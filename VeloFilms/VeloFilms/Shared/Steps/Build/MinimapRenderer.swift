import Foundation
import CoreGraphics
import MapKit
import CoreLocation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders a 390×390 minimap PNG per clip.
/// One MKMapSnapshotter call captures real map tiles once per ride; each per-clip
/// render draws the route polyline and position dot on top synchronously.
struct MinimapRenderer {

    struct BaseSnapshot {
        let snapshot: MKMapSnapshotter.Snapshot
    }

    // MARK: - One-time async setup

    /// Call once before the clip loop. Returns nil if gpxPoints too sparse.
    /// Never throws — network failure silently falls back to offline renderer.
    static func makeBaseSnapshot(gpxPoints: [GPXPoint]) async -> BaseSnapshot? {
        guard gpxPoints.count >= 2 else { return nil }

        let lats = gpxPoints.map { $0.lat }
        let lons = gpxPoints.map { $0.lon }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!

        let pad = AppConfig.Map.paddingPct
        let latSpan = max(maxLat - minLat, 0.001) * (1 + 2 * pad)
        let lonSpan = max(maxLon - minLon, 0.001) * (1 + 2 * pad)
        let midLat  = (minLat + maxLat) / 2
        let midLon  = (minLon + maxLon) / 2

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
        let size = AppConfig.HUD.mapW
        options.size = CGSize(width: size, height: size)
        options.mapType = .standard
        options.showsBuildings = false

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            return BaseSnapshot(snapshot: snapshot)
        } catch {
            return nil
        }
    }

    // MARK: - Per-clip render

    /// Renders one minimap PNG. Falls back to offline CG renderer if base is nil
    /// (e.g. no network during snapshot fetch).
    static func render(base: BaseSnapshot?,
                       gpxPoints: [GPXPoint],
                       currentEpoch: Double,
                       outputURL: URL) throws {
        guard gpxPoints.count >= 2 else { return }
        let size = AppConfig.HUD.mapW
        let ctx = makeContext(size: size)

        if let base {
            drawSnapshotBackground(base.snapshot, into: ctx, size: size)
            drawRoute(gpxPoints, snapshot: base.snapshot, into: ctx, size: size)
            drawMarker(gpxPoints: gpxPoints, epoch: currentEpoch,
                       snapshot: base.snapshot, into: ctx, size: size)
        } else {
            drawOfflineBackground(gpxPoints: gpxPoints, into: ctx, size: size)
        }

        let image = ctx.makeImage()!
        try saveImage(image, to: outputURL)
    }

    // MARK: - Drawing helpers

    private static func drawSnapshotBackground(_ snapshot: MKMapSnapshotter.Snapshot,
                                               into ctx: CGContext, size: Int) {
        // CGBitmapContext: y=0 maps to the TOP of the saved PNG (same as UIKit y-down).
        // Draw the snapshot cgImage directly — no flip needed.
        #if os(macOS)
        let cgImage = snapshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        #else
        let cgImage = snapshot.image.cgImage!
        #endif
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    }

    private static func drawRoute(_ gpxPoints: [GPXPoint],
                                  snapshot: MKMapSnapshotter.Snapshot,
                                  into ctx: CGContext, size: Int) {
        let rc = AppConfig.Map.routeColor
        ctx.setStrokeColor(CGColor(red: CGFloat(rc.0)/255,
                                   green: CGFloat(rc.1)/255,
                                   blue: CGFloat(rc.2)/255, alpha: 0.85))
        ctx.setLineWidth(CGFloat(AppConfig.Map.routeWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let path = CGMutablePath()
        var started = false
        for pt in gpxPoints {
            let p = cgPoint(snapshot, lat: pt.lat, lon: pt.lon, size: size)
            if !started { path.move(to: p); started = true }
            else { path.addLine(to: p) }
        }
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func drawMarker(gpxPoints: [GPXPoint], epoch: Double,
                                   snapshot: MKMapSnapshotter.Snapshot,
                                   into ctx: CGContext, size: Int) {
        guard let nearest = gpxPoints.min(by: { abs($0.epoch - epoch) < abs($1.epoch - epoch) }) else { return }
        let p  = cgPoint(snapshot, lat: nearest.lat, lon: nearest.lon, size: size)
        let mc = AppConfig.Map.markerColor
        let r  = CGFloat(AppConfig.Map.markerRadius) / 2

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: p.x - r - 2, y: p.y - r - 2, width: (r+2)*2, height: (r+2)*2))
        ctx.setFillColor(CGColor(red: CGFloat(mc.0)/255,
                                 green: CGFloat(mc.1)/255,
                                 blue: CGFloat(mc.2)/255, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2))
    }

    /// Offline fallback: dark background + route + marker using lat/lon bounding box projection.
    private static func drawOfflineBackground(gpxPoints: [GPXPoint],
                                              into ctx: CGContext, size: Int) {
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let lats = gpxPoints.map { $0.lat }
        let lons = gpxPoints.map { $0.lon }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let pad = AppConfig.Map.paddingPct
        let latSpan = max(maxLat - minLat, 0.001) * (1 + 2 * pad)
        let lonSpan = max(maxLon - minLon, 0.001) * (1 + 2 * pad)
        let midLat  = (minLat + maxLat) / 2
        let midLon  = (minLon + maxLon) / 2
        let s = Double(size)
        func px(_ lon: Double) -> CGFloat { CGFloat((lon - (midLon - lonSpan/2)) / lonSpan * s) }
        func py(_ lat: Double) -> CGFloat { CGFloat((1 - (lat - (midLat - latSpan/2)) / latSpan) * s) }

        let rc = AppConfig.Map.routeColor
        ctx.setStrokeColor(CGColor(red: CGFloat(rc.0)/255, green: CGFloat(rc.1)/255,
                                   blue: CGFloat(rc.2)/255, alpha: 1))
        ctx.setLineWidth(CGFloat(AppConfig.Map.routeWidth))
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: px(gpxPoints[0].lon), y: py(gpxPoints[0].lat)))
        for pt in gpxPoints.dropFirst() {
            path.addLine(to: CGPoint(x: px(pt.lon), y: py(pt.lat)))
        }
        ctx.addPath(path); ctx.strokePath()
    }

    // MARK: - Coordinate conversion

    /// snapshot.point(for:) returns UIKit/screen coords (y-down, origin top-left).
    /// CGBitmapContext saves with y=0 at the top of the PNG, so coordinates map directly — no flip.
    private static func cgPoint(_ snapshot: MKMapSnapshotter.Snapshot,
                                 lat: Double, lon: Double, size: Int) -> CGPoint {
        let p = snapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        return CGPoint(x: p.x, y: p.y)
    }

    // MARK: - Context / save

    private static func makeContext(size: Int) -> CGContext {
        CGContext(data: nil, width: size, height: size,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private static func saveImage(_ image: CGImage, to url: URL) throws {
#if os(macOS)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
#else
        guard let data = UIImage(cgImage: image).pngData() else { return }
#endif
        try data.write(to: url, options: .atomic)
    }
}
