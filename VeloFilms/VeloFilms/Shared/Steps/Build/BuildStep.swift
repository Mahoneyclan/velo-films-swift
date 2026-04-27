import Foundation
import AVFoundation

/// Orchestrates the build step: pre-render assets then composite clips.
/// Mirrors build.py: minimaps → elevation strips → gauges → clip render → segment concat.
struct BuildStep: PipelineStep {
    let name = "build"
    let jsonlReader: JSONLReader
    let yoloModelURL: URL

    init(yoloModelURL: URL, jsonlReader: JSONLReader = JSONLReader()) {
        self.jsonlReader = jsonlReader
        self.yoloModelURL = yoloModelURL
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        try project.createOutputDirectories()
        await reporter.report(current: 0, total: 6, message: "Loading select.jsonl...")

        let selectRows:  [SelectRow]  = try jsonlReader.read(from: project.selectJSONL)
        let flattenRows: [FlattenRow] = try jsonlReader.read(from: project.flattenJSONL)
        let recommended = selectRows.filter { $0.recommended }

        guard !recommended.isEmpty else {
            throw PipelineError.missingInput("No recommended clips in select.jsonl — run select step first")
        }

        let gpxPoints = flattenRows.map {
            GPXPoint(epoch: $0.gpxEpoch, lat: $0.lat, lon: $0.lon,
                     elevation: $0.elevation, hr: $0.hrBpm, cadence: $0.cadenceRpm,
                     speedKmh: $0.speedKmh, gradientPct: $0.gradientPct)
        }

        let recommendedIds = Set(recommended.map { $0.base.momentId })
        let allMoments     = PartnerMatcher.group(selectRows.map(\.base))
        let moments        = allMoments.filter { recommendedIds.contains($0.momentId) }
        let total          = moments.count

        clearDirectory(project.minimapsDir)
        clearDirectory(project.elevationDir)
        clearDirectory(project.gaugesDir)
        clearClips(in: project.clipsDir)

        await reporter.report(current: 0, total: total, message: "Fetching map tiles...")
        let baseSnapshot = await MinimapRenderer.makeBaseSnapshot(gpxPoints: gpxPoints)

        var minimapPaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            await reporter.report(current: i, total: total, message: "Minimap \(i+1)/\(total)...")
            let outURL = project.minimapsDir.appending(
                path: String(format: "minimap_%04d.png", i+1))
            try MinimapRenderer.render(base: baseSnapshot, gpxPoints: gpxPoints,
                                       currentEpoch: primary.absTimeEpoch, outputURL: outURL)
            minimapPaths[i+1] = outURL
        }

        var elevPaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            await reporter.report(current: i, total: total, message: "Elevation \(i+1)/\(total)...")
            let outURL = project.elevationDir.appending(
                path: String(format: "elev_%04d.png", i+1))
            try ElevationRenderer.render(flattenRows: flattenRows,
                                         currentEpoch: primary.absTimeEpoch, outputURL: outURL)
            elevPaths[i+1] = outURL
        }

        await reporter.report(current: 0, total: total, message: "Pre-rendering gauge strips...")
        var gaugeFrames: [Int: [CGImage]] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            gaugeFrames[i+1] = try GaugeRenderer.renderFrames(
                flattenRows: flattenRows, clipEpoch: primary.absTimeEpoch)
        }

        await reporter.report(current: 4, total: 6, message: "Rendering clips...")
        let compositor = ClipCompositor(outputDir: project.clipsDir)
        var clipURLs: [URL] = []

        for (i, moment) in moments.enumerated() {
            guard let primary  = moment.primary,
                  let minimap  = minimapPaths[i+1],
                  let elev     = elevPaths[i+1],
                  let gauge    = gaugeFrames[i+1] else { continue }

            let clipURL = try await compositor.renderClip(
                mainRow:       primary,
                pipRow:        moment.secondary,
                minimapPath:   minimap,
                elevationPath: elev,
                gaugeImages:   gauge,
                clipIndex:     i + 1
            )
            clipURLs.append(clipURL)
            await reporter.report(current: i + 1, total: moments.count + 2,
                                  message: "Rendered clip \(i+1)/\(moments.count)")
        }

        await reporter.report(current: 5, total: 6, message: "Building segments...")
        let prefs = project.loadPreferences()
        try await buildSegments(clipURLs: clipURLs, project: project, preferences: prefs)

        await reporter.report(current: 6, total: 6, message: "Build complete")
    }

    // MARK: - Segment concatenation

    private func buildSegments(clipURLs: [URL], project: Project,
                                preferences: ProjectPreferences) async throws {
        let perSegment = AppConfig.highlightsPerSegment
        let chunks = stride(from: 0, to: clipURLs.count, by: perSegment).map {
            Array(clipURLs[$0..<min($0 + perSegment, clipURLs.count)])
        }

        let musicTrack   = findMusicTrack(preferred: preferences.selectedMusicTrack)
        var musicOffset  = 0.0

        for (segIdx, chunk) in chunks.enumerated() {
            let segURL  = project.clipsDir.appending(
                path: String(format: "_middle_%02d.mp4", segIdx + 1))
            let isFirst = segIdx == 0
            let isLast  = segIdx == chunks.count - 1
            let segDuration = segmentDuration(clipCount: chunk.count)

            if let music = musicTrack {
                let rawURL = project.clipsDir.appending(
                    path: String(format: "_raw_%02d.mp4", segIdx + 1))
                try await concatenateWithXfade(clips: chunk, outputURL: rawURL,
                                               isFirst: isFirst, isLast: isLast)
                try await mixMusic(videoURL: rawURL, musicURL: music,
                                   musicOffset: musicOffset, duration: segDuration,
                                   outputURL: segURL)
                try? FileManager.default.removeItem(at: rawURL)
            } else {
                try await concatenateWithXfade(clips: chunk, outputURL: segURL,
                                               isFirst: isFirst, isLast: isLast)
            }
            musicOffset += segDuration
        }
    }

    private func segmentDuration(clipCount: Int) -> Double {
        let d = AppConfig.clipOutLenS, x = AppConfig.xfadeDuration
        return Double(clipCount) * d - Double(max(0, clipCount - 1)) * x
    }

    // MARK: - AVFoundation xfade concat

    /// Concatenate clips with cross-dissolve transitions and optional fade in/out.
    /// Uses two alternating video tracks with AVMutableVideoCompositionLayerInstruction
    /// opacity ramps — the AVFoundation equivalent of FFmpeg's xfade filter.
    private func concatenateWithXfade(clips: [URL], outputURL: URL,
                                       isFirst: Bool, isLast: Bool) async throws {
        guard !clips.isEmpty else { return }

        let D        = AppConfig.clipOutLenS
        let X        = AppConfig.xfadeDuration
        let fadeDur  = AppConfig.fadeInOutDuration
        let ts       = CMTimeScale(600)

        let dCM      = CMTimeMakeWithSeconds(D,       preferredTimescale: ts)
        let xCM      = CMTimeMakeWithSeconds(X,       preferredTimescale: ts)
        let stepCM   = CMTimeMakeWithSeconds(D - X,   preferredTimescale: ts)
        let fadeCM   = CMTimeMakeWithSeconds(fadeDur, preferredTimescale: ts)

        // Single-clip fast path — copy or fade-encode
        if clips.count == 1 {
            try await encodeSingleClip(clips[0], outputURL: outputURL,
                                       isFirst: isFirst, isLast: isLast,
                                       duration: D, fadeDur: fadeDur)
            return
        }

        let composition = AVMutableComposition()
        // Two alternating video tracks for cross-dissolve
        let trackA = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let trackB = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!

        // Insert clips into alternating tracks
        var insertTime = CMTime.zero
        for (i, url) in clips.enumerated() {
            let asset  = AVURLAsset(url: url)
            let vTrack = (i % 2 == 0) ? trackA : trackB
            let srcRange = CMTimeRange(start: .zero, duration: dCM)
            if let src = try? await asset.loadTracks(withMediaType: .video).first {
                try vTrack.insertTimeRange(srcRange, of: src, at: insertTime)
            }
            if let src = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(srcRange, of: src, at: insertTime)
            }
            if i < clips.count - 1 { insertTime = insertTime + stepCM }
        }

        let totalDurS = segmentDuration(clipCount: clips.count)
        let totalDurCM = CMTimeMakeWithSeconds(totalDurS, preferredTimescale: ts)

        // Build instructions: non-transition regions + dissolve regions
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for i in 0..<clips.count {
            let useA        = (i % 2 == 0)
            let currTrack   = useA ? trackA : trackB
            let nextTrack   = useA ? trackB : trackA
            let clipStart   = CMTimeMakeWithSeconds(Double(i) * (D - X), preferredTimescale: ts)

            // Non-transition middle of clip i
            // Starts after previous transition ends (clipStart + X if i > 0, else clipStart)
            let midStart = i == 0 ? clipStart : clipStart + xCM
            // Ends at transition to next clip (clipStart + D - X), or totalDur for last clip
            let midEnd   = i < clips.count - 1
                ? clipStart + stepCM
                : totalDurCM

            if midStart < midEnd {
                let midRange     = CMTimeRange(start: midStart, end: midEnd)
                let midInstr     = AVMutableVideoCompositionInstruction()
                midInstr.timeRange = midRange
                let layer        = AVMutableVideoCompositionLayerInstruction(assetTrack: currTrack)

                // Fade in on very first segment
                if i == 0 && isFirst {
                    layer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1,
                                         timeRange: CMTimeRange(start: .zero, duration: fadeCM))
                }
                // Fade out on very last segment's non-transition portion
                if i == clips.count - 1 && isLast {
                    let fadeStart = totalDurCM - fadeCM
                    layer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0,
                                         timeRange: CMTimeRange(start: fadeStart, duration: fadeCM))
                }

                midInstr.layerInstructions = [layer]
                instructions.append(midInstr)
            }

            // Transition to next clip
            if i < clips.count - 1 {
                let transStart = clipStart + stepCM
                let transRange = CMTimeRange(start: transStart, duration: xCM)
                let transInstr = AVMutableVideoCompositionInstruction()
                transInstr.timeRange = transRange

                let outLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: currTrack)
                outLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: transRange)
                let inLayer  = AVMutableVideoCompositionLayerInstruction(assetTrack: nextTrack)
                inLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: transRange)
                transInstr.layerInstructions = [inLayer, outLayer]
                instructions.append(transInstr)
            }
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)
        videoComp.renderSize    = CGSize(width: AppConfig.HUD.outputW, height: AppConfig.HUD.outputH)
        videoComp.instructions  = instructions

        // Audio mix with fade in/out volume ramps
        let audioParams = AVMutableAudioMixInputParameters(track: audioTrack)
        audioParams.setVolume(Float(GlobalSettings.shared.rawAudioVolume), at: .zero)
        if isFirst {
            audioParams.setVolumeRamp(fromStartVolume: 0,
                                      toEndVolume: Float(GlobalSettings.shared.rawAudioVolume),
                                      timeRange: CMTimeRange(start: .zero, duration: fadeCM))
        }
        if isLast {
            let fadeStart = totalDurCM - fadeCM
            audioParams.setVolumeRamp(fromStartVolume: Float(GlobalSettings.shared.rawAudioVolume),
                                      toEndVolume: 0,
                                      timeRange: CMTimeRange(start: fadeStart, duration: fadeCM))
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [audioParams]

        try await VideoEncoder.export(
            composition:      composition,
            videoComposition: videoComp,
            audioMix:         audioMix,
            to:               outputURL
        )
    }

    /// Single-clip encode with optional fade in/out via AVMutableVideoComposition opacity ramps.
    private func encodeSingleClip(_ url: URL, outputURL: URL,
                                   isFirst: Bool, isLast: Bool,
                                   duration: Double, fadeDur: Double) async throws {
        let ts      = CMTimeScale(600)
        let durCM   = CMTimeMakeWithSeconds(duration, preferredTimescale: ts)
        let fadeCM  = CMTimeMakeWithSeconds(fadeDur,  preferredTimescale: ts)

        let composition = AVMutableComposition()
        let asset = AVURLAsset(url: url)

        let vTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        if let src = try? await asset.loadTracks(withMediaType: .video).first {
            try? vTrack.insertTimeRange(CMTimeRange(start: .zero, duration: durCM), of: src, at: .zero)
        }

        var audioMix: AVAudioMix? = nil
        if let src = try? await asset.loadTracks(withMediaType: .audio).first {
            let aTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try? aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: durCM), of: src, at: .zero)
            let params = AVMutableAudioMixInputParameters(track: aTrack)
            params.setVolume(Float(GlobalSettings.shared.rawAudioVolume), at: .zero)
            if isFirst {
                params.setVolumeRamp(fromStartVolume: 0,
                                     toEndVolume: Float(GlobalSettings.shared.rawAudioVolume),
                                     timeRange: CMTimeRange(start: .zero, duration: fadeCM))
            }
            if isLast {
                let fadeStart = durCM - fadeCM
                params.setVolumeRamp(fromStartVolume: Float(GlobalSettings.shared.rawAudioVolume),
                                     toEndVolume: 0,
                                     timeRange: CMTimeRange(start: fadeStart, duration: fadeCM))
            }
            let mix = AVMutableAudioMix(); mix.inputParameters = [params]; audioMix = mix
        }

        // Only need video composition if applying fades
        var videoComp: AVVideoComposition? = nil
        if isFirst || isLast {
            let instr = AVMutableVideoCompositionInstruction()
            instr.timeRange = CMTimeRange(start: .zero, duration: durCM)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
            if isFirst {
                layer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1,
                                     timeRange: CMTimeRange(start: .zero, duration: fadeCM))
            }
            if isLast {
                layer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0,
                                     timeRange: CMTimeRange(start: durCM - fadeCM, duration: fadeCM))
            }
            instr.layerInstructions = [layer]
            let vc = AVMutableVideoComposition()
            vc.frameDuration = CMTime(value: 1, timescale: 30)
            vc.renderSize    = CGSize(width: AppConfig.HUD.outputW, height: AppConfig.HUD.outputH)
            vc.instructions  = [instr]
            videoComp = vc
        }

        try await VideoEncoder.export(
            composition:      composition,
            videoComposition: videoComp,
            audioMix:         audioMix,
            to:               outputURL
        )
    }

    // MARK: - Music mixing

    /// Mix background music into a segment at the correct playback offset.
    /// Replaces FFmpeg loudnorm+amix with AVMutableComposition + AVAudioMix volume control.
    private func mixMusic(videoURL: URL, musicURL: URL,
                           musicOffset: Double, duration: Double,
                           outputURL: URL) async throws {
        let ts      = CMTimeScale(600)
        let durCM   = CMTimeMakeWithSeconds(duration,     preferredTimescale: ts)
        let offCM   = CMTimeMakeWithSeconds(musicOffset,  preferredTimescale: ts)

        let videoAsset = AVURLAsset(url: videoURL)
        let musicAsset = AVURLAsset(url: musicURL)

        let composition = AVMutableComposition()

        // Video track (copy)
        if let srcV = try? await videoAsset.loadTracks(withMediaType: .video).first {
            let vTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try? vTrack.insertTimeRange(CMTimeRange(start: .zero, duration: durCM), of: srcV, at: .zero)
        }

        // Camera audio track
        var rawAudioTrack: AVMutableCompositionTrack? = nil
        if let srcA = try? await videoAsset.loadTracks(withMediaType: .audio).first {
            let aTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try? aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: durCM), of: srcA, at: .zero)
            rawAudioTrack = aTrack
        }

        // Music audio track — seek to musicOffset, loop if shorter than segment
        var musicTrack: AVMutableCompositionTrack? = nil
        if let srcM = try? await musicAsset.loadTracks(withMediaType: .audio).first {
            let musicDur = try await musicAsset.load(.duration)
            let mTrack   = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            var remaining = durCM
            var destTime  = CMTime.zero
            var srcOffset = offCM

            // Loop music to fill the segment duration
            while remaining > .zero {
                let avail    = musicDur - srcOffset
                let insert   = CMTimeMinimum(remaining, avail > .zero ? avail : musicDur)
                let srcRange = CMTimeRange(start: srcOffset, duration: insert)
                try? mTrack.insertTimeRange(srcRange, of: srcM, at: destTime)
                destTime  = destTime + insert
                remaining = remaining - insert
                srcOffset = .zero   // loop from start after first pass
            }
            musicTrack = mTrack
        }

        // AVAudioMix — set volumes for raw audio and music
        var inputParams: [AVMutableAudioMixInputParameters] = []
        if let raw = rawAudioTrack {
            let p = AVMutableAudioMixInputParameters(track: raw)
            p.setVolume(Float(GlobalSettings.shared.rawAudioVolume), at: .zero)
            inputParams.append(p)
        }
        if let music = musicTrack {
            let p = AVMutableAudioMixInputParameters(track: music)
            p.setVolume(Float(GlobalSettings.shared.musicVolume), at: .zero)
            inputParams.append(p)
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParams

        try await VideoEncoder.export(
            composition: composition,
            audioMix:    audioMix,
            to:          outputURL
        )
    }

    // MARK: - Music lookup

    private func findMusicTrack(preferred: String = "") -> URL? {
        let extensions = ["mp3", "m4a", "aac", "wav"]
        var candidates: [URL] = []

        if let bundleURL = Bundle.main.resourceURL {
            let musicDir = bundleURL.appending(path: "music")
            if let files = try? FileManager.default.contentsOfDirectory(
                at: musicDir, includingPropertiesForKeys: nil) {
                candidates += files.filter { extensions.contains($0.pathExtension.lowercased()) }
            }
        }
        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                candidates += urls
            }
        }
        let repoMusic = URL(fileURLWithPath:
            "/Volumes/AData/Github/velo-films-swift/Shared/Resources/music")
        if let files = try? FileManager.default.contentsOfDirectory(
            at: repoMusic, includingPropertiesForKeys: nil) {
            candidates += files.filter { extensions.contains($0.pathExtension.lowercased()) }
        }

        if !preferred.isEmpty,
           let match = candidates.first(where: { $0.lastPathComponent == preferred }) {
            return match
        }
        return candidates.randomElement()
    }

    // MARK: - Directory cleanup

    private func clearDirectory(_ url: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: url.path) else { return }
        for f in files { try? fm.removeItem(at: url.appending(path: f)) }
    }

    private func clearClips(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files {
            guard f.hasSuffix(".mp4") || f.hasSuffix(".mov") else { continue }
            guard !f.hasPrefix("_intro") && !f.hasPrefix("_outro") else { continue }
            try? fm.removeItem(at: dir.appending(path: f))
        }
    }
}
