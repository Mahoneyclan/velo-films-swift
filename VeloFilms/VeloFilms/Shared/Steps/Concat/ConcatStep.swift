import Foundation
import AVFoundation

/// Joins _intro + _middle_01…N + _outro into {rideName}.mp4 with crossfade transitions.
/// macOS: FFmpeg xfade/acrossfade filter chain with timebase normalisation.
/// iOS:   AVMutableComposition A/B opacity + audio volume ramps.
struct ConcatStep: PipelineStep {
    let name = "concat"

    init() {}

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 1, total: 3, message: "Collecting segments...")

        let clipsDir = project.clipsDir
        let allFiles = (try? FileManager.default.contentsOfDirectory(
            at: clipsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []

        let middleFiles = allFiles
            .filter { $0.lastPathComponent.hasPrefix("_middle_") && $0.pathExtension == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !middleFiles.isEmpty else {
            throw PipelineError.missingInput(
                "No _middle_##.mp4 segments found — run build step first")
        }

        var parts: [URL] = []
        let intro = clipsDir.appending(path: "_intro.mp4")
        let outro = clipsDir.appending(path: "_outro.mp4")
        if FileManager.default.fileExists(atPath: intro.path) { parts.append(intro) }
        parts.append(contentsOf: middleFiles)
        if FileManager.default.fileExists(atPath: outro.path) { parts.append(outro) }

        await reporter.report(current: 2, total: 3,
                              message: "Joining \(parts.count) segment(s) with crossfades...")

        try? FileManager.default.removeItem(at: project.finalReelURL)

        if parts.count == 1 {
            try FileManager.default.copyItem(at: parts[0], to: project.finalReelURL)
        } else {
            var durations: [Double] = []
            for url in parts {
                let asset = AVURLAsset(url: url)
                let dur = try await asset.load(.duration)
                durations.append(CMTimeGetSeconds(dur))
            }
#if os(macOS)
            let bridge = makeBridge()
            try await xfadeConcat(parts: parts, durations: durations,
                                   outputURL: project.finalReelURL, bridge: bridge)
#else
            try await crossFadeConcatAVF(parts: parts, durations: durations,
                                          outputURL: project.finalReelURL)
#endif
        }

        let sizeMB = (try? FileManager.default
            .attributesOfItem(atPath: project.finalReelURL.path)[.size] as? Int)
            .map { Double($0) / 1_048_576 } ?? 0

        await reporter.report(current: 3, total: 3,
                              message: String(format: "Done — %.0f MB: %@",
                                             sizeMB, project.finalReelURL.lastPathComponent))
    }

    // MARK: - FFmpeg xfade segment join (macOS)

    private func xfadeConcat(parts: [URL], durations: [Double],
                              outputURL: URL, bridge: any FFmpegBridge) async throws {
        let X   = AppConfig.concatXfadeDuration
        let vbr = "\(AppConfig.Encoding.videoBitrate / 1000)k"
        let abr = "\(AppConfig.Encoding.audioBitrate / 1000)k"

        var inputs: [String] = []
        for part in parts { inputs += ["-i", part.path] }

        var filterParts: [String] = []

        // Normalise every input to a common timebase (fps=30) and sample rate (48 kHz)
        // before xfade/acrossfade — the filters require matching specs across all inputs.
        // Intro/outro come from AVFoundation (1/600 tb, 48 kHz); middles come from
        // FFmpeg libx264 (1/15360 tb, 96 kHz); fps + aresample unify them.
        for i in 0..<parts.count {
            filterParts.append("[\(i):v]fps=fps=30[vn\(i)]")
            filterParts.append("[\(i):a]aresample=48000[an\(i)]")
        }

        var prevV = "[vn0]"
        var prevA = "[an0]"
        var cumulativeDur = durations[0]

        for i in 1..<parts.count {
            let offset  = max(0, cumulativeDur - X)
            let isLast  = (i == parts.count - 1)
            let vOut    = isLast ? "[vchain]" : "[v\(i)]"
            let aOut    = isLast ? "[achain]" : "[a\(i)]"
            filterParts.append("\(prevV)[vn\(i)]xfade=transition=fade:duration=\(X):offset=\(String(format: "%.3f", offset))\(vOut)")
            filterParts.append("\(prevA)[an\(i)]acrossfade=d=\(X)\(aOut)")
            prevV = vOut
            prevA = aOut
            cumulativeDur += durations[i] - X
        }

        filterParts.append("[vchain]null[vout]")
        filterParts.append("[achain]anull[aout]")

        let filter = filterParts.joined(separator: ";")
        print("[ConcatStep] xfade join: \(parts.count) parts, X=\(X)s → \(outputURL.lastPathComponent)")
        try await bridge.execute(arguments: inputs + [
            "-filter_complex", filter,
            "-map", "[vout]", "-map", "[aout]",
            "-c:v", AppConfig.Encoding.videoCodec, "-b:v", vbr,
            "-c:a", "aac", "-b:a", abr,
            "-movflags", "+faststart",
            "-y", outputURL.path,
        ])
    }

    // MARK: - AVFoundation crossfade segment join (iOS)

    private func crossFadeConcatAVF(parts: [URL], durations: [Double],
                                     outputURL: URL) async throws {
        let X  = AppConfig.concatXfadeDuration
        let ts = CMTimeScale(600)
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

        // Insert each segment into the A/B alternating tracks
        var insertTime = CMTime.zero
        var clipStarts: [CMTime] = []
        for (i, url) in parts.enumerated() {
            clipStarts.append(insertTime)
            let dur   = durations[i]
            let durCM = CMTimeMakeWithSeconds(dur, preferredTimescale: ts)
            let asset = AVURLAsset(url: url)
            let vT = (i % 2 == 0) ? vidA : vidB
            let aT = (i % 2 == 0) ? audA : audB
            if let src = try? await asset.loadTracks(withMediaType: .video).first {
                try? vT.insertTimeRange(CMTimeRange(start: .zero, duration: durCM), of: src, at: insertTime)
            }
            if let src = try? await asset.loadTracks(withMediaType: .audio).first {
                try? aT.insertTimeRange(CMTimeRange(start: .zero, duration: durCM), of: src, at: insertTime)
            }
            if i < parts.count - 1 {
                let stepCM = durCM - xCM
                insertTime = insertTime + stepCM
            }
        }

        let totalDur = durations.enumerated().reduce(0.0) { acc, pair in
            let (i, d) = pair
            return acc + (i < parts.count - 1 ? d - X : d)
        }
        let totalDurCM = CMTimeMakeWithSeconds(totalDur, preferredTimescale: ts)

        // Video composition instructions with opacity crossfades
        var instructions: [any AVVideoCompositionInstructionProtocol] = []
        for i in 0..<parts.count {
            let dur   = durations[i]
            let durCM = CMTimeMakeWithSeconds(dur, preferredTimescale: ts)
            let useA  = (i % 2 == 0)
            let curr  = useA ? vidA : vidB
            let next  = useA ? vidB : vidA
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

        // Audio volume ramps matching video crossfades
        let paramsA = AVMutableAudioMixInputParameters(track: audA)
        let paramsB = AVMutableAudioMixInputParameters(track: audB)
        var timelinePos = CMTime.zero
        for i in 0..<parts.count - 1 {
            let dur   = durations[i]
            let durCM = CMTimeMakeWithSeconds(dur, preferredTimescale: ts)
            // Transition starts at end of clip i minus xfade overlap
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
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [paramsA, paramsB]

        print("[ConcatStep] crossfade join (AVF): \(parts.count) parts → \(outputURL.lastPathComponent)")
        try await VideoEncoder.export(composition: composition,
                                       videoComposition: videoComp,
                                       audioMix: audioMix,
                                       to: outputURL)
    }
}
