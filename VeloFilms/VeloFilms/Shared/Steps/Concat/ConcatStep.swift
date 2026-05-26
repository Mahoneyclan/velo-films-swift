import Foundation
import AVFoundation
import CoreGraphics
import os

/// Phase 1: Joins clip_0001…N into _middle.mp4 with crossfade transitions and backing music.
/// Phase 2: Joins _intro + _middle + _outro into {rideName}.mp4 (audio passthrough — each part
///           has its own music already baked: intro.mp3, backing music, outro.mp3).
/// macOS: FFmpeg xfade/acrossfade filter chain with timebase normalisation + amix (phase 1 only).
/// iOS:   AVMutableComposition A/B opacity + audio volume ramps + music track (phase 1 only).
private let log = Logger(subsystem: "com.velofilms", category: "ConcatStep")

struct ConcatStep: PipelineStep {
    let name = "concat"

    init() {}

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 1, total: 5, message: "Collecting clips...")

        let clipsDir = project.clipsDir
        let allFiles = (try? FileManager.default.contentsOfDirectory(
            at: clipsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []

        let clipFiles = allFiles
            .filter { $0.lastPathComponent.hasPrefix("clip_") && $0.pathExtension == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !clipFiles.isEmpty else {
            throw PipelineError.missingInput(
                "No clip_####.mp4 files found — run build step first")
        }

        let prefs    = project.loadPreferences()
        let musicURL = findMusicTrack(preferred: prefs.selectedMusicTrack)

        // MARK: Phase 1 — clips → _middle.mp4 with backing music

        // On iOS, AVAssetReader routes through mediaserverd which cannot access security-scoped
        // external drive files. Copy all inputs to the system temp dir (accessible to mediaserverd)
        // before passing them to crossFadeConcatAVF. FileManager.copyItem uses POSIX I/O and works
        // fine with the active security scope. middleURL also lives in temp since it's read back
        // in phase 2.
#if os(iOS)
        let iosTmp = FileManager.default.temporaryDirectory
        await reporter.report(current: 2, total: 5,
                              message: "Copying \(clipFiles.count) clip(s) to working storage...")
        let workClips: [URL] = try clipFiles.map { src in
            let dst = iosTmp.appending(path: src.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: src, to: dst)
            return dst
        }
        let middleURL = iosTmp.appending(path: "_middle.mp4")
#else
        await reporter.report(current: 2, total: 5,
                              message: "Building middle: \(clipFiles.count) clip(s) + music...")
        let workClips = clipFiles
        let middleURL = clipsDir.appending(path: "_middle.mp4")
#endif
        try? FileManager.default.removeItem(at: middleURL)

        // All clip_NNNN.mp4 files are exactly AppConfig.clipOutLenS seconds — set by ClipCompositor.
        // AVURLAsset.duration requires XPC loading and returns kCMTimeIndefinite unloaded.
        let clipDurations: [Double] = Array(repeating: AppConfig.clipOutLenS, count: workClips.count)

        if workClips.count == 1, let music = musicURL {
#if os(macOS)
            let bridge = makeBridge()
            try await xfadeConcat(parts: workClips, durations: clipDurations,
                                  outputURL: middleURL, bridge: bridge, musicURL: music)
#else
            try await crossFadeConcatAVF(parts: workClips, durations: clipDurations,
                                          outputURL: middleURL, musicURL: music)
#endif
        } else if workClips.count == 1 {
            try FileManager.default.copyItem(at: workClips[0], to: middleURL)
        } else {
#if os(macOS)
            let bridge = makeBridge()
            try await xfadeConcat(parts: workClips, durations: clipDurations,
                                   outputURL: middleURL, bridge: bridge, musicURL: musicURL)
#else
            try await crossFadeConcatAVF(parts: workClips, durations: clipDurations,
                                          outputURL: middleURL, musicURL: musicURL)
#endif
        }

        // MARK: Phase 2 — _intro + _middle + _outro → final reel (audio passthrough)

        await reporter.report(current: 4, total: 5, message: "Joining intro + middle + outro...")

        try? FileManager.default.removeItem(at: project.finalReelURL)

        let intro = clipsDir.appending(path: "_intro.mp4")
        let outro = clipsDir.appending(path: "_outro.mp4")
        var finalParts: [URL] = []
        if FileManager.default.fileExists(atPath: intro.path) { finalParts.append(intro) }
        finalParts.append(middleURL)
        if FileManager.default.fileExists(atPath: outro.path) { finalParts.append(outro) }

        if finalParts.count == 1 {
            try FileManager.default.copyItem(at: finalParts[0], to: project.finalReelURL)
        } else {
            // Binary parser — AVURLAsset.duration requires XPC and returns kCMTimeIndefinite
            // for unloaded assets; FrameSampler.movieDuration reads the mvhd box in-process.
            var finalDurations: [Double] = []
            for url in finalParts {
                finalDurations.append(FrameSampler.movieDuration(for: url) ?? AppConfig.clipOutLenS)
            }
#if os(macOS)
            let bridge = makeBridge()
            try await xfadeJoin(parts: finalParts, durations: finalDurations,
                                 outputURL: project.finalReelURL, bridge: bridge)
#else
            // Copy intro/outro from external drive to temp; middleURL is already in iosTmp.
            let workFinalParts: [URL] = try finalParts.map { part in
                if part == middleURL { return part }
                let dst = iosTmp.appending(path: part.lastPathComponent)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.copyItem(at: part, to: dst)
                return dst
            }
            try await crossFadeConcatAVF(parts: workFinalParts, durations: finalDurations,
                                          outputURL: project.finalReelURL, musicURL: nil)
#endif
        }

        let sizeMB = (try? FileManager.default
            .attributesOfItem(atPath: project.finalReelURL.path)[.size] as? Int)
            .map { Double($0) / 1_048_576 } ?? 0

        await reporter.report(current: 5, total: 5,
                              message: String(format: "Done — %.0f MB: %@",
                                             sizeMB, project.finalReelURL.lastPathComponent))
    }

    // MARK: - FFmpeg xfade with music (macOS) — clips → _middle.mp4

    private static let xfadeBatchSize = 30

    // applyRawVolume: false for batch segment passes — rv is applied once in the join pass.
    private func xfadeConcat(parts: [URL], durations: [Double],
                              outputURL: URL, bridge: any FFmpegBridge,
                              musicURL: URL?, applyRawVolume: Bool = true) async throws {
        // Split large clip counts into batches to keep each FFmpeg invocation manageable.
        // 30+ clips in one filter_complex causes SIGKILL on Apple Silicon due to graph size.
        if parts.count > Self.xfadeBatchSize {
            let tmpDir = outputURL.deletingLastPathComponent()
            var segURLs: [URL] = []
            var segDurs: [Double] = []
            let stride = Self.xfadeBatchSize
            var offset = 0
            var segIdx = 0
            while offset < parts.count {
                let end       = min(offset + stride, parts.count)
                let bParts    = Array(parts[offset..<end])
                let bDurs     = Array(durations[offset..<end])
                let segURL    = tmpDir.appending(path: "_xseg_\(segIdx).mp4")
                try? FileManager.default.removeItem(at: segURL)
                log.info("batch \(segIdx): clips \(offset+1)–\(end) → \(segURL.lastPathComponent)")
                // applyRawVolume: false — rv applied once in the join pass below
                try await xfadeConcat(parts: bParts, durations: bDurs,
                                      outputURL: segURL, bridge: bridge,
                                      musicURL: nil, applyRawVolume: false)
                let asset = AVURLAsset(url: segURL)
                let dur   = try await asset.load(.duration)
                segURLs.append(segURL)
                segDurs.append(CMTimeGetSeconds(dur))
                offset  += stride
                segIdx  += 1
            }
            // Join segments with music — rv applied here for the first (and only) time
            log.info("joining \(segURLs.count) segments → \(outputURL.lastPathComponent)")
            try await xfadeConcat(parts: segURLs, durations: segDurs,
                                  outputURL: outputURL, bridge: bridge,
                                  musicURL: musicURL, applyRawVolume: true)
            for seg in segURLs { try? FileManager.default.removeItem(at: seg) }
            return
        }

        let X   = AppConfig.concatXfadeDuration
        let vbr = "\(AppConfig.Encoding.videoBitrate / 1000)k"
        let abr = "\(AppConfig.Encoding.audioBitrate / 1000)k"
        let rv  = GlobalSettings.shared.rawAudioVolume
        let mv  = GlobalSettings.shared.musicVolume

        var hasAudio: [Bool] = []
        for url in parts {
            let asset = AVURLAsset(url: url)
            let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            hasAudio.append(!tracks.isEmpty)
        }

        // Total output duration — needed to calculate music copy count and trim
        var totalDur = durations[0]
        for i in 1..<durations.count { totalDur += durations[i] - X }

        // Probe music duration and calculate how many copies are needed to cover totalDur.
        // Using explicit copies + concat filter is more reliable than aloop (whose size
        // parameter must match the exact sample count of the file to loop correctly).
        var musicLoopCount = 1
        if let music = musicURL {
            let mAsset = AVURLAsset(url: music)
            let mDur = (try? await mAsset.load(.duration)).map { CMTimeGetSeconds($0) } ?? totalDur
            musicLoopCount = max(1, Int(ceil(totalDur / max(mDur, 0.001))) + 1)
        }

        var inputs: [String] = []
        for part in parts { inputs += ["-i", part.path] }
        if let music = musicURL {
            for _ in 0..<musicLoopCount { inputs += ["-i", music.path] }
        }

        var filterParts: [String] = []
        for i in 0..<parts.count {
            // fps=30 first normalises to CFR and a consistent timebase, then trim clamps to the
            // AVFoundation-reported duration (removing the stray Cycliq B-frame at PTS ~4.0s
            // that fps alone would include), then setpts resets PTS to zero for xfade offsets.
            let clipDurStr = String(format: "%.6f", durations[i])
            filterParts.append("[\(i):v]fps=30,trim=end=\(clipDurStr),setpts=PTS-STARTPTS[vn\(i)]")
            if hasAudio[i] {
                filterParts.append(
                    "[\(i):a]atrim=end=\(clipDurStr),asetpts=PTS-STARTPTS,aresample=48000[an\(i)]")
            } else {
                filterParts.append(
                    "aevalsrc=0:c=stereo:s=48000:d=\(clipDurStr)[an\(i)]")
            }
        }

        var prevV = "[vn0]"
        var prevA = "[an0]"
        var cumulativeDur = durations[0]

        for i in 1..<parts.count {
            let offset = max(0, cumulativeDur - X)
            let isLast = (i == parts.count - 1)
            let vOut   = isLast ? "[vchain]" : "[v\(i)]"
            let aOut   = isLast ? "[achain]" : "[a\(i)]"
            filterParts.append(
                "\(prevV)[vn\(i)]xfade=transition=fade:duration=\(X):offset=\(String(format: "%.3f", offset))\(vOut)")
            filterParts.append("\(prevA)[an\(i)]acrossfade=d=\(X)\(aOut)")
            prevV = vOut
            prevA = aOut
            cumulativeDur += durations[i] - X
        }

        filterParts.append("[vchain]null[vout]")
        if let _ = musicURL {
            let N      = parts.count
            let durStr = String(format: "%.3f", totalDur)
            // Concat N explicit copies of the music track, trim to totalDur.
            // This avoids aloop's sample-count dependency and works for all formats.
            let concatInputs = (0..<musicLoopCount).map { "[\(N + $0):a]" }.joined()
            let rawVol = applyRawVolume ? rv : 1.0
            filterParts.append(
                "[achain]volume=\(rawVol)[rawA];" +
                "\(concatInputs)concat=n=\(musicLoopCount):v=0:a=1," +
                "atrim=end=\(durStr),asetpts=PTS-STARTPTS," +
                "volume=\(mv)[musicA];" +
                "[rawA][musicA]amix=inputs=2:duration=longest:dropout_transition=0[aout]"
            )
        } else {
            let vol = applyRawVolume ? rv : 1.0
            filterParts.append("[achain]volume=\(vol)[aout]")
        }

        let filter = filterParts.joined(separator: ";")
        log.info("xfade middle: \(parts.count) clips, music=\(musicURL?.lastPathComponent ?? "none") → \(outputURL.lastPathComponent)")
        try await bridge.execute(arguments: inputs + [
            "-filter_complex", filter,
            "-map", "[vout]", "-map", "[aout]",
            "-c:v", AppConfig.Encoding.videoCodec, "-b:v", vbr,
            "-c:a", "aac", "-b:a", abr,
            "-movflags", "+faststart",
            "-y", outputURL.path,
        ])
    }

    // MARK: - FFmpeg xfade passthrough (macOS) — intro + middle + outro → final

    private func xfadeJoin(parts: [URL], durations: [Double],
                            outputURL: URL, bridge: any FFmpegBridge) async throws {
        let X   = AppConfig.concatXfadeDuration
        let vbr = "\(AppConfig.Encoding.videoBitrate / 1000)k"
        let abr = "\(AppConfig.Encoding.audioBitrate / 1000)k"

        var inputs: [String] = []
        for part in parts { inputs += ["-i", part.path] }

        var hasAudio: [Bool] = []
        for url in parts {
            let asset = AVURLAsset(url: url)
            let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            hasAudio.append(!tracks.isEmpty)
        }

        var filterParts: [String] = []
        for i in 0..<parts.count {
            // fps=30 first normalises to CFR and a consistent timebase, then trim clamps to the
            // AVFoundation-reported duration (removing the stray Cycliq B-frame at PTS ~4.0s
            // that fps alone would include), then setpts resets PTS to zero for xfade offsets.
            let clipDurStr = String(format: "%.6f", durations[i])
            filterParts.append("[\(i):v]fps=30,trim=end=\(clipDurStr),setpts=PTS-STARTPTS[vn\(i)]")
            if hasAudio[i] {
                filterParts.append(
                    "[\(i):a]atrim=end=\(clipDurStr),asetpts=PTS-STARTPTS,aresample=48000[an\(i)]")
            } else {
                filterParts.append(
                    "aevalsrc=0:c=stereo:s=48000:d=\(clipDurStr)[an\(i)]")
            }
        }

        var prevV = "[vn0]"
        var prevA = "[an0]"
        var cumulativeDur = durations[0]

        for i in 1..<parts.count {
            let offset = max(0, cumulativeDur - X)
            let isLast = (i == parts.count - 1)
            let vOut   = isLast ? "[vchain]" : "[v\(i)]"
            let aOut   = isLast ? "[achain]" : "[a\(i)]"
            filterParts.append(
                "\(prevV)[vn\(i)]xfade=transition=fade:duration=\(X):offset=\(String(format: "%.3f", offset))\(vOut)")
            filterParts.append("\(prevA)[an\(i)]acrossfade=d=\(X)\(aOut)")
            prevV = vOut
            prevA = aOut
            cumulativeDur += durations[i] - X
        }

        // Audio passthrough — each part's music is already baked in at correct levels
        filterParts.append("[vchain]null[vout]")
        filterParts.append("[achain]anull[aout]")

        let filter = filterParts.joined(separator: ";")
        log.info("xfade join: \(parts.count) parts → \(outputURL.lastPathComponent)")
        try await bridge.execute(arguments: inputs + [
            "-filter_complex", filter,
            "-map", "[vout]", "-map", "[aout]",
            "-c:v", AppConfig.Encoding.videoCodec, "-b:v", vbr,
            "-c:a", "aac", "-b:a", abr,
            "-movflags", "+faststart",
            "-y", outputURL.path,
        ])
    }

    // MARK: - AVFoundation crossfade (iOS)
    //
    // AVVideoComposition + AVAssetReaderVideoCompositionOutput engages the Fig video
    // compositor on iOS (FigApplicationStateMonitor err=-19431) regardless of composition
    // complexity. This replaces the composition-based approach with:
    //   Step 1 — Frame-by-frame video crossfade via AVAssetImageGenerator (in-process
    //            VTDecompressionSession) + CGContext alpha blending → video-only temp file.
    //   Step 2a — Music: IntroBuilder.mixAudio (AVAssetReaderTrackOutput, no compositor).
    //   Step 2b — Audio passthrough: composition with video from step 1 + audio A/B tracks
    //             + AVAudioMix volume ramps, exported with videoComposition=nil so
    //             exportInProcess uses AVAssetReaderTrackOutput (no Fig compositor).

    private func crossFadeConcatAVF(parts: [URL], durations: [Double],
                                     outputURL: URL, musicURL: URL?) async throws {
        guard !parts.isEmpty else { return }

        // AVAssetReaderAudioMixOutput routes through mediaserverd which cannot access
        // security-scoped external-drive URLs. Copy music to iosTmp if needed.
        let iosTmp     = FileManager.default.temporaryDirectory
        let accessibleMusic: URL? = try musicURL.map { raw in
            guard !raw.path.hasPrefix(Bundle.main.bundlePath),
                  !raw.path.hasPrefix(iosTmp.path) else { return raw }
            let dst = iosTmp.appending(path: "music_\(raw.lastPathComponent)")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: raw, to: dst)
            return dst
        }

        if parts.count == 1 {
            if let music = accessibleMusic {
                try await IntroBuilder.mixAudio(videoURL: parts[0], musicURL: music,
                                                duration: durations[0],
                                                musicVolume: Float(GlobalSettings.shared.musicVolume),
                                                outputURL: outputURL)
            } else {
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.copyItem(at: parts[0], to: outputURL)
            }
            return
        }

        let fps = 30
        let ts  = CMTimeScale(600)
        let W   = AppConfig.HUD.outputW
        let H   = AppConfig.HUD.outputH
        let X   = AppConfig.concatXfadeDuration
        let n   = parts.count

        // Clip start times in the output timeline (supports variable-duration clips)
        var clipStarts = [Double](repeating: 0.0, count: n)
        for i in 1..<n { clipStarts[i] = clipStarts[i-1] + durations[i-1] - X }
        let totalDur    = clipStarts[n-1] + durations[n-1]
        let totalFrames = Int(ceil(totalDur * Double(fps)))
        let totalDurCM  = CMTimeMakeWithSeconds(totalDur, preferredTimescale: ts)

        // MARK: Step 1 — frame-by-frame video crossfade
        let videoOnly = iosTmp.appending(path: "concat_vid_\(outputURL.lastPathComponent)")
        try? FileManager.default.removeItem(at: videoOnly)

        let gens: [AVAssetImageGenerator] = parts.indices.map { i in
            let url  = parts[i]
            let dur  = durations[i]
            let comp = AVMutableComposition()
            if let vt = comp.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let durCM = CMTimeMakeWithSeconds(dur, preferredTimescale: ts)
                vt.segments = [AVCompositionTrackSegment(
                    url: url, trackID: 1,
                    sourceTimeRange: CMTimeRange(start: .zero, duration: durCM),
                    targetTimeRange: CMTimeRange(start: .zero, duration: durCM)
                )]
            }
            let g = AVAssetImageGenerator(asset: comp)
            g.maximumSize    = CGSize(width: W, height: H)
            g.appliesPreferredTrackTransform = true
            g.requestedTimeToleranceBefore   = CMTime(value: 1, timescale: CMTimeScale(fps))
            g.requestedTimeToleranceAfter    = CMTime(value: 1, timescale: CMTimeScale(fps))
            return g
        }

        let vidWriter = try AVAssetWriter(outputURL: videoOnly, fileType: .mp4)
        let vidInput  = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  W,
            AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: AppConfig.Encoding.videoBitrate,
                AVVideoProfileLevelKey:   AVVideoProfileLevelH264HighAutoLevel,
            ]
        ])
        vidInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vidInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: W,
                kCVPixelBufferHeightKey as String: H,
            ])
        vidWriter.add(vidInput)
        vidWriter.startWriting()
        vidWriter.startSession(atSourceTime: .zero)
        defer { if vidWriter.status == .writing { vidWriter.cancelWriting() } }

        let frameDur = CMTime(value: CMTimeValue(ts / CMTimeScale(fps)), timescale: ts)
        let rect     = CGRect(x: 0, y: 0, width: W, height: H)

        for f in 0..<totalFrames {
            let t = Double(f) / Double(fps)
            var outCG: CGImage?
            var inXfade = false

            for i in 0..<(n-1) {
                let xStart = clipStarts[i+1]
                guard t >= xStart && t < xStart + X else { continue }
                inXfade = true
                let alpha = (t - xStart) / X
                let tA = CMTimeMakeWithSeconds(t - clipStarts[i],   preferredTimescale: ts)
                let tB = CMTimeMakeWithSeconds(t - clipStarts[i+1], preferredTimescale: ts)
                let cgA = (try? await gens[i].image(at: tA))?.image
                let cgB = (try? await gens[i+1].image(at: tB))?.image
                if let a = cgA, let b = cgB {
                    let ctx = IntroBuilder.makeBitmapContext(width: W, height: H)
                    ctx.draw(a, in: rect)
                    ctx.setAlpha(CGFloat(alpha))
                    ctx.draw(b, in: rect)
                    outCG = ctx.makeImage()
                } else { outCG = cgA ?? cgB }
                break
            }

            if !inXfade {
                var clipIdx = n - 1
                for i in 0..<(n-1) {
                    if t < clipStarts[i+1] { clipIdx = i; break }
                }
                let localT = CMTimeMakeWithSeconds(t - clipStarts[clipIdx], preferredTimescale: ts)
                outCG = (try? await gens[clipIdx].image(at: localT))?.image
            }

            guard let cg = outCG else { continue }
            let pb = try VideoEncoder.makePixelBuffer(from: cg, width: W, height: H)
            while !vidInput.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            adaptor.append(pb, withPresentationTime: CMTimeMultiply(frameDur, multiplier: Int32(f)))
        }

        vidInput.markAsFinished()
        await vidWriter.finishWriting()
        if let err = vidWriter.error { throw err }
        guard vidWriter.status == .completed else {
            throw PipelineError.renderFailed("crossFadeConcatAVF: video \(vidWriter.status.rawValue)")
        }

        // MARK: Step 2 — Add audio
        if let music = accessibleMusic {
            // Phase 1: iOS clips have no audio — just mix in the backing music.
            // mixAudio uses exportInProcess (video compressed passthrough + audio AAC re-encode).
            // videoOnly and music are both in iosTmp → accessible to mediaserverd.
            log.info("crossfade (iOS): adding music → \(outputURL.lastPathComponent)")
            try await IntroBuilder.mixAudio(videoURL: videoOnly, musicURL: music,
                                             duration: totalDur,
                                             musicVolume: Float(GlobalSettings.shared.musicVolume),
                                             outputURL: outputURL)
            try? FileManager.default.removeItem(at: videoOnly)
        } else {
            // Phase 2: intro+middle+outro each have baked-in audio at trackID 2.
            // Video: passthrough from frame-by-frame file (no compositor).
            // Audio: A/B interleaved tracks + AVAudioMix crossfade volume ramps.
            // exportInProcess with videoComposition=nil uses AVAssetReaderTrackOutput for
            // video (no Fig compositor) + AVAssetReaderAudioMixOutput for audio.
            log.info("crossfade (iOS): audio passthrough crossfade → \(outputURL.lastPathComponent)")
            let composition = AVMutableComposition()

            if let vt = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                vt.segments = [AVCompositionTrackSegment(
                    url: videoOnly, trackID: 1,
                    sourceTimeRange: CMTimeRange(start: .zero, duration: totalDurCM),
                    targetTimeRange: CMTimeRange(start: .zero, duration: totalDurCM)
                )]
            }

            guard let audA = composition.addMutableTrack(
                      withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audB = composition.addMutableTrack(
                      withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw PipelineError.renderFailed("crossFadeConcatAVF: failed to create audio tracks")
            }

            for i in parts.indices {
                let url   = parts[i]
                let aT    = (i % 2 == 0) ? audA : audB
                let start = CMTimeMakeWithSeconds(clipStarts[i], preferredTimescale: ts)
                let durCM = CMTimeMakeWithSeconds(durations[i], preferredTimescale: ts)
                aT.segments = (aT.segments ?? []) + [AVCompositionTrackSegment(
                    url: url, trackID: 2,
                    sourceTimeRange: CMTimeRange(start: .zero, duration: durCM),
                    targetTimeRange: CMTimeRange(start: start, duration: durCM)
                )]
            }

            let paramsA = AVMutableAudioMixInputParameters(track: audA)
            let paramsB = AVMutableAudioMixInputParameters(track: audB)
            let xCM     = CMTimeMakeWithSeconds(X, preferredTimescale: ts)
            for i in 0..<(n-1) {
                let transStart = CMTimeMakeWithSeconds(clipStarts[i+1], preferredTimescale: ts)
                let transRange = CMTimeRange(start: transStart, duration: xCM)
                if i % 2 == 0 {
                    paramsA.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: transRange)
                    paramsB.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: transRange)
                } else {
                    paramsB.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: transRange)
                    paramsA.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: transRange)
                }
            }
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [paramsA, paramsB]

            try await VideoEncoder.export(composition: composition,
                                           videoComposition: nil,
                                           audioMix: audioMix,
                                           to: outputURL)
            try? FileManager.default.removeItem(at: videoOnly)
        }
    }

    // MARK: - Music lookup

    private func findMusicTrack(preferred: String = "") -> URL? {
        if let url = GlobalSettings.shared.musicURL,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let extensions = ["mp3", "m4a", "aac", "wav"]
        var candidates: [URL] = []
        for ext in extensions {
            candidates += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "music") ?? []
        }
        if candidates.isEmpty {
            let splash = Set(["intro", "outro"])
            for ext in extensions {
                let rootURLs = (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [])
                    .filter { !splash.contains($0.deletingPathExtension().lastPathComponent) }
                candidates += rootURLs
            }
        }
        if !preferred.isEmpty,
           let match = candidates.first(where: { $0.lastPathComponent == preferred }) {
            return match
        }
        return candidates.randomElement()
    }
}
