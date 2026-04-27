import Foundation
import AVFoundation
import CoreGraphics
import MapKit
import CoreLocation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Builds _intro.mp4: logo → map+banner → collage crossfade chain, with music.
/// Mirrors intro_builder.py. All rendering via AVFoundation + Core Graphics.
enum IntroBuilder {

    static func build(project: Project,
                      selectRows: [SelectRow],
                      flattenRows: [FlattenRow]) async throws {
        let outputURL = project.clipsDir.appending(path: "_intro.mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let assetsDir = project.splashAssetsDir
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let stats  = computeRideStats(flattenRows: flattenRows)
        let frames = collectFrames(from: project.framesDir, selectRows: selectRows, max: 24)

        let W = AppConfig.HUD.outputW, H = AppConfig.HUD.outputH
        let bannerH = AppConfig.bannerHeight

        // 1. Render PNG assets
        let mapPNG = assetsDir.appending(path: "intro_map.png")
        await renderMapBanner(flattenRows: flattenRows, stats: stats, project: project,
                              outputURL: mapPNG, width: W, height: H, bannerHeight: bannerH)

        let collagePNG = assetsDir.appending(path: "intro_collage.png")
        try renderCollage(frames: frames, outputURL: collagePNG,
                          width: W, height: H, bannerHeight: bannerH,
                          stats: stats, project: project)

        // 2. Load CGImages and encode stills to video clips
        guard let mapCG     = loadCGImage(from: mapPNG),
              let collageCG = loadCGImage(from: collagePNG) else {
            throw PipelineError.renderFailed("IntroBuilder: could not load splash PNGs")
        }

        let clipDur  = 3.0
        let xfadeDur = 1.2

        var clips: [(image: CGImage, url: URL)] = []

        if let logoURL = findResourceImage(named: "velo_films"),
           let logoCG  = loadCGImage(from: logoURL) {
            let c = assetsDir.appending(path: "intro_logo.mp4")
            try await VideoEncoder.encodeStill(image: logoCG, duration: clipDur, outputURL: c)
            clips.append((logoCG, c))
        }

        let mapClip = assetsDir.appending(path: "intro_map.mp4")
        try await VideoEncoder.encodeStill(image: mapCG, duration: clipDur, outputURL: mapClip)
        clips.append((mapCG, mapClip))

        let collageClip = assetsDir.appending(path: "intro_collage.mp4")
        try await VideoEncoder.encodeStill(image: collageCG, duration: clipDur, outputURL: collageClip)
        clips.append((collageCG, collageClip))

        // 3. Cross-dissolve chain
        let rawURL = assetsDir.appending(path: "intro_raw.mp4")
        try await crossDissolveChain(clips: clips.map(\.url),
                                     clipDur: clipDur, xfadeDur: xfadeDur,
                                     outputURL: rawURL)

        // 4. Add music or keep silent
        let totalDur = Double(clips.count) * clipDur - Double(clips.count - 1) * xfadeDur
        if let musicURL = findResourceAudio(named: "intro") {
            try await mixAudio(videoURL: rawURL, musicURL: musicURL,
                               duration: totalDur, musicVolume: 0.85, outputURL: outputURL)
            try? FileManager.default.removeItem(at: rawURL)
        } else {
            try FileManager.default.moveItem(at: rawURL, to: outputURL)
        }
    }

    // MARK: - Cross-dissolve chain (shared with OutroBuilder)

    /// Joins N video clips with cross-dissolve transitions using AVMutableComposition.
    static func crossDissolveChain(clips: [URL], clipDur: Double, xfadeDur: Double,
                                    outputURL: URL) async throws {
        guard clips.count >= 2 else {
            // Single clip — just copy
            if let first = clips.first {
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.copyItem(at: first, to: outputURL)
            }
            return
        }

        let ts      = CMTimeScale(600)
        let dCM     = CMTimeMakeWithSeconds(clipDur,  preferredTimescale: ts)
        let xCM     = CMTimeMakeWithSeconds(xfadeDur, preferredTimescale: ts)
        let stepCM  = dCM - xCM

        let composition = AVMutableComposition()
        let trackA = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let trackB = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!

        var insertTime = CMTime.zero
        for (i, url) in clips.enumerated() {
            let asset  = AVURLAsset(url: url)
            let vTrack = (i % 2 == 0) ? trackA : trackB
            if let src = try? await asset.loadTracks(withMediaType: .video).first {
                try? vTrack.insertTimeRange(CMTimeRange(start: .zero, duration: dCM),
                                            of: src, at: insertTime)
            }
            if i < clips.count - 1 { insertTime = insertTime + stepCM }
        }

        let totalDurS  = Double(clips.count) * clipDur - Double(clips.count - 1) * xfadeDur
        let totalDurCM = CMTimeMakeWithSeconds(totalDurS, preferredTimescale: ts)

        var instructions: [AVMutableVideoCompositionInstruction] = []
        for i in 0..<clips.count {
            let useA      = (i % 2 == 0)
            let curr      = useA ? trackA : trackB
            let next      = useA ? trackB : trackA
            let clipStart = CMTimeMakeWithSeconds(Double(i) * (clipDur - xfadeDur),
                                                  preferredTimescale: ts)

            let midStart = i == 0 ? clipStart : clipStart + xCM
            let midEnd   = i < clips.count - 1 ? clipStart + stepCM : totalDurCM

            if midStart < midEnd {
                let instr = AVMutableVideoCompositionInstruction()
                instr.timeRange = CMTimeRange(start: midStart, end: midEnd)
                instr.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: curr)]
                instructions.append(instr)
            }

            if i < clips.count - 1 {
                let transStart = clipStart + stepCM
                let transRange = CMTimeRange(start: transStart, duration: xCM)
                let transInstr = AVMutableVideoCompositionInstruction()
                transInstr.timeRange = transRange
                let outL = AVMutableVideoCompositionLayerInstruction(assetTrack: curr)
                outL.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: transRange)
                let inL  = AVMutableVideoCompositionLayerInstruction(assetTrack: next)
                inL.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: transRange)
                transInstr.layerInstructions = [inL, outL]
                instructions.append(transInstr)
            }
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)
        videoComp.renderSize    = CGSize(width: AppConfig.HUD.outputW, height: AppConfig.HUD.outputH)
        videoComp.instructions  = instructions

        try await VideoEncoder.export(composition: composition,
                                      videoComposition: videoComp,
                                      to: outputURL)
    }

    // MARK: - Music mix (replaces silent track with music audio)

    /// Replace or add audio from musicURL into an existing video file.
    static func mixAudio(videoURL: URL, musicURL: URL,
                          duration: Double, musicVolume: Float,
                          outputURL: URL) async throws {
        let ts         = CMTimeScale(600)
        let durCM      = CMTimeMakeWithSeconds(duration, preferredTimescale: ts)
        let videoAsset = AVURLAsset(url: videoURL)
        let musicAsset = AVURLAsset(url: musicURL)

        let composition = AVMutableComposition()

        // Video track
        if let srcV = try? await videoAsset.loadTracks(withMediaType: .video).first {
            let vTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try? vTrack.insertTimeRange(CMTimeRange(start: .zero, duration: durCM),
                                        of: srcV, at: .zero)
        }

        // Music audio — loop to fill duration
        var musicTrackComp: AVMutableCompositionTrack? = nil
        if let srcM = try? await musicAsset.loadTracks(withMediaType: .audio).first {
            let musicDur  = try await musicAsset.load(.duration)
            let mTrack    = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            var remaining = durCM
            var destTime  = CMTime.zero
            while remaining > .zero {
                let insert   = CMTimeMinimum(remaining, musicDur)
                try? mTrack.insertTimeRange(CMTimeRange(start: .zero, duration: insert),
                                            of: srcM, at: destTime)
                destTime  = destTime + insert
                remaining = remaining - insert
            }
            musicTrackComp = mTrack
        }

        var inputParams: [AVMutableAudioMixInputParameters] = []
        if let mt = musicTrackComp {
            let p = AVMutableAudioMixInputParameters(track: mt)
            p.setVolume(musicVolume, at: .zero)
            inputParams.append(p)
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParams

        try await VideoEncoder.export(composition: composition,
                                      audioMix: audioMix,
                                      to: outputURL)
    }

    // MARK: - Resource lookup

    static func findResourceImage(named name: String) -> URL? {
        let exts = ["png", "jpg"]
        for ext in exts {
            if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        }
        let repoBase = URL(fileURLWithPath:
            "/Volumes/AData/Github/velo-films-swift/Shared/Resources")
        for ext in exts {
            let u = repoBase.appending(path: "\(name).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    static func findResourceAudio(named name: String) -> URL? {
        let exts = ["mp3", "m4a", "aac", "wav"]
        for ext in exts {
            if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        }
        let repoBase = URL(fileURLWithPath:
            "/Volumes/AData/Github/velo-films-swift/Shared/Resources")
        for ext in exts {
            let u = repoBase.appending(path: "\(name).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // MARK: - Ride stats

    static func computeRideStats(flattenRows: [FlattenRow]) -> RideStats {
        guard flattenRows.count >= 2 else { return RideStats() }
        var totalDistM = 0.0, totalClimb = 0.0
        for i in 1..<flattenRows.count {
            let prev = flattenRows[i-1], curr = flattenRows[i]
            totalDistM += haversineM(prev.lat, prev.lon, curr.lat, curr.lon)
            if curr.elevation > prev.elevation { totalClimb += curr.elevation - prev.elevation }
        }
        let durationS = (flattenRows.last?.gpxEpoch ?? 0) - (flattenRows.first?.gpxEpoch ?? 0)
        let avgSpeed  = durationS > 0 ? (totalDistM / 1000.0) / (durationS / 3600.0) : 0
        return RideStats(distanceKm: totalDistM / 1000.0, durationS: durationS,
                         avgSpeedKmh: avgSpeed, totalClimbM: totalClimb)
    }

    // MARK: - Frame collection

    static func collectFrames(from dir: URL, selectRows: [SelectRow], max: Int) -> [URL] {
        let recommended = Set(selectRows.filter { $0.recommended }.map { $0.base.index })
        let all = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        let jpgs = all.filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let filtered = jpgs.filter { url in
            recommended.contains(where: { url.lastPathComponent.contains(String($0)) })
        }
        return Array((filtered.isEmpty ? jpgs : filtered).prefix(max))
    }

    // MARK: - Map + banner

    static func renderMapBanner(flattenRows: [FlattenRow], stats: RideStats,
                                  project: Project, outputURL: URL,
                                  width: Int, height: Int, bannerHeight: Int) async {
        let mapH = height - bannerHeight
        let gpxPoints = flattenRows.map {
            GPXPoint(epoch: $0.gpxEpoch, lat: $0.lat, lon: $0.lon,
                     elevation: $0.elevation, hr: $0.hrBpm, cadence: $0.cadenceRpm,
                     speedKmh: $0.speedKmh, gradientPct: $0.gradientPct)
        }

        var mapImage: CGImage? = nil
        if gpxPoints.count >= 2 {
            let lats = gpxPoints.map { $0.lat }, lons = gpxPoints.map { $0.lon }
            let pad  = AppConfig.Map.paddingPct
            let latSpan = max(lats.max()! - lats.min()!, 0.001) * (1 + 2 * pad)
            let lonSpan = max(lons.max()! - lons.min()!, 0.001) * (1 + 2 * pad)
            let opts = MKMapSnapshotter.Options()
            opts.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude:  (lats.min()! + lats.max()!) / 2,
                                               longitude: (lons.min()! + lons.max()!) / 2),
                span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
            opts.size     = CGSize(width: width, height: mapH)
            opts.mapType  = .standard
            opts.showsBuildings = false

            if let snap = try? await MKMapSnapshotter(options: opts).start() {
                let ctx = makeBitmapContext(width: width, height: mapH)
                #if os(macOS)
                let cg = snap.image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                #else
                let cg = snap.image.cgImage!
                #endif
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: mapH))

                let rw = AppConfig.Map.splashRouteWidth
                let rc = AppConfig.Map.routeColor
                ctx.setStrokeColor(CGColor(red: CGFloat(rc.0)/255, green: CGFloat(rc.1)/255,
                                           blue: CGFloat(rc.2)/255, alpha: 0.9))
                ctx.setLineWidth(CGFloat(rw)); ctx.setLineCap(.round); ctx.setLineJoin(.round)
                let path = CGMutablePath()
                var started = false
                for pt in gpxPoints {
                    let p = snap.point(for: CLLocationCoordinate2D(latitude: pt.lat, longitude: pt.lon))
                    if !started { path.move(to: p); started = true } else { path.addLine(to: p) }
                }
                ctx.addPath(path); ctx.strokePath()
                mapImage = ctx.makeImage()
            }
        }

        let ctx = makeBitmapContext(width: width, height: height)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let mi = mapImage {
            ctx.draw(mi, in: CGRect(x: 0, y: 0, width: width, height: mapH))
        }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.82))
        ctx.fill(CGRect(x: 0, y: mapH, width: width, height: bannerHeight))

        let titleSize = CGFloat(72 * width / 2560)
        drawCentred(project.name, in: ctx, x: width / 2,
                    y: mapH + bannerHeight / 3, fontSize: titleSize, bold: true)

        let dS = Int(stats.durationS)
        let statsStr = String(format: "%.1f km   %dh %02dm   %.1f km/h avg   %.0f m ascent",
                              stats.distanceKm, dS / 3600, (dS % 3600) / 60,
                              stats.avgSpeedKmh, stats.totalClimbM)
        drawCentred(statsStr, in: ctx, x: width / 2,
                    y: mapH + bannerHeight * 2 / 3,
                    fontSize: CGFloat(48 * width / 2560), bold: false)

        savePNG(ctx, to: outputURL)
    }

    // MARK: - Collage

    static func renderCollage(frames: [URL], outputURL: URL,
                               width: Int, height: Int, bannerHeight: Int,
                               stats: RideStats, project: Project) throws {
        let ctx = makeBitmapContext(width: width, height: height)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard !frames.isEmpty else { savePNG(ctx, to: outputURL); return }

        let collageH = height - bannerHeight
        let cols = min(frames.count, 5)
        let rows = Int(ceil(Double(frames.count) / Double(cols)))
        let tileW = width / cols, tileH = collageH / rows

        for (i, url) in frames.enumerated() {
            guard i < cols * rows else { break }
            let col = i % cols, row = i / cols
            let destRect = CGRect(x: col * tileW, y: row * tileH, width: tileW, height: tileH)
            guard let src = loadCGImage(from: url) else { continue }
            let srcW = CGFloat(src.width), srcH = CGFloat(src.height)
            let tileAspect = CGFloat(tileW) / CGFloat(tileH)
            let srcAspect  = srcW / srcH
            let cropRect: CGRect
            if srcAspect > tileAspect {
                let cropW = srcH * tileAspect
                cropRect = CGRect(x: (srcW - cropW) / 2, y: 0, width: cropW, height: srcH)
            } else {
                let cropH = srcW / tileAspect
                cropRect = CGRect(x: 0, y: (srcH - cropH) / 2, width: srcW, height: cropH)
            }
            if let cropped = src.cropping(to: cropRect) { ctx.draw(cropped, in: destRect) }
        }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.75))
        ctx.fill(CGRect(x: 0, y: collageH, width: width, height: bannerHeight))

        let titleSize = CGFloat(72 * width / 2560)
        drawCentred(project.name, in: ctx, x: width / 2,
                    y: collageH + bannerHeight / 3, fontSize: titleSize, bold: true)

        let dS = Int(stats.durationS)
        let statsStr = String(format: "%.1f km   %dh %02dm   %.1f km/h avg   %.0f m ascent",
                              stats.distanceKm, dS / 3600, (dS % 3600) / 60,
                              stats.avgSpeedKmh, stats.totalClimbM)
        drawCentred(statsStr, in: ctx, x: width / 2,
                    y: collageH + bannerHeight * 2 / 3,
                    fontSize: CGFloat(48 * width / 2560), bold: false)

        savePNG(ctx, to: outputURL)
    }

    // MARK: - Drawing helpers

    static func drawCentred(_ text: String, in ctx: CGContext,
                             x: Int, y: Int, fontSize: CGFloat, bold: Bool) {
        let fontName = bold ? "SFNS-Bold" : "SFNS-Regular"
        let font     = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName:            font,
            kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        let line   = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: CGFloat(x) - bounds.width / 2 - bounds.minX,
                                   y: CGFloat(y) - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    static func makeBitmapContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func loadCGImage(from url: URL) -> CGImage? {
#if os(macOS)
        guard let img = NSImage(contentsOf: url) else { return nil }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
#else
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        return img.cgImage
#endif
    }

    static func savePNG(_ ctx: CGContext, to url: URL) {
        guard let img = ctx.makeImage() else { return }
#if os(macOS)
        let rep = NSBitmapImageRep(cgImage: img)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url, options: .atomic)
        }
#else
        if let data = UIImage(cgImage: img).pngData() {
            try? data.write(to: url, options: .atomic)
        }
#endif
    }
}

struct RideStats {
    var distanceKm:   Double = 0
    var durationS:    Double = 0
    var avgSpeedKmh:  Double = 0
    var totalClimbM:  Double = 0
}
