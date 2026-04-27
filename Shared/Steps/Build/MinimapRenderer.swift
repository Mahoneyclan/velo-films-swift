import Foundation
import MapKit
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders a 390×390 minimap PNG per clip using MKMapSnapshotter.
/// Mirrors minimap_prerenderer.py + map_overlay.py:
///   - Route polyline in green RGB(40,180,60)
///   - Position marker dot in yellow RGB(230,175,0)
///   - Map bottom-aligned on transparent square canvas
///   - Basemap: standard (OSM equivalent via MapKit)
struct MinimapRenderer {

    static func render(gpxPoints: [GPXPoint],
                       currentEpoch: Double,
                       outputURL: URL) async throws {
        let size = CGFloat(AppConfig.Map.mapW)  // 390

        // Determine region
        let coords = gpxPoints.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard !coords.isEmpty else { return }

        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let pad = AppConfig.Map.paddingPct

        let spanLat = (maxLat - minLat) * (1 + 2 * pad)
        let spanLon = (maxLon - minLon) * (1 + 2 * pad)
        let centre = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let region = MKCoordinateRegion(
            center: centre,
            span: MKCoordinateSpan(latitudeDelta: max(spanLat, 0.001),
                                   longitudeDelta: max(spanLon, 0.001))
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: size, height: size)
        options.mapType = .standard
        options.showsBuildings = false

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot = try await snapshotter.start()

        // Draw route and marker on the snapshot image
        let finalImage = drawOverlay(snapshot: snapshot, gpxPoints: gpxPoints,
                                     currentEpoch: currentEpoch, size: size)

        // Bottom-align on transparent square canvas (matches minimap_prerenderer.py)
        let canvas = makeTransparentCanvas(size: Int(size), image: finalImage)

        try saveImage(canvas, to: outputURL)
    }

    // MARK: - Drawing

    private static func drawOverlay(snapshot: MKMapSnapshotter.Snapshot,
                                     gpxPoints: [GPXPoint],
                                     currentEpoch: Double,
                                     size: CGFloat) -> CGImage {
#if os(macOS)
        let nsImage = snapshot.image
        guard let cgBase = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        }
#else
        let cgBase = snapshot.image.cgImage!
#endif
        let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cgBase, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Route polyline
        let routeColor = AppConfig.Map.routeColor
        ctx.setStrokeColor(CGColor(red: CGFloat(routeColor.0)/255,
                                   green: CGFloat(routeColor.1)/255,
                                   blue: CGFloat(routeColor.2)/255, alpha: 1))
        ctx.setLineWidth(CGFloat(AppConfig.Map.routeWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let path = CGMutablePath()
        for (i, pt) in gpxPoints.enumerated() {
            let screenPt = snapshot.point(for: CLLocationCoordinate2D(latitude: pt.lat, longitude: pt.lon))
            i == 0 ? path.move(to: screenPt) : path.addLine(to: screenPt)
        }
        ctx.addPath(path)
        ctx.strokePath()

        // Position marker
        let markerColor = AppConfig.Map.markerColor
        if let nearest = gpxPoints.min(by: { abs($0.epoch - currentEpoch) < abs($1.epoch - currentEpoch) }) {
            let pt = snapshot.point(for: CLLocationCoordinate2D(latitude: nearest.lat, longitude: nearest.lon))
            let r = CGFloat(AppConfig.Map.markerRadius) / 2   // radius in points (half pixel radius)
            ctx.setFillColor(CGColor(red: CGFloat(markerColor.0)/255,
                                     green: CGFloat(markerColor.1)/255,
                                     blue: CGFloat(markerColor.2)/255, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r*2, height: r*2))
        }

        return ctx.makeImage()!
    }

    private static func makeTransparentCanvas(size: Int, image: CGImage) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Clear to transparent
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        // Bottom-align
        let imgH = image.height
        let yOffset = size - imgH
        ctx.draw(image, in: CGRect(x: 0, y: yOffset, width: size, height: imgH))
        return ctx.makeImage()!
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
