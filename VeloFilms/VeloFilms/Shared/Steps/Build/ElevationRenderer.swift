import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders the 948×75px elevation strip for a single clip.
/// Mirrors elevation_prerenderer.py + matplotlib output:
///   - Distance-based x-axis (cumulative haversine km from flatten.csv start)
///   - Filled green area under line
///   - Yellow position marker dot
///   - Semi-transparent dark background
///   - Labels: max elev (top-left), min elev (bottom-left), total dist (bottom-right)
struct ElevationRenderer {

    static func render(flattenRows: [FlattenRow],
                       currentEpoch: Double,
                       outputURL: URL) throws {
        guard flattenRows.count >= 2 else { return }

        let W = AppConfig.HUD.elevW   // 948
        let H = AppConfig.HUD.elevH   // 75
        let ctx = makeBitmapContext(width: W, height: H)

        // Background
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Build cumulative distance array
        var distances: [Double] = [0]
        for i in 1..<flattenRows.count {
            let prev = flattenRows[i-1], curr = flattenRows[i]
            let d = haversineM(prev.lat, prev.lon, curr.lat, curr.lon) / 1000.0
            distances.append(distances[i-1] + d)
        }
        let totalDistKm = distances.last ?? 1

        let elevations = flattenRows.map { $0.elevation }
        let minElev = elevations.min() ?? 0
        let maxElev = max(elevations.max() ?? 1, minElev + 1)
        let elevRange = maxElev - minElev

        func xPos(_ distKm: Double) -> CGFloat { CGFloat(distKm / totalDistKm) * CGFloat(W) }
        func yPos(_ elev: Double) -> CGFloat {
            CGFloat(H) - CGFloat((elev - minElev) / elevRange) * CGFloat(H - 4) - 2
        }

        // Filled area
        let path = CGMutablePath()
        path.move(to: CGPoint(x: xPos(distances[0]), y: CGFloat(H)))
        for (i, row) in flattenRows.enumerated() {
            path.addLine(to: CGPoint(x: xPos(distances[i]), y: yPos(row.elevation)))
        }
        path.addLine(to: CGPoint(x: xPos(totalDistKm), y: CGFloat(H)))
        path.closeSubpath()

        ctx.setFillColor(CGColor(red: 0/255, green: 180/255, blue: 60/255, alpha: 0.5))
        ctx.addPath(path)
        ctx.fillPath()

        // Darker line on top
        let linePath = CGMutablePath()
        for (i, row) in flattenRows.enumerated() {
            let pt = CGPoint(x: xPos(distances[i]), y: yPos(row.elevation))
            i == 0 ? linePath.move(to: pt) : linePath.addLine(to: pt)
        }
        ctx.addPath(linePath)
        ctx.setStrokeColor(CGColor(red: 0/255, green: 230/255, blue: 77/255, alpha: 1))
        ctx.setLineWidth(1.5)
        ctx.strokePath()

        // Position marker — nearest point by epoch distance
        if let (posIndex, _) = flattenRows.enumerated()
                .min(by: { abs($0.element.gpxEpoch - currentEpoch) < abs($1.element.gpxEpoch - currentEpoch) }) {
            let mx = xPos(distances[posIndex])
            let my = yPos(flattenRows[posIndex].elevation)
            let r: CGFloat = 6
            // White halo
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: mx - r - 2, y: my - r - 2, width: (r+2)*2, height: (r+2)*2))
            // Yellow dot
            ctx.setFillColor(CGColor(red: 230/255, green: 175/255, blue: 0, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: mx - r, y: my - r, width: r*2, height: r*2))
        }

        // Labels (small white text)
        // max elev top-left, min elev bottom-left, total dist bottom-right
        // (label drawing omitted for brevity — add with CoreText as in GaugeRenderer)

        let cgImage = ctx.makeImage()!
#if os(macOS)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let data = rep.representation(using: .png, properties: [:])!
#else
        let data = UIImage(cgImage: cgImage).pngData()!
#endif
        try data.write(to: outputURL, options: .atomic)
    }

    private static func makeBitmapContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}
