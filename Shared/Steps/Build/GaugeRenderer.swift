import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders the 5-cell gauge strip as a PNG (static) or a series of PNGs for ProRes compilation.
/// Mirrors gauge_prerenderer.py + draw_gauge.py.
///
/// Strip layout (L→R): elev | gradient | speed | hr | cadence
/// Each cell: 194×194px. Total strip: 972×194px.
struct GaugeRenderer {

    struct GaugeTelemetry {
        var elevM: Double?
        var gradientPct: Double?
        var speedKmh: Double?
        var hrBpm: Double?
        var cadenceRpm: Double?
    }

    /// Render a single 972×194 gauge strip PNG for a given telemetry snapshot.
    static func renderStrip(telemetry: GaugeTelemetry, outputURL: URL) throws {
        let W = AppConfig.HUD.gaugeCompositeW   // 972
        let H = AppConfig.HUD.gaugeCompositeH   // 194
        let cellW = AppConfig.HUD.gaugeCellSize // 194

        let ctx = makeBitmapContext(width: W, height: H)

        // Draw 5 cells in order: elev, gradient, speed, hr, cadence
        let cells: [(label: String, value: Double?, minVal: Double, maxVal: Double, unit: String)] = [
            ("ELEV",     telemetry.elevM,       0,   2000,  "m"),
            ("GRAD",     telemetry.gradientPct, -20, 20,    "%"),
            ("SPEED",    telemetry.speedKmh,    0,   60,    "km/h"),
            ("HR",       telemetry.hrBpm,       60,  180,   "bpm"),
            ("CADENCE",  telemetry.cadenceRpm,  0,   120,   "rpm"),
        ]

        for (i, cell) in cells.enumerated() {
            let x = CGFloat(i * cellW)
            let cellRect = CGRect(x: x, y: 0, width: CGFloat(cellW), height: CGFloat(H))
            drawGaugeCell(in: ctx, rect: cellRect,
                          value: cell.value, minVal: cell.minVal, maxVal: cell.maxVal,
                          label: cell.label, unit: cell.unit)
        }

        try saveContext(ctx, width: W, height: H, to: outputURL)
    }

    // MARK: - Single gauge cell (arc + text)

    /// Arc geometry — mirrors draw_gauge.py.
    ///
    /// PIL uses clockwise angles from 3-o'clock:
    ///   ARC_START=150° → CoreGraphics (anti-clockwise from 3-o'clock) = -(150°) = 210° = 7π/6
    ///   ARC_END=390°   → CG = -(390°) + 360° = -30° = -π/6
    ///
    /// In CG: startAngle = -150° * π/180 (note: CG y-axis is flipped in CGContext, so
    /// we use the raw angle values — callers pass already-converted radians).
    static func drawGaugeCell(in ctx: CGContext,
                               rect: CGRect,
                               value: Double?,
                               minVal: Double, maxVal: Double,
                               label: String, unit: String) {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.38
        let lineW: CGFloat = 8

        // Background circle
        let bg = AppConfig.GaugeArc.bg
        ctx.setFillColor(cgColor(bg))
        ctx.fillEllipse(in: rect.insetBy(dx: 4, dy: 4))

        // Arc angles (PIL clockwise from 3-o'clock → CG anti-clockwise from 3-o'clock)
        // PIL 150° → CG: start at -(150-90)° from 12-o'clock... simplest mapping:
        // CG startAngle = π - 150° in radians (PIL angle measured from East, CW)
        // After coordinate flip in drawingFlipped context: use directly as negative radians from E.
        let arcStartRad = CGFloat((-210.0) * .pi / 180)  // CG equivalent of PIL 150°
        let arcSpanRad  = CGFloat((-240.0) * .pi / 180)  // 240° span, CCW

        // Dim (unfilled) arc
        ctx.setStrokeColor(cgColor(AppConfig.GaugeArc.dim))
        ctx.setLineWidth(lineW)
        ctx.addArc(center: centre, radius: radius,
                   startAngle: arcStartRad,
                   endAngle: arcStartRad + arcSpanRad,
                   clockwise: false)
        ctx.strokePath()

        // Filled green arc (proportional to value)
        if let v = value {
            let fraction = CGFloat(max(0, min(1, (v - minVal) / (maxVal - minVal))))
            let fillSpan = arcSpanRad * fraction
            ctx.setStrokeColor(cgColor(AppConfig.GaugeArc.green))
            ctx.setLineWidth(lineW)
            ctx.addArc(center: centre, radius: radius,
                       startAngle: arcStartRad,
                       endAngle: arcStartRad + fillSpan,
                       clockwise: false)
            ctx.strokePath()
        }

        // Value text
        let valueStr = value.map { formatValue($0, label: label) } ?? "--"
        drawCentredText(valueStr, in: ctx, centredAt: centre,
                        fontSize: radius * 0.55, color: cgColor(AppConfig.GaugeArc.white))

        // Unit text
        let unitOrigin = CGPoint(x: centre.x, y: centre.y + radius * 0.65)
        drawCentredText(unit, in: ctx, centredAt: unitOrigin,
                        fontSize: radius * 0.28, color: cgColor(AppConfig.GaugeArc.white))

        // Label in gap (below arc)
        let labelOrigin = CGPoint(x: centre.x, y: rect.maxY - radius * 0.3)
        drawCentredText(label, in: ctx, centredAt: labelOrigin,
                        fontSize: radius * 0.25, color: cgColor(AppConfig.GaugeArc.white))
    }

    // MARK: - Helpers

    private static func formatValue(_ v: Double, label: String) -> String {
        switch label {
        case "GRAD": return String(format: "%.1f", v)
        case "SPEED": return String(format: "%.0f", v)
        default: return String(format: "%.0f", v)
        }
    }

    private static func cgColor(_ tuple: (Int, Int, Int, Int)) -> CGColor {
        CGColor(red: CGFloat(tuple.0)/255, green: CGFloat(tuple.1)/255,
                blue: CGFloat(tuple.2)/255, alpha: CGFloat(tuple.3)/255)
    }

    private static func makeBitmapContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private static func drawCentredText(_ text: String, in ctx: CGContext,
                                         centredAt point: CGPoint,
                                         fontSize: CGFloat, color: CGColor) {
        // Use CoreText for platform-portable text rendering
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("SFNS-Regular" as CFString, fontSize, nil),
            kCTForegroundColorAttributeName: color
        ]
        let attrStr = CFAttributedStringCreate(nil, text as CFString,
                                               attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: point.x - bounds.width / 2 - bounds.minX,
                                   y: point.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    private static func saveContext(_ ctx: CGContext, width: Int, height: Int, to url: URL) throws {
        guard let cgImage = ctx.makeImage() else {
            throw PipelineError.missingInput("GaugeRenderer: failed to make CGImage")
        }
#if os(macOS)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw PipelineError.missingInput("GaugeRenderer: PNG encoding failed")
        }
#else
        guard let data = UIImage(cgImage: cgImage).pngData() else {
            throw PipelineError.missingInput("GaugeRenderer: PNG encoding failed")
        }
#endif
        try data.write(to: url, options: .atomic)
    }
}
