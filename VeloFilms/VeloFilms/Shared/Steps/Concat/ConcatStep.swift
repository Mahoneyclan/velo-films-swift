import Foundation
import AVFoundation

/// Phase 1: Joins clip_0001…N into _middle.mp4 with crossfade transitions and backing music.
/// Phase 2: Joins _intro + _middle + _outro into {rideName}.mp4 (audio passthrough — each part
///           has its own music already baked: intro.mp3, backing music, outro.mp3).
/// macOS: FFmpeg xfade/acrossfade filter chain with timebase normalisation + amix (phase 1 only).
/// iOS:   AVMutableComposition A/B opacity + audio volume ramps + music track (phase 1 only).
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

        let prefs       = project.loadPreferences()
        let musicTracks = musicPlaylist(preferred: prefs.selectedMusicTrack)

        // MARK: Phase 1 — clips → _middle.mp4 with backing music

        await reporter.report(current: 2, total: 5,
                              message: "Building middle: \(clipFiles.count) clip(s) + music...")

        let middleURL = clipsDir.appending(path: "_middle.mp4")
        try? FileManager.default.removeItem(at: middleURL)

        var clipDurations: [Double] = []
        for url in clipFiles {
            let asset = AVURLAsset(url: url)
            let dur = try await asset.load(.duration)
            clipDurations.append(CMTimeGetSeconds(dur))
        }

        if clipFiles.count == 1, !musicTracks.isEmpty {
#if os(macOS)
            let bridge = makeBridge()
            try await xfadeConcat(parts: clipFiles, durations: clipDurations,
                                  outputURL: middleURL, bridge: bridge, musicTracks: musicTracks)
#else
            try await crossFadeConcatAVF(parts: clipFiles, durations: clipDurations,
                                          outputURL: middleURL, musicTracks: musicTracks)
#endif
        } else if clipFiles.count == 1 {
            try FileManager.default.copyItem(at: clipFiles[0], to: middleURL)
        } else {
#if os(macOS)
            let bridge = makeBridge()
            try await xfadeConcat(parts: clipFiles, durations: clipDurations,
                                   outputURL: middleURL, bridge: bridge, musicTracks: musicTracks)
#else
            try await crossFadeConcatAVF(parts: clipFiles, durations: clipDurations,
                                          outputURL: middleURL, musicTracks: musicTracks)
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
            var finalDurations: [Double] = []
            for url in finalParts {
                let asset = AVURLAsset(url: url)
                let dur = try await asset.load(.duration)
                finalDurations.append(CMTimeGetSeconds(dur))
            }
#if os(macOS)
            let bridge = makeBridge()
            try await xfadeJoin(parts: finalParts, durations: finalDurations,
                                 outputURL: project.finalReelURL, bridge: bridge)
#else
            try await crossFadeConcatAVF(parts: finalParts, durations: finalDurations,
                                          outputURL: project.finalReelURL, musicTracks: [])
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

    private func xfadeConcat(parts: [URL], durations: [Double],
                              outputURL: URL, bridge: any FFmpegBridge,
                              musicTracks: [URL]) async throws {
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

        // Total output duration — needed to build the music sequence and trim
        var totalDur = durations[0]
        for i in 1..<durations.count { totalDur += durations[i] - X }

        // Walk the playlist in order (cycling back to the start only once every distinct
        // track has been used) until the sequence covers totalDur — plays each track once
        // and moves on to the next rather than looping a single track.
        var musicSequence: [URL] = []
        if !musicTracks.isEmpty {
            var seqDur = 0.0
            var idx    = 0
            while seqDur < totalDur {
                let track = musicTracks[idx % musicTracks.count]
                musicSequence.append(track)
                let mAsset = AVURLAsset(url: track)
                let mDur = (try? await mAsset.load(.duration)).map { CMTimeGetSeconds($0) } ?? totalDur
                seqDur += max(mDur, 0.001)
                idx += 1
            }
        }

        var inputs: [String] = []
        for part in parts { inputs += ["-i", part.path] }
        for track in musicSequence { inputs += ["-i", track.path] }

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

        // When there's only one part, the crossfade loop above never runs, so prevV/prevA
        // are still [vn0]/[an0] rather than the [vchain]/[achain] labels the loop would
        // have produced — use prevV/prevA here rather than hardcoding [vchain]/[achain].
        filterParts.append("\(prevV)null[vout]")
        if !musicSequence.isEmpty {
            let N      = parts.count
            let count  = musicSequence.count
            let durStr = String(format: "%.3f", totalDur)
            // Concat the distinct tracks in sequence, trim to totalDur. Using explicit
            // concat is more reliable than aloop (whose size parameter must match the
            // exact sample count of the file to loop correctly).
            let concatInputs = (0..<count).map { "[\(N + $0):a]" }.joined()
            filterParts.append(
                "\(prevA)volume=\(rv)[rawA];" +
                "\(concatInputs)concat=n=\(count):v=0:a=1," +
                "atrim=end=\(durStr),asetpts=PTS-STARTPTS," +
                "volume=\(mv)[musicA];" +
                "[rawA][musicA]amix=inputs=2:duration=longest:dropout_transition=0[aout]"
            )
        } else {
            filterParts.append("\(prevA)volume=\(rv)[aout]")
        }

        let filter = filterParts.joined(separator: ";")
        let musicDesc = musicSequence.isEmpty ? "none" : musicSequence.map(\.lastPathComponent).joined(separator: " → ")
        print("[ConcatStep] xfade middle: \(parts.count) clips, music=\(musicDesc) → \(outputURL.lastPathComponent)")
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

        // Audio passthrough — each part's music is already baked in at correct levels.
        // When there's only one part, the crossfade loop above never runs, so prevV/prevA
        // are still [vn0]/[an0] rather than the [vchain]/[achain] labels the loop would
        // have produced — use prevV/prevA here rather than hardcoding [vchain]/[achain].
        filterParts.append("\(prevV)null[vout]")
        filterParts.append("\(prevA)anull[aout]")

        let filter = filterParts.joined(separator: ";")
        print("[ConcatStep] xfade join: \(parts.count) parts → \(outputURL.lastPathComponent)")
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

    private func crossFadeConcatAVF(parts: [URL], durations: [Double],
                                     outputURL: URL, musicTracks: [URL]) async throws {
        let X   = AppConfig.concatXfadeDuration
        let ts  = CMTimeScale(600)
        let xCM = CMTimeMakeWithSeconds(X, preferredTimescale: ts)

        let composition = AVMutableComposition()
        let vidA = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let vidB = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let audA = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let audB = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!

        var insertTime = CMTime.zero
        var clipStarts: [CMTime] = []
        for (i, url) in parts.enumerated() {
            clipStarts.append(insertTime)
            let dur   = durations[i]
            let durCM = CMTimeMakeWithSeconds(dur, preferredTimescale: ts)
            let asset = AVURLAsset(url: url)
            let vT    = (i % 2 == 0) ? vidA : vidB
            let aT    = (i % 2 == 0) ? audA : audB
            if let src = try? await asset.loadTracks(withMediaType: .video).first {
                try? vT.insertTimeRange(CMTimeRange(start: .zero, duration: durCM), of: src, at: insertTime)
            }
            if let src = try? await asset.loadTracks(withMediaType: .audio).first {
                try? aT.insertTimeRange(CMTimeRange(start: .zero, duration: durCM), of: src, at: insertTime)
            }
            if i < parts.count - 1 {
                insertTime = insertTime + durCM - xCM
            }
        }

        let totalDur = durations.enumerated().reduce(0.0) { acc, pair in
            let (i, d) = pair
            return acc + (i < parts.count - 1 ? d - X : d)
        }
        let totalDurCM = CMTimeMakeWithSeconds(totalDur, preferredTimescale: ts)

        var instructions: [any AVVideoCompositionInstructionProtocol] = []
        for i in 0..<parts.count {
            let dur       = durations[i]
            let durCM     = CMTimeMakeWithSeconds(dur, preferredTimescale: ts)
            let useA      = (i % 2 == 0)
            let curr      = useA ? vidA : vidB
            let next      = useA ? vidB : vidA
            let clipStart = clipStarts[i]

            let midStart = i == 0 ? clipStart : clipStart + xCM
            let midEnd   = i < parts.count - 1 ? clipStart + durCM - xCM : totalDurCM
            if midStart < midEnd {
                var iCfg = AVVideoCompositionInstruction.Configuration(
                    timeRange: CMTimeRange(start: midStart, end: midEnd))
                iCfg.layerInstructions = [
                    AVVideoCompositionLayerInstruction(configuration: .init(assetTrack: curr)),
                ]
                instructions.append(AVVideoCompositionInstruction(configuration: iCfg))
            }

            if i < parts.count - 1 {
                let transStart = clipStart + durCM - xCM
                let transRange = CMTimeRange(start: transStart, duration: xCM)
                var outCfg = AVVideoCompositionLayerInstruction.Configuration(assetTrack: curr)
                outCfg.addOpacityRamp(.init(timeRange: transRange, start: 1.0, end: 0.0))
                var inCfg = AVVideoCompositionLayerInstruction.Configuration(assetTrack: next)
                inCfg.addOpacityRamp(.init(timeRange: transRange, start: 0.0, end: 1.0))
                var iCfg = AVVideoCompositionInstruction.Configuration(timeRange: transRange)
                iCfg.layerInstructions = [
                    AVVideoCompositionLayerInstruction(configuration: inCfg),
                    AVVideoCompositionLayerInstruction(configuration: outCfg),
                ]
                instructions.append(AVVideoCompositionInstruction(configuration: iCfg))
            }
        }

        let videoComp = AVVideoComposition(configuration: AVVideoComposition.Configuration(
            frameDuration: CMTime(value: 1, timescale: 30),
            instructions: instructions,
            renderSize: CGSize(width: AppConfig.HUD.outputW, height: AppConfig.HUD.outputH)
        ))

        let paramsA = AVMutableAudioMixInputParameters(track: audA)
        let paramsB = AVMutableAudioMixInputParameters(track: audB)
        var timelinePos = CMTime.zero
        for i in 0..<parts.count - 1 {
            let dur        = durations[i]
            let durCM      = CMTimeMakeWithSeconds(dur, preferredTimescale: ts)
            let transStart = timelinePos + durCM - xCM
            let transRange = CMTimeRange(start: transStart, duration: xCM)
            if i % 2 == 0 {
                paramsA.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: transRange)
                paramsB.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: transRange)
            } else {
                paramsB.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: transRange)
                paramsA.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: transRange)
            }
            timelinePos = timelinePos + durCM - xCM
        }
        var inputParams: [AVMutableAudioMixInputParameters] = [paramsA, paramsB]

        if !musicTracks.isEmpty {
            let mTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            var remaining = totalDurCM
            var destTime  = CMTime.zero
            var idx       = 0
            // Walk the playlist in order (cycling back to the start only once every distinct
            // track has been used) until the timeline is filled — plays each track once and
            // moves on to the next rather than looping a single track.
            while remaining > .zero {
                let track = musicTracks[idx % musicTracks.count]
                idx += 1
                let musicAsset = AVURLAsset(url: track)
                guard let musicDur = try? await musicAsset.load(.duration),
                      musicDur > .zero,
                      let srcM = try? await musicAsset.loadTracks(withMediaType: .audio).first
                else { break }
                let insert = CMTimeMinimum(remaining, musicDur)
                try? mTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: insert), of: srcM, at: destTime)
                destTime  = destTime + insert
                remaining = remaining - insert
            }
            let mp = AVMutableAudioMixInputParameters(track: mTrack)
            mp.setVolume(Float(GlobalSettings.shared.musicVolume), at: .zero)
            inputParams.append(mp)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParams

        let musicDesc = musicTracks.isEmpty ? "none" : musicTracks.map(\.lastPathComponent).joined(separator: " → ")
        print("[ConcatStep] crossfade join (AVF): \(parts.count) parts, music=\(musicDesc) → \(outputURL.lastPathComponent)")
        try await VideoEncoder.export(composition: composition,
                                       videoComposition: videoComp,
                                       audioMix: audioMix,
                                       to: outputURL)
    }

    // MARK: - Music lookup

    /// Ordered playlist to sequence through for backing music: starts at the preferred/random
    /// pick, then walks the rest of the library in order so a long ride plays through
    /// different tracks instead of looping the same one. A user-supplied global override
    /// (GlobalSettings.musicURL) has no library to draw from, so it's played (and looped if
    /// needed) on its own.
    private func musicPlaylist(preferred: String = "") -> [URL] {
        if let url = GlobalSettings.shared.musicURL,
           FileManager.default.fileExists(atPath: url.path) {
            return [url]
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
        guard !candidates.isEmpty else { return [] }
        candidates.sort { $0.lastPathComponent < $1.lastPathComponent }

        let startIndex: Int
        if !preferred.isEmpty,
           let idx = candidates.firstIndex(where: { $0.lastPathComponent == preferred }) {
            startIndex = idx
        } else {
            startIndex = Int.random(in: 0..<candidates.count)
        }
        return Array(candidates[startIndex...] + candidates[..<startIndex])
    }
}
