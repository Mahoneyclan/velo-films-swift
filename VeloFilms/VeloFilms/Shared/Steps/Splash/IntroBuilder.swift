import Foundation
import CoreGraphics
import MapKit
import CoreLocation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Builds _intro.mp4: map+banner → crossfade → collage → music.
/// Mirrors intro_builder.py. Flip animation simplified to xfade dissolve.
enum IntroBuilder {

    static func build(project: Project,
                      selectRows: [SelectRow],
                      flattenRows: [FlattenRow],
                      bridge: any FFmpegBridge) async throws {
        let outputURL = project.clipsDir.appending(path: "_intro.mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let assetsDir = project.splashAssetsDir
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let stats = computeRideStats(flattenRows: flattenRows)
        let frames = collectFrames(from: project.framesDir, selectRows: selectRows, max: 24)

        let W = AppConfig.HUD.outputW, H = AppConfig.HUD.outputH
        let bannerH = AppConfig.bannerHeight
        let enc = AppConfig.Encoding.self
        let clipDuration = 3.0
        let xfadeDur    = 1.2

        // 1. Map + banner PNG
        let mapPNG = assetsDir.appending(path: "intro_map.png")
        await renderMapBanner(flattenRows: flattenRows, stats: stats,
                              project: project, outputURL: mapPNG,
                              width: W, height: H, bannerHeight: bannerH)

        // 2. Collage PNG
        let collagePNG = assetsDir.appending(path: "intro_collage.png")
        try renderCollage(frames: frames, outputURL: collagePNG,
                          width: W, height: H, bannerHeight: bannerH,
                          stats: stats, project: project)

        // 3. Encode map + collage stills
        let mapClip = assetsDir.appending(path: "intro_map.mp4")
        try await encodeStill(imageURL: mapPNG, duration: clipDuration, outputURL: mapClip, bridge: bridge)

        let collageClip = assetsDir.appending(path: "intro_collage.mp4")
        try await encodeStill(imageURL: collagePNG, duration: clipDuration, outputURL: collageClip, bridge: bridge)

        // 4. Logo clip (velo_films.png)
        let logoClip: URL?
        if let logoURL = findResourceImage(named: "velo_films") {
            let c = assetsDir.appending(path: "intro_logo.mp4")
            try await encodeStill(imageURL: logoURL, duration: clipDuration, outputURL: c, bridge: bridge)
            logoClip = c
        } else {
            logoClip = nil
        }

        // 5. Crossfade chain → raw silent video
        let rawURL = assetsDir.appending(path: "intro_raw.mp4")
        try? FileManager.default.removeItem(at: rawURL)

        if let logo = logoClip {
            // logo → map → collage (3-clip chain)
            let o1 = String(format: "%.3f", 1.0 * (clipDuration - xfadeDur))  // 1.800
            let o2 = String(format: "%.3f", 2.0 * (clipDuration - xfadeDur))  // 3.600
            _ = try await bridge.execute(arguments: [
                "-i", logo.path,
                "-i", mapClip.path,
                "-i", collageClip.path,
                "-filter_complex",
                "[0:v][1:v]xfade=transition=fade:duration=\(xfadeDur):offset=\(o1)[v1];" +
                "[v1][2:v]xfade=transition=fade:duration=\(xfadeDur):offset=\(o2)[vout];" +
                "[0:a][1:a]acrossfade=d=\(xfadeDur)[a1];" +
                "[a1][2:a]acrossfade=d=\(xfadeDur)[aout]",
                "-map", "[vout]", "-map", "[aout]",
                "-c:v", enc.codec, "-b:v", enc.bitrate,
                "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k",
                "-y", rawURL.path
            ])
        } else {
            // map → collage (2-clip fallback)
            _ = try await bridge.execute(arguments: [
                "-i", mapClip.path,
                "-i", collageClip.path,
                "-filter_complex",
                "[0:v][1:v]xfade=transition=fade:duration=\(xfadeDur):offset=1.800[vout];" +
                "[0:a][1:a]acrossfade=d=\(xfadeDur)[aout]",
                "-map", "[vout]", "-map", "[aout]",
                "-c:v", enc.codec, "-b:v", enc.bitrate,
                "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k",
                "-y", rawURL.path
            ])
        }

        // 6. Mix in intro.mp3 if available; otherwise rename raw → output
        let clipCount = logoClip != nil ? 3.0 : 2.0
        let totalDur  = clipCount * clipDuration - (clipCount - 1) * xfadeDur

        if let musicURL = findResourceAudio(named: "intro") {
            try await mixSplashMusic(videoURL: rawURL, musicURL: musicURL,
                                     duration: totalDur, outputURL: outputURL, bridge: bridge)
            try? FileManager.default.removeItem(at: rawURL)
        } else {
            try FileManager.default.moveItem(at: rawURL, to: outputURL)
        }
    }

    // MARK: - Splash music mix (replaces silent audio with music track)

    private static func mixSplashMusic(videoURL: URL, musicURL: URL,
                                        duration: Double, outputURL: URL,
                                        bridge: any FFmpegBridge) async throws {
        _ = try await bridge.execute(arguments: [
            "-i", videoURL.path,
            "-stream_loop", "-1", "-i", musicURL.path,
            "-map", "0:v", "-map", "1:a",
            "-af", "loudnorm=I=-16:TP=-1.5:LRA=11,volume=0.85",
            "-c:v", "copy",
            "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k",
            "-t", String(format: "%.3f", duration),
            "-y", outputURL.path
        ])
    }

    // MARK: - Resource lookup (bundle first, then repo Shared/Resources)

    static func findResourceImage(named name: String) -> URL? {
        let exts = ["png", "jpg"]
        for ext in exts {
            if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        }
        let repoBase = URL(fileURLWithPath: "/Volumes/AData/Github/velo-films-swift/Shared/Resources")
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
        let repoBase = URL(fileURLWithPath: "/Volumes/AData/Github/velo-films-swift/Shared/Resources")
        for ext in exts {
            let u = repoBase.appending(path: "\(name).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // MARK: - Ride stats

    static func computeRideStats(flattenRows: [FlattenRow]) -> RideStats {
        guard flattenRows.count >= 2 else { return RideStats() }
        var totalDistM = 0.0
        var totalClimb = 0.0
        for i in 1..<flattenRows.count {
            let prev = flattenRows[i-1], curr = flattenRows[i]
            totalDistM += haversineM(prev.lat, prev.lon, curr.lat, curr.lon)
            if curr.elevation > prev.elevation {
                totalClimb += curr.elevation - prev.elevation
            }
        }
        let durationS = (flattenRows.last?.gpxEpoch ?? 0) - (flattenRows.first?.gpxEpoch ?? 0)
        let avgSpeed = durationS > 0 ? (totalDistM / 1000.0) / (durationS / 3600.0) : 0
        return RideStats(distanceKm: totalDistM / 1000.0, durationS: durationS,
                         avgSpeedKmh: avgSpeed, totalClimbM: totalClimb)
    }

    // MARK: - Frame collection

    static func collectFrames(from dir: URL, selectRows: [SelectRow], max: Int) -> [URL] {
        let recommended = Set(selectRows.filter { $0.recommended }.map { $0.base.index })
        let all = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles)) ?? []
        let jpgs = all.filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Prefer recommended frames; fall back to all
        let filtered = jpgs.filter { url in
            recommended.contains(where: { url.lastPathComponent.contains(String($0)) })
        }
        let pool = filtered.isEmpty ? jpgs : filtered
        return Array(pool.prefix(max))
    }

    // MARK: - Map + banner

    private static func renderMapBanner(flattenRows: [FlattenRow],
                                         stats: RideStats,
                                         project: Project,
                                         outputURL: URL,
                                         width: Int, height: Int, bannerHeight: Int) async {
        let mapH = height - bannerHeight
        let gpxPoints = flattenRows.map {
            GPXPoint(epoch: $0.gpxEpoch, lat: $0.lat, lon: $0.lon,
                     elevation: $0.elevation, hr: $0.hrBpm, cadence: $0.cadenceRpm,
                     speedKmh: $0.speedKmh, gradientPct: $0.gradientPct)
        }

        // Fetch map snapshot for the route area
        var mapImage: CGImage? = nil
        if gpxPoints.count >= 2 {
            let lats = gpxPoints.map { $0.lat }
            let lons = gpxPoints.map { $0.lon }
            let pad = AppConfig.Map.paddingPct
            let latSpan = max(lats.max()! - lats.min()!, 0.001) * (1 + 2 * pad)
            let lonSpan = max(lons.max()! - lons.min()!, 0.001) * (1 + 2 * pad)
            let opts = MKMapSnapshotter.Options()
            opts.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                               longitude: (lons.min()! + lons.max()!) / 2),
                span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
            opts.size = CGSize(width: width, height: mapH)
            opts.mapType = .standard
            opts.showsBuildings = false

            if let snap = try? await MKMapSnapshotter(options: opts).start() {
                // Draw route over snapshot
                let ctx = makeBitmapContext(width: width, height: mapH)
                #if os(macOS)
                let cg = snap.image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                #else
                let cg = snap.image.cgImage!
                #endif
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: mapH))

                // Route polyline
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

        // Composite full frame: map area + dark banner
        let ctx = makeBitmapContext(width: width, height: height)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let mi = mapImage {
            ctx.draw(mi, in: CGRect(x: 0, y: 0, width: width, height: mapH))
        }

        // Banner (bottom strip, dark overlay)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.82))
        ctx.fill(CGRect(x: 0, y: mapH, width: width, height: bannerHeight))

        // Title: ride folder name
        let titleSize = CGFloat(72 * width / 2560)
        drawCentred(project.name, in: ctx, x: width / 2,
                    y: mapH + bannerHeight / 3,
                    fontSize: titleSize, bold: true)

        // Stats line
        let dS = Int(stats.durationS)
        let statsStr = String(format: "%.1f km   %dh %02dm   %.1f km/h avg   %.0f m ascent",
                              stats.distanceKm, dS / 3600, (dS % 3600) / 60,
                              stats.avgSpeedKmh, stats.totalClimbM)
        let statsSize = CGFloat(48 * width / 2560)
        drawCentred(statsStr, in: ctx, x: width / 2,
                    y: mapH + bannerHeight * 2 / 3,
                    fontSize: statsSize, bold: false)

        savePNG(ctx, to: outputURL)
    }

    // MARK: - Collage

    static func renderCollage(frames: [URL], outputURL: URL,
                                       width: Int, height: Int, bannerHeight: Int,
                                       stats: RideStats, project: Project) throws {
        let ctx = makeBitmapContext(width: width, height: height)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard !frames.isEmpty else {
            savePNG(ctx, to: outputURL); return
        }

        let collageH = height - bannerHeight
        let cols = min(frames.count, 5)
        let rows = Int(ceil(Double(frames.count) / Double(cols)))
        let tileW = width / cols
        let tileH = collageH / rows

        for (i, url) in frames.enumerated() {
            guard i < cols * rows else { break }
            let col = i % cols, row = i / cols
            let destRect = CGRect(x: col * tileW, y: row * tileH, width: tileW, height: tileH)

            guard let src = loadCGImage(from: url) else { continue }
            // Scale-to-fill: crop to tile aspect
            let srcW = CGFloat(src.width), srcH = CGFloat(src.height)
            let tileAspect = CGFloat(tileW) / CGFloat(tileH)
            let srcAspect = srcW / srcH
            let cropRect: CGRect
            if srcAspect > tileAspect {
                let cropW = srcH * tileAspect
                cropRect = CGRect(x: (srcW - cropW) / 2, y: 0, width: cropW, height: srcH)
            } else {
                let cropH = srcW / tileAspect
                cropRect = CGRect(x: 0, y: (srcH - cropH) / 2, width: srcW, height: cropH)
            }
            if let cropped = src.cropping(to: cropRect) {
                ctx.draw(cropped, in: destRect)
            }
        }

        // Banner
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

    // MARK: - FFmpeg helpers

    static func encodeStill(imageURL: URL, duration: Double,
                                     outputURL: URL, bridge: any FFmpegBridge) async throws {
        let enc = AppConfig.Encoding.self
        let W = AppConfig.HUD.outputW, H = AppConfig.HUD.outputH
        _ = try await bridge.execute(arguments: [
            "-loop", "1", "-framerate", "30",
            "-i", imageURL.path,
            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
            "-t", String(format: "%.2f", duration),
            "-vf", "scale=\(W):\(H):force_original_aspect_ratio=decrease,pad=\(W):\(H):(ow-iw)/2:(oh-ih)/2",
            "-c:v", enc.codec, "-b:v", enc.bitrate, "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "128k", "-shortest",
            "-y", outputURL.path
        ])
    }

    // MARK: - Drawing helpers

    static func drawCentred(_ text: String, in ctx: CGContext,
                                     x: Int, y: Int, fontSize: CGFloat, bold: Bool) {
        let fontName = bold ? "SFNS-Bold" : "SFNS-Regular"
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(
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
    var distanceKm: Double = 0
    var durationS: Double  = 0
    var avgSpeedKmh: Double = 0
    var totalClimbM: Double = 0
}
