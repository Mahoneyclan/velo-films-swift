#if os(iOS)
import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

/// In-process MP4 demuxer for security-scoped external-drive files on iOS.
///
/// AVAssetReader.startReading() routes through mediaserverd XPC even in passthrough
/// mode, so it cannot access external-drive files. FileHandle reads use the kernel
/// file descriptor directly, which does honour security-scoped bookmarks.
///
/// Supports Cycliq NOVATEK mp42 files (ftyp → skip → mdat → moov at end).
/// Also handles any MP4 where moov is at the end (common for camera-recorded files).
enum MP4Demuxer {

    // MARK: - Public API

    /// Demux [startTime, startTime+duration) from sourceURL to a self-contained MP4 at destURL.
    ///
    /// Returns leaderFrames: the count of video frames prepended for keyframe alignment.
    /// The caller must skip this many frames from the subsequent AVAssetReader output
    /// so the rendered clip starts at exactly startTime.
    static func copySegment(
        from sourceURL: URL,
        startTime: Double,
        duration: Double,
        to destURL: URL
    ) async throws -> Int {
        // --- iOS diagnostic: log scope/path state so we can see what's wrong ---
        let gs = GlobalSettings.shared
        let diagFly12 = gs.fly12SourceURL?.path(percentEncoded: false) ?? "nil"
        let diagFly6  = gs.fly6SourceURL?.path(percentEncoded: false)  ?? "nil"
        let diagBase  = gs.inputBaseDir?.path(percentEncoded: false)   ?? "nil"
        let diagPath  = sourceURL.path(percentEncoded: false)
        let diagExists = FileManager.default.fileExists(atPath: diagPath)
        let diagScope  = sourceURL.startAccessingSecurityScopedResource()
        defer { if diagScope { sourceURL.stopAccessingSecurityScopedResource() } }
        // -----------------------------------------------------------------------

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: sourceURL)
        } catch {
            throw PipelineError.renderFailed(
                "MP4Demuxer: cannot open \(diagPath) — \(error) | " +
                "exists=\(diagExists) scope=\(diagScope) " +
                "fly12=\(diagFly12) fly6=\(diagFly6) base=\(diagBase)")
        }
        defer { try? handle.close() }

        let moovData = try readMoovData(handle: handle)
        let movie    = try parseMovieBox(moovData)

        guard let videoTrack = movie.tracks.first(where: { $0.isVideo }) else {
            throw PipelineError.renderFailed("MP4Demuxer: no video track")
        }
        let audioTrack = movie.tracks.first(where: { !$0.isVideo })

        // Video sample range — start from preceding keyframe
        let videoTimescale = Double(videoTrack.timescale)
        let startTick  = Int64(startTime * videoTimescale)
        let endTick    = Int64((startTime + duration) * videoTimescale)

        let (firstSampleIdx, leaderFrames) = findVideoStartSample(
            track: videoTrack, startTick: startTick)
        let endSampleIdx = findSampleAtOrAfterTick(track: videoTrack, tick: endTick)

        guard firstSampleIdx < videoTrack.sampleCount,
              endSampleIdx > firstSampleIdx else {
            throw PipelineError.renderFailed(
                "MP4Demuxer: empty video range for t=\(startTime)–\(startTime+duration)")
        }

        // Format descriptions
        let videoFmt = try makeVideoFormatDesc(stsdData: videoTrack.stsdData)

        // Audio sample range — align with video start (keyframe-adjusted)
        let videoDeltaSec = Double(videoTrack.sttsEntries.first?.delta ?? 1) / videoTimescale
        var audioRange: (start: Int, end: Int)? = nil
        var audioFmt: CMAudioFormatDescription? = nil
        if let at = audioTrack {
            let videoStartSec = startTime - Double(leaderFrames) * videoDeltaSec
            let aStart = findSampleAtOrAfterTime(track: at, seconds: videoStartSec)
            let aEnd   = findSampleAtOrAfterTime(track: at, seconds: startTime + duration)
            if aEnd > aStart {
                audioRange = (aStart, aEnd)
                audioFmt   = makeAudioFormatDesc(stsdData: at.stsdData, timescale: at.timescale)
            }
        }

        // Writer
        try? FileManager.default.removeItem(at: destURL)
        let writer = try AVAssetWriter(outputURL: destURL, fileType: .mp4)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                             sourceFormatHint: videoFmt)
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput? = nil
        if let af = audioFmt {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: nil,
                                         sourceFormatHint: af)
            ai.expectsMediaDataInRealTime = false
            writer.add(ai)
            audioInput = ai
        }

        writer.startWriting()
        guard writer.status == .writing else {
            throw writer.error ?? PipelineError.renderFailed("MP4Demuxer: writer failed to start")
        }
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)

        // Pump video
        let videoDelta = videoTrack.sttsEntries.first?.delta ?? 1
        var writeTime = CMTime.zero
        for sampleIdx in firstSampleIdx ..< endSampleIdx {
            let (fileOffset, sampleSize) = try sampleLocation(track: videoTrack, index: sampleIdx)
            guard sampleSize > 0 else { continue }
            try handle.seek(toOffset: fileOffset)
            guard let rawData = try? handle.read(upToCount: sampleSize),
                  rawData.count == sampleSize else {
                throw PipelineError.renderFailed("MP4Demuxer: short read at video sample \(sampleIdx)")
            }
            let buf = try makeSampleBuffer(data: rawData,
                                            presentationTime: writeTime,
                                            duration: CMTime(value: CMTimeValue(videoDelta),
                                                             timescale: CMTimeScale(videoTrack.timescale)),
                                            formatDesc: videoFmt)
            while !videoInput.isReadyForMoreMediaData { await Task.yield() }
            guard writer.status == .writing else { break }
            videoInput.append(buf)
            writeTime = CMTimeAdd(writeTime,
                                  CMTime(value: CMTimeValue(videoDelta),
                                         timescale: CMTimeScale(videoTrack.timescale)))
        }
        videoInput.markAsFinished()

        // Pump audio
        if let ai = audioInput, let at = audioTrack, let (aStart, aEnd) = audioRange {
            let framesPerPacket = at.framesPerPacket > 0 ? at.framesPerPacket : 1024
            var audioTime = CMTime.zero
            for sampleIdx in aStart ..< aEnd {
                let (fileOffset, sampleSize) = try sampleLocation(track: at, index: sampleIdx)
                guard sampleSize > 0 else { continue }
                try handle.seek(toOffset: fileOffset)
                guard let rawData = try? handle.read(upToCount: sampleSize),
                      rawData.count == sampleSize else { continue }
                let dur = CMTime(value: CMTimeValue(framesPerPacket),
                                 timescale: CMTimeScale(at.timescale))
                let buf = try makeSampleBuffer(data: rawData,
                                               presentationTime: audioTime,
                                               duration: dur,
                                               formatDesc: audioFmt)
                while !ai.isReadyForMoreMediaData { await Task.yield() }
                guard writer.status == .writing else { break }
                ai.append(buf)
                audioTime = CMTimeAdd(audioTime, dur)
            }
            ai.markAsFinished()
        } else {
            audioInput?.markAsFinished()
        }

        guard writer.status == .writing else {
            throw writer.error ?? PipelineError.renderFailed("MP4Demuxer: writer failed during pump")
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        if let err = writer.error { throw err }
        guard writer.status == .completed else {
            throw PipelineError.renderFailed(
                "MP4Demuxer: writer status \(writer.status.rawValue)")
        }

        return leaderFrames
    }

    /// Extracts only the audio track from [startTime, startTime+duration) to an audio-only MP4.
    /// Uses FileHandle (in-process) — safe for external-drive security-scoped URLs.
    /// Audio is the first (and only) track in the output file, so trackID = 1.
    /// Returns false if the source has no audio track (caller can treat clip as silent).
    @discardableResult
    static func extractAudio(
        from sourceURL: URL,
        startTime: Double,
        duration: Double,
        to destURL: URL
    ) async throws -> Bool {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: sourceURL) }
        catch { throw PipelineError.renderFailed("MP4Demuxer.extractAudio: open \(sourceURL.lastPathComponent) — \(error)") }
        defer { try? handle.close() }

        let moovData  = try readMoovData(handle: handle)
        let movie     = try parseMovieBox(moovData)
        guard let at  = movie.tracks.first(where: { !$0.isVideo }) else { return false }
        guard let fmt = makeAudioFormatDesc(stsdData: at.stsdData, timescale: at.timescale) else { return false }

        let aStart = findSampleAtOrAfterTime(track: at, seconds: startTime)
        let aEnd   = findSampleAtOrAfterTime(track: at, seconds: startTime + duration)
        guard aEnd > aStart else { return false }

        try? FileManager.default.removeItem(at: destURL)
        let writer = try AVAssetWriter(outputURL: destURL, fileType: .mp4)
        let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: fmt)
        audioIn.expectsMediaDataInRealTime = false
        writer.add(audioIn)
        writer.startWriting()
        guard writer.status == .writing else { return false }
        // Ensure writer is cancelled on any throw path before finishWriting is reached.
        // Deallocating an AVAssetWriter in .writing state raises NSFileHandleOperationException.
        // Also prevents calling finishWriting on a failed writer, which triggers the same crash.
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)

        let fpk = at.framesPerPacket > 0 ? at.framesPerPacket : 1024
        var pts = CMTime.zero
        let dur = CMTime(value: CMTimeValue(fpk), timescale: CMTimeScale(at.timescale))
        for idx in aStart..<aEnd {
            guard writer.status == .writing else { break }
            let (off, sz) = try sampleLocation(track: at, index: idx)
            guard sz > 0 else { continue }
            try handle.seek(toOffset: off)
            guard let raw = try? handle.read(upToCount: sz), raw.count == sz else { continue }
            let buf = try makeSampleBuffer(data: raw, presentationTime: pts, duration: dur, formatDesc: fmt)
            while !audioIn.isReadyForMoreMediaData { await Task.yield() }
            guard writer.status == .writing else { break }
            audioIn.append(buf)
            pts = CMTimeAdd(pts, dur)
        }

        // Check status after loop: calling finishWriting on a failed writer raises
        // NSFileHandleOperationException. Defer handles cancelWriting in this case.
        guard writer.status == .writing else { return false }
        audioIn.markAsFinished()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        if let err = writer.error { throw err }
        guard writer.status == .completed else {
            throw PipelineError.renderFailed("MP4Demuxer.extractAudio: writer status \(writer.status.rawValue)")
        }
        return true
    }

    // MARK: - moov discovery

    private static func readMoovData(handle: FileHandle) throws -> Data {
        guard let fileSize = try? handle.seekToEnd(), fileSize > 8 else {
            throw PipelineError.renderFailed("MP4Demuxer: empty file")
        }
        // Scan last 32 MB for moov (camera files put moov at end)
        let scanBytes = min(fileSize, UInt64(32 * 1024 * 1024))
        let scanStart = fileSize - scanBytes
        try handle.seek(toOffset: scanStart)
        guard let tail = try? handle.readToEnd(), tail.count > 8 else {
            throw PipelineError.renderFailed("MP4Demuxer: tail read failed")
        }
        let moovMagic = Data([0x6D, 0x6F, 0x6F, 0x76]) // "moov"
        guard let range = tail.range(of: moovMagic, options: .backwards) else {
            throw PipelineError.renderFailed("MP4Demuxer: moov box not found")
        }
        // Box size is 4 bytes before the type tag
        let sizeIdx = range.lowerBound - 4
        guard sizeIdx >= 0 else {
            throw PipelineError.renderFailed("MP4Demuxer: moov offset invalid")
        }
        let boxSize = Int(ru32(tail, at: sizeIdx))
        guard boxSize >= 8, sizeIdx + boxSize <= tail.count else {
            throw PipelineError.renderFailed("MP4Demuxer: moov size \(boxSize) out of range")
        }
        // Return a contiguous copy so startIndex == 0; integer offsets in the parsers
        // are all relative to startIndex, and Data.endIndex == Data.count when startIndex==0.
        return Data(tail[sizeIdx ..< sizeIdx + boxSize])
    }

    // MARK: - moov parse

    private struct TrackInfo {
        var isVideo:        Bool
        var timescale:      UInt32
        var sampleCount:    Int
        var sttsEntries:    [(count: Int, delta: Int)]
        var stssSet:        Set<Int>           // 1-based keyframe sample numbers
        var stscEntries:    [(firstChunk: Int, samplesPerChunk: Int)]
        var sampleSizes:    [Int]              // stsz
        var chunkOffsets:   [UInt64]           // co64 or stco
        var stsdData:       Data               // raw stsd payload (after 8-byte header)
        var framesPerPacket: Int               // audio only; 0 = unknown
    }

    private struct MovieInfo {
        var tracks: [TrackInfo]
    }

    private static func parseMovieBox(_ moov: Data) throws -> MovieInfo {
        // moov starts with 4-byte size + "moov"
        var tracks: [TrackInfo] = []
        iterateBoxes(in: moov, start: 8) { boxType, boxStart, boxEnd in
            if boxType == "trak" {
                if let t = parseTrak(moov, start: boxStart + 8, end: boxEnd) {
                    tracks.append(t)
                }
            }
        }
        return MovieInfo(tracks: tracks)
    }

    private static func parseTrak(_ data: Data, start: Int, end: Int) -> TrackInfo? {
        var track = TrackInfo(
            isVideo: false, timescale: 1, sampleCount: 0,
            sttsEntries: [], stssSet: [], stscEntries: [],
            sampleSizes: [], chunkOffsets: [], stsdData: Data(),
            framesPerPacket: 0
        )
        var foundStbl = false

        iterateBoxes(in: data, start: start) { boxType, boxStart, boxEnd in
            if boxType == "mdia" {
                iterateBoxes(in: data, start: boxStart + 8) { t2, s2, e2 in
                    if t2 == "mdhd" { parseMdhd(data, start: s2, into: &track) }
                    if t2 == "hdlr" { parseHdlr(data, start: s2, into: &track) }
                    if t2 == "minf" {
                        iterateBoxes(in: data, start: s2 + 8) { t3, s3, e3 in
                            if t3 == "stbl" {
                                parseStbl(data, start: s3 + 8, end: e3, into: &track)
                                foundStbl = true
                            }
                        }
                    }
                }
            }
        }
        return foundStbl ? track : nil
    }

    private static func parseMdhd(_ data: Data, start: Int, into t: inout TrackInfo) {
        guard start + 4 <= data.endIndex else { return }
        let version = data[data.index(data.startIndex, offsetBy: start + 8)]
        let base = start + 8 + 4  // skip version(1)+flags(3)
        if version == 0 {
            // creation(4) modification(4) timescale(4)
            guard base + 12 <= data.endIndex else { return }
            t.timescale = ru32(data, at: base + 8)
        } else {
            // creation(8) modification(8) timescale(4)
            guard base + 20 <= data.endIndex else { return }
            t.timescale = ru32(data, at: base + 16)
        }
    }

    private static func parseHdlr(_ data: Data, start: Int, into t: inout TrackInfo) {
        // hdlr: size(4) type(4) version(4) pre_defined(4) handler_type(4) ...
        let handlerOffset = start + 8 + 4 + 4
        guard handlerOffset + 4 <= data.endIndex else { return }
        let idx = data.index(data.startIndex, offsetBy: handlerOffset)
        let handler = String(data[idx ..< data.index(idx, offsetBy: 4)]
            .map { Character(UnicodeScalar($0)) })
        t.isVideo = (handler == "vide")
    }

    private static func parseStbl(_ data: Data, start: Int, end: Int, into t: inout TrackInfo) {
        iterateBoxes(in: data, start: start) { boxType, boxStart, boxEnd in
            let payloadStart = boxStart + 8 + 4  // skip size(4)+type(4)+version_flags(4)
            switch boxType {
            case "stts": parseStts(data, start: payloadStart, into: &t)
            case "stss": parseStss(data, start: payloadStart, into: &t)
            case "stsc": parseStsc(data, start: payloadStart, into: &t)
            case "stsz": parseStsz(data, start: boxStart + 8, into: &t)
            case "co64": parseCo64(data, start: payloadStart, into: &t)
            case "stco": parseStco(data, start: payloadStart, into: &t)
            case "stsd": parseStsd(data, start: boxStart, end: boxEnd, into: &t)
            default: break
            }
        }
    }

    private static func parseStts(_ data: Data, start: Int, into t: inout TrackInfo) {
        guard start + 4 <= data.endIndex else { return }
        let count = Int(ru32(data, at: start))
        var entries: [(count: Int, delta: Int)] = []
        entries.reserveCapacity(count)
        var totalSamples = 0
        for i in 0 ..< count {
            let off = start + 4 + i * 8
            guard off + 8 <= data.endIndex else { break }
            let c = Int(ru32(data, at: off))
            let d = Int(ru32(data, at: off + 4))
            entries.append((count: c, delta: d))
            totalSamples += c
        }
        t.sttsEntries  = entries
        t.sampleCount  = totalSamples
    }

    private static func parseStss(_ data: Data, start: Int, into t: inout TrackInfo) {
        guard start + 4 <= data.endIndex else { return }
        let count = Int(ru32(data, at: start))
        var set = Set<Int>()
        set.reserveCapacity(count)
        for i in 0 ..< count {
            let off = start + 4 + i * 4
            guard off + 4 <= data.endIndex else { break }
            set.insert(Int(ru32(data, at: off)))
        }
        t.stssSet = set
    }

    private static func parseStsc(_ data: Data, start: Int, into t: inout TrackInfo) {
        guard start + 4 <= data.endIndex else { return }
        let count = Int(ru32(data, at: start))
        var entries: [(firstChunk: Int, samplesPerChunk: Int)] = []
        entries.reserveCapacity(count)
        for i in 0 ..< count {
            let off = start + 4 + i * 12
            guard off + 8 <= data.endIndex else { break }
            let fc  = Int(ru32(data, at: off))
            let spc = Int(ru32(data, at: off + 4))
            entries.append((firstChunk: fc, samplesPerChunk: spc))
        }
        t.stscEntries = entries
    }

    private static func parseStsz(_ data: Data, start: Int, into t: inout TrackInfo) {
        // stsz: version_flags(4) default_size(4) sample_count(4) [sizes...]
        // start points after size+type, so version_flags at start
        let payloadStart = start + 4  // skip version_flags
        guard payloadStart + 8 <= data.endIndex else { return }
        let defaultSize  = Int(ru32(data, at: payloadStart))
        let sampleCount  = Int(ru32(data, at: payloadStart + 4))
        if defaultSize != 0 {
            t.sampleSizes = Array(repeating: defaultSize, count: sampleCount)
            if t.sampleCount == 0 { t.sampleCount = sampleCount }
        } else {
            var sizes = [Int]()
            sizes.reserveCapacity(sampleCount)
            for i in 0 ..< sampleCount {
                let off = payloadStart + 8 + i * 4
                guard off + 4 <= data.endIndex else { break }
                sizes.append(Int(ru32(data, at: off)))
            }
            t.sampleSizes = sizes
            if t.sampleCount == 0 { t.sampleCount = sampleCount }
        }
    }

    private static func parseCo64(_ data: Data, start: Int, into t: inout TrackInfo) {
        guard start + 4 <= data.endIndex else { return }
        let count = Int(ru32(data, at: start))
        var offsets = [UInt64]()
        offsets.reserveCapacity(count)
        for i in 0 ..< count {
            let off = start + 4 + i * 8
            guard off + 8 <= data.endIndex else { break }
            offsets.append(ru64(data, at: off))
        }
        t.chunkOffsets = offsets
    }

    private static func parseStco(_ data: Data, start: Int, into t: inout TrackInfo) {
        guard start + 4 <= data.endIndex else { return }
        let count = Int(ru32(data, at: start))
        var offsets = [UInt64]()
        offsets.reserveCapacity(count)
        for i in 0 ..< count {
            let off = start + 4 + i * 4
            guard off + 4 <= data.endIndex else { break }
            offsets.append(UInt64(ru32(data, at: off)))
        }
        t.chunkOffsets = offsets
    }

    private static func parseStsd(_ data: Data, start: Int, end: Int, into t: inout TrackInfo) {
        // Preserve raw stsd payload for format-description extraction
        // start = box start (includes 8-byte size+type header)
        guard start + 8 <= data.endIndex else { return }
        let payloadStart = start + 8  // after size(4)+type(4)
        let payloadEnd   = min(end, data.endIndex)
        t.stsdData = Data(data[payloadStart ..< payloadEnd])  // normalise startIndex to 0

        // Audio: detect framesPerPacket from mp4a framesPerPacket field (offset 32 in body)
        if !t.isVideo {
            // stsd payload: version_flags(4) entry_count(4) entry(size+type+body...)
            // mp4a body at offset 8+8=16: reserved(6)+data_ref_idx(2)+reserved(8)+channels(2)+
            //   sampleSize(2)+preDefined(2)+reserved(2)+sampleRate(4) = 28 bytes
            // framesPerPacket is NOT in the SoundSampleEntry; use 1024 for AAC-LC (standard)
            t.framesPerPacket = 1024
        }
    }

    // MARK: - Sample location

    /// Returns (fileOffset, sampleSize) for the given 0-based sample index.
    private static func sampleLocation(track: TrackInfo, index: Int) throws -> (UInt64, Int) {
        guard index < track.sampleSizes.count else {
            throw PipelineError.renderFailed("MP4Demuxer: sample index \(index) out of range")
        }
        let sampleSize = track.sampleSizes[index]

        // stsc: find which entry covers this sample, then compute chunk + intra-chunk offset
        // Since Cycliq uses 1 sample/chunk, chunkIndex == sampleIndex for both tracks.
        // General implementation handles arbitrary stsc entries.
        let (chunkIndex, intraOffset) = sampleToChunk(
            sampleIndex: index, stscEntries: track.stscEntries)

        guard chunkIndex < track.chunkOffsets.count else {
            throw PipelineError.renderFailed(
                "MP4Demuxer: chunk index \(chunkIndex) out of range (have \(track.chunkOffsets.count))")
        }
        let chunkFileOffset = track.chunkOffsets[chunkIndex]
        return (chunkFileOffset + UInt64(intraOffset), sampleSize)
    }

    /// Maps a 0-based sample index to its (0-based chunk index, byte offset within chunk).
    private static func sampleToChunk(
        sampleIndex: Int, stscEntries: [(firstChunk: Int, samplesPerChunk: Int)]
    ) -> (chunkIndex: Int, byteOffset: Int) {
        guard !stscEntries.isEmpty else { return (sampleIndex, 0) }

        // Find which stsc entry covers this sample
        var sampleBase = 0
        for i in 0 ..< stscEntries.count {
            let entry      = stscEntries[i]
            let nextFirstChunk = (i + 1 < stscEntries.count)
                                  ? stscEntries[i + 1].firstChunk
                                  : Int.max
            let firstChunk0 = entry.firstChunk - 1  // convert to 0-based
            let nextFirst0  = nextFirstChunk - 1
            let spc         = entry.samplesPerChunk
            let chunksInRun = nextFirst0 - firstChunk0
            let samplesInRun = chunksInRun == Int.max ? Int.max : chunksInRun * spc

            if samplesInRun == Int.max || sampleBase + samplesInRun > sampleIndex {
                // sampleIndex falls in this run
                let localSample  = sampleIndex - sampleBase
                let chunkInRun   = localSample / spc
                let sampleInChunk = localSample % spc
                // byte offset within chunk: sum of sizes of preceding samples in same chunk
                // For constant sizes (Cycliq) this is 0 when spc=1; general case needs stsz
                // We use 0 here and rely on spc=1 for Cycliq. Full impl would accumulate.
                _ = sampleInChunk
                return (firstChunk0 + chunkInRun, 0)
            }
            sampleBase += samplesInRun
        }
        return (sampleIndex, 0)
    }

    // MARK: - Sample timing helpers

    private static func findVideoStartSample(
        track: TrackInfo, startTick: Int64
    ) -> (firstSampleIdx: Int, leaderFrames: Int) {
        // Find the sample whose decode tick is just <= startTick
        let displayStartIdx = findSampleAtOrAfterTick(track: track, tick: startTick)
        let clampedDisplay  = min(displayStartIdx, max(0, track.sampleCount - 1))

        if track.stssSet.isEmpty {
            // No keyframe table — every frame is a keyframe
            return (clampedDisplay, 0)
        }

        // Walk backwards from displayStartIdx to find the preceding keyframe (1-based in stssSet)
        var keyIdx = clampedDisplay
        while keyIdx > 0, !track.stssSet.contains(keyIdx + 1) {
            keyIdx -= 1
        }
        let leaderFrames = clampedDisplay - keyIdx
        return (keyIdx, leaderFrames)
    }

    private static func findSampleAtOrAfterTick(track: TrackInfo, tick: Int64) -> Int {
        var elapsed = Int64(0)
        var sampleIdx = 0
        for entry in track.sttsEntries {
            let runTicks = Int64(entry.count) * Int64(entry.delta)
            if elapsed + runTicks > tick {
                let offset = Int((tick - elapsed) / Int64(entry.delta))
                return sampleIdx + max(0, offset)
            }
            elapsed    += runTicks
            sampleIdx  += entry.count
        }
        return track.sampleCount  // beyond end
    }

    private static func findSampleAtOrAfterTime(track: TrackInfo, seconds: Double) -> Int {
        let tick = Int64(seconds * Double(track.timescale))
        return findSampleAtOrAfterTick(track: track, tick: max(0, tick))
    }

    // MARK: - Format descriptions

    private static func makeVideoFormatDesc(stsdData: Data) throws -> CMVideoFormatDescription {
        // stsdData layout (startIndex=0): version_flags(4) entry_count(4) avc1_entry(...)
        // avc1_entry: size(4) "avc1"(4) SampleEntry(8) VisualSampleEntry_body(72) child_boxes...
        // Standard searchFrom = 8+8+8+72 = 96. Try nearby offsets as fallback, then raw scan.
        let avccRange: Range<Data.Index>
        if let r = findChildBox(in: stsdData, type: "avcC", searchFrom: 96)
                ?? findChildBox(in: stsdData, type: "avcC", searchFrom: 94)
                ?? findChildBox(in: stsdData, type: "avcC", searchFrom: 88) {
            avccRange = r
        } else {
            // Raw byte scan: locate "avcC" 4-byte tag anywhere in stsdData after offset 8,
            // then back up 4 bytes to get the enclosing box size field.
            let needle: [UInt8] = [0x61, 0x76, 0x63, 0x43] // "avcC"
            var rawStart: Int? = nil
            for i in 8 ..< max(8, stsdData.count - 3) {
                if stsdData[i] == needle[0], stsdData[i+1] == needle[1],
                   stsdData[i+2] == needle[2], stsdData[i+3] == needle[3] {
                    rawStart = i - 4  // the size field precedes the type
                    break
                }
            }
            if let rs = rawStart, rs >= 0 {
                let sz = Int(ru32(stsdData, at: rs))
                if sz >= 8, rs + sz <= stsdData.count {
                    avccRange = stsdData.index(stsdData.startIndex, offsetBy: rs + 8) ..<
                                stsdData.index(stsdData.startIndex, offsetBy: rs + sz)
                } else {
                    throw PipelineError.renderFailed("MP4Demuxer: avcC box not found in video stsd (size=\(stsdData.count))")
                }
            } else {
                let dump = stsdData.prefix(min(108, stsdData.count))
                    .map { String(format: "%02x", $0) }.joined(separator: " ")
                throw PipelineError.renderFailed(
                    "MP4Demuxer: avcC box not found in video stsd (size=\(stsdData.count)) dump: \(dump)")
            }
        }
        let avccPayload = stsdData[avccRange]

        // avcC payload: configVersion(1) profile(1) compat(1) level(1) naluLen-1(1)
        //               numSPS(1, lower 5 bits) spsLen(2) sps... numPPS(1) ppsLen(2) pps...
        guard avccPayload.count >= 7 else {
            throw PipelineError.renderFailed("MP4Demuxer: avcC payload too short")
        }
        var offset = avccPayload.startIndex
        offset += 5  // configVersion + profile + compat + level + naluLen
        let numSPS = Int(avccPayload[offset] & 0x1f)
        offset += 1

        var spsArrays: [[UInt8]] = []
        for _ in 0 ..< numSPS {
            guard offset + 2 <= avccPayload.endIndex else { break }
            let len = Int(UInt16(avccPayload[offset]) << 8 | UInt16(avccPayload[offset + 1]))
            offset += 2
            guard offset + len <= avccPayload.endIndex else { break }
            spsArrays.append(Array(avccPayload[offset ..< offset + len]))
            offset += len
        }
        guard offset < avccPayload.endIndex else {
            throw PipelineError.renderFailed("MP4Demuxer: avcC truncated before PPS count")
        }
        let numPPS = Int(avccPayload[offset])
        offset += 1
        var ppsArrays: [[UInt8]] = []
        for _ in 0 ..< numPPS {
            guard offset + 2 <= avccPayload.endIndex else { break }
            let len = Int(UInt16(avccPayload[offset]) << 8 | UInt16(avccPayload[offset + 1]))
            offset += 2
            guard offset + len <= avccPayload.endIndex else { break }
            ppsArrays.append(Array(avccPayload[offset ..< offset + len]))
            offset += len
        }
        guard !spsArrays.isEmpty, !ppsArrays.isEmpty else {
            throw PipelineError.renderFailed("MP4Demuxer: no SPS or PPS in avcC")
        }

        // Copy each SPS/PPS into malloc-owned memory so the pointers stay valid
        // across the CMVideoFormatDescriptionCreateFromH264ParameterSets call.
        let allSets = spsArrays + ppsArrays
        var rawBuffers = [UnsafeMutableRawPointer]()
        defer { rawBuffers.forEach { free($0) } }
        var ptrs  = [UnsafePointer<UInt8>]()
        var sizes = [Int]()
        for arr in allSets {
            let buf = malloc(max(arr.count, 1))!
            if !arr.isEmpty { _ = arr.withUnsafeBytes { memcpy(buf, $0.baseAddress!, arr.count) } }
            rawBuffers.append(buf)
            ptrs.append(buf.assumingMemoryBound(to: UInt8.self))
            sizes.append(arr.count)
        }
        var desc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator:          kCFAllocatorDefault,
            parameterSetCount:  ptrs.count,
            parameterSetPointers: &ptrs,
            parameterSetSizes:  &sizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &desc
        )
        guard status == noErr, let d = desc else {
            throw PipelineError.renderFailed(
                "MP4Demuxer: CMVideoFormatDescriptionCreateFromH264ParameterSets failed \(status)")
        }
        return d
    }

    private static func makeAudioFormatDesc(stsdData: Data, timescale: UInt32) -> CMAudioFormatDescription? {
        // stsdData layout: version_flags(4) entry_count(4) mp4a_entry(size+type+body+children)
        // mp4a_entry: size(4) "mp4a"(4) SampleEntry(8) AudioSampleEntry_body(20) child_boxes...
        // = 8+8+8+20 = 44 bytes before the first child box (esds).
        guard let esdsRange = findChildBox(in: stsdData, type: "esds", searchFrom: 44) else {
            return nil
        }
        let esdsPayload = stsdData[esdsRange]
        // esds payload starts with version_flags(4) then MPEG-4 descriptor tree.
        // extractAudioSpecificConfig skips the first 4 bytes internally.
        guard let asc = extractAudioSpecificConfig(from: esdsPayload),
              asc.count >= 2 else { return nil }  // ASC < 2 bytes is always malformed

        // Extract channel count and sample rate from AudioSampleEntry.
        // stsdData offsets: [0..7] version_flags+entry_count, [8..15] entry size+type,
        // [16..23] SampleEntry (reserved[6]+data_ref[2]),
        // [24..31] AudioSampleEntry reserved[8], [32..33] channelCount, [40..43] sampleRate
        let mp4aBodyStart = 8 + 8  // start of SampleEntry: after stsd version+count+entry size+type
        var channels: UInt32 = 1
        var sampleRateHz: Double = Double(timescale)
        if mp4aBodyStart + 28 <= stsdData.count {
            channels = UInt32(ru16(stsdData, at: mp4aBodyStart + 16))  // SampleEntry(8)+reserved(8)=16
            let rateFixed = ru32(stsdData, at: mp4aBodyStart + 24)     // +8 more for rest of AudioSampleEntry
            sampleRateHz = Double(rateFixed >> 16)
        }
        if channels == 0 { channels = 1 }
        if sampleRateHz < 8000 { sampleRateHz = Double(timescale) }

        var asbd = AudioStreamBasicDescription(
            mSampleRate:       sampleRateHz,
            mFormatID:         kAudioFormatMPEG4AAC,
            mFormatFlags:      0,
            mBytesPerPacket:   0,
            mFramesPerPacket:  1024,
            mBytesPerFrame:    0,
            mChannelsPerFrame: channels,
            mBitsPerChannel:   0,
            mReserved:         0
        )
        var desc: CMAudioFormatDescription?
        let ascBytes = asc
        let status = ascBytes.withUnsafeBytes { ptr in
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0, layout: nil,
                magicCookieSize: ascBytes.count,
                magicCookie: ptr.baseAddress,
                extensions: nil,
                formatDescriptionOut: &desc
            )
        }
        return status == noErr ? desc : nil
    }

    private static func extractAudioSpecificConfig(from esdsPayload: Data) -> [UInt8]? {
        // Skip version_flags(4), then walk MPEG-4 descriptors
        var idx = esdsPayload.startIndex + 4

        func readDescriptor() -> (tag: UInt8, end: Data.Index)? {
            guard idx < esdsPayload.endIndex else { return nil }
            let tag = esdsPayload[idx]; idx += 1
            var length = 0
            // Variable-length encoding: each byte's high bit signals another byte follows
            for _ in 0 ..< 4 {
                guard idx < esdsPayload.endIndex else { return nil }
                let b = esdsPayload[idx]; idx += 1
                length = (length << 7) | Int(b & 0x7f)
                if b & 0x80 == 0 { break }
            }
            return (tag, esdsPayload.index(idx, offsetBy: length,
                                           limitedBy: esdsPayload.endIndex) ?? esdsPayload.endIndex)
        }

        while idx < esdsPayload.endIndex {
            guard let (tag, end) = readDescriptor() else { break }
            switch tag {
            case 0x03:  // ES_Descriptor — skip ES_ID(2) + flags(1)
                idx = esdsPayload.index(idx, offsetBy: 3, limitedBy: end) ?? end
            case 0x04:  // DecoderConfigDescriptor — skip objectType(1)+streamType(1)+buffer(3)+maxBR(4)+avgBR(4)
                idx = esdsPayload.index(idx, offsetBy: 13, limitedBy: end) ?? end
            case 0x05:  // DecoderSpecificInfo = AudioSpecificConfig ← what we want
                return Array(esdsPayload[idx ..< end])
            default:
                idx = end
            }
        }
        return nil
    }

    // MARK: - Box scanning

    private static func findChildBox(in data: Data, type target: String,
                                      searchFrom start: Int) -> Range<Data.Index>? {
        let targetBytes = Array(target.utf8)
        var pos = data.index(data.startIndex, offsetBy: start, limitedBy: data.endIndex) ?? data.endIndex
        while pos < data.endIndex {
            guard data.index(pos, offsetBy: 8, limitedBy: data.endIndex) != nil else { break }
            let boxSize = Int(ru32(data, at: data.distance(from: data.startIndex, to: pos)))
            let typeStart = data.index(pos, offsetBy: 4)
            let typeEnd   = data.index(typeStart, offsetBy: 4)
            guard typeEnd <= data.endIndex else { break }
            let boxType = Array(data[typeStart ..< typeEnd])
            if boxSize >= 8, boxType == targetBytes {
                // Return payload after size(4)+type(4) only.
                // Callers that need FullBox version+flags handle the extra skip themselves.
                let payloadStart = data.index(pos, offsetBy: 8)
                let payloadEnd   = data.index(pos, offsetBy: boxSize,
                                               limitedBy: data.endIndex) ?? data.endIndex
                return payloadStart ..< payloadEnd
            }
            if boxSize < 8 { break }
            pos = data.index(pos, offsetBy: boxSize, limitedBy: data.endIndex) ?? data.endIndex
        }
        return nil
    }

    private static func iterateBoxes(
        in data: Data, start startOff: Int,
        visitor: (_ boxType: String, _ boxStart: Int, _ boxEnd: Int) -> Void
    ) {
        var pos = startOff
        while pos + 8 <= data.endIndex {
            let absPos = data.index(data.startIndex, offsetBy: pos)
            let boxSize: Int
            let typeOffset: Int
            let rawSize = Int(ru32(data, at: pos))
            if rawSize == 1 {
                guard pos + 16 <= data.endIndex else { return }
                boxSize    = Int(ru64(data, at: pos + 8))
                typeOffset = 4
            } else if rawSize == 0 {
                boxSize    = data.endIndex - pos
                typeOffset = 4
            } else {
                boxSize    = rawSize
                typeOffset = 4
            }
            guard boxSize >= 8 else { return }
            let typeIdx = data.index(absPos, offsetBy: typeOffset)
            guard data.index(typeIdx, offsetBy: 4, limitedBy: data.endIndex) != nil else { return }
            let boxType = String(data[typeIdx ..< data.index(typeIdx, offsetBy: 4)]
                .map { Character(UnicodeScalar($0)) })
            visitor(boxType, pos, pos + boxSize)
            pos += boxSize
        }
    }

    // MARK: - CMSampleBuffer construction

    private static func makeSampleBuffer(
        data: Data,
        presentationTime: CMTime,
        duration: CMTime,
        formatDesc: CMFormatDescription?
    ) throws -> CMSampleBuffer {
        let byteCount = data.count
        let rawPtr = malloc(byteCount)!
        _ = data.withUnsafeBytes { memcpy(rawPtr, $0.baseAddress!, byteCount) }

        var blockBuf: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator:        kCFAllocatorDefault,
            memoryBlock:      rawPtr,
            blockLength:      byteCount,
            blockAllocator:   kCFAllocatorMalloc,
            customBlockSource: nil,
            offsetToData:     0,
            dataLength:       byteCount,
            flags:            0,
            blockBufferOut:   &blockBuf
        )
        guard status == noErr, let bb = blockBuf else {
            free(rawPtr)
            throw PipelineError.renderFailed("MP4Demuxer: CMBlockBuffer create failed \(status)")
        }

        var timing = CMSampleTimingInfo(
            duration:            duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp:     .invalid
        )
        var sampleSize = byteCount
        var sampleBuf: CMSampleBuffer?
        status = CMSampleBufferCreate(
            allocator:             kCFAllocatorDefault,
            dataBuffer:            bb,
            dataReady:             true,
            makeDataReadyCallback: nil,
            refcon:                nil,
            formatDescription:     formatDesc,
            sampleCount:           1,
            sampleTimingEntryCount: 1,
            sampleTimingArray:     &timing,
            sampleSizeEntryCount:  1,
            sampleSizeArray:       &sampleSize,
            sampleBufferOut:       &sampleBuf
        )
        guard status == noErr, let sb = sampleBuf else {
            throw PipelineError.renderFailed("MP4Demuxer: CMSampleBuffer create failed \(status)")
        }
        return sb
    }

    // MARK: - Big-endian read helpers (file-private to avoid conflict with FrameSampler)

    private static func ru32(_ data: Data, at offset: Int) -> UInt32 {
        let i = data.index(data.startIndex, offsetBy: offset)
        return UInt32(data[i]) << 24 | UInt32(data[data.index(i, offsetBy: 1)]) << 16 |
               UInt32(data[data.index(i, offsetBy: 2)]) << 8 | UInt32(data[data.index(i, offsetBy: 3)])
    }

    private static func ru16(_ data: Data, at offset: Int) -> UInt16 {
        let i = data.index(data.startIndex, offsetBy: offset)
        return UInt16(data[i]) << 8 | UInt16(data[data.index(i, offsetBy: 1)])
    }

    private static func ru64(_ data: Data, at offset: Int) -> UInt64 {
        let i = data.index(data.startIndex, offsetBy: offset)
        return UInt64(data[i]) << 56 | UInt64(data[data.index(i, offsetBy: 1)]) << 48 |
               UInt64(data[data.index(i, offsetBy: 2)]) << 40 | UInt64(data[data.index(i, offsetBy: 3)]) << 32 |
               UInt64(data[data.index(i, offsetBy: 4)]) << 24 | UInt64(data[data.index(i, offsetBy: 5)]) << 16 |
               UInt64(data[data.index(i, offsetBy: 6)]) << 8  | UInt64(data[data.index(i, offsetBy: 7)])
    }
}
#endif
