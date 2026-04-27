import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders the 5-cell gauge strip.
/// Dynamic mode: one PNG per second of clip duration, compiled to ProRes 4444 .mov via FFmpeg.
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

    /// Render per-second gauge frames as CGImages held in memory.
    /// The compositor selects the frame for each video frame by elapsed second.
    static func renderFrames(
        flattenRows: [FlattenRow],
        clipEpoch: Double
    ) throws -> [CGImage] {
        let numFrames = Int(ceil(AppConfig.clipOutLenS)) + 1
        let ranges = computeRanges(flattenRows: flattenRows)
        return try (0..<numFrames).map { sec in
            let telem = lookupTelemetry(flattenRows: flattenRows, epoch: clipEpoch + Double(sec))
            return try renderStripImage(telemetry: telem, ranges: ranges)
        }
    }

    /// Render a single gauge strip frame to a CGImage (no file I/O).
    static func renderStripImage(telemetry: GaugeTelemetry,
                                  ranges: GaugeRanges = GaugeRanges()) throws -> CGImage {
        let W = AppConfig.HUD.gaugeCompositeW
        let H = AppConfig.HUD.gaugeCompositeH
        let cellW = AppConfig.HUD.gaugeCellSize
        let ctx = makeBitmapContext(width: W, height: H)

        let cells: [(label: String, value: Double?, minVal: Double, maxVal: Double, unit: String)] = [
            ("ELEVATION", telemetry.elevM,       ranges.elevMin,    ranges.elevMax,    "m"),
            ("GRADIENT",  telemetry.gradientPct, ranges.gradMin,    ranges.gradMax,    "%"),
            ("SPEED",     telemetry.speedKmh,    ranges.speedMin,   ranges.speedMax,   "km/h"),
            ("HR",        telemetry.hrBpm,       ranges.hrMin,      ranges.hrMax,      "bpm"),
            ("CADENCE",   telemetry.cadenceRpm,  ranges.cadenceMin, ranges.cadenceMax, "rpm"),
        ]
        for (i, cell) in cells.enumerated() {
            drawGaugeCell(in: ctx,
                          rect: CGRect(x: CGFloat(i * cellW), y: 0,
                                       width: CGFloat(cellW), height: CGFloat(H)),
                          value: cell.value, minVal: cell.minVal, maxVal: cell.maxVal,
                          label: cell.label, unit: cell.unit)
        }
        guard let image = ctx.makeImage() else {
            throw PipelineError.renderFailed("GaugeRenderer: CGImage creation failed")
        }
        return image
    }

    // MARK: - Single strip frame

    // MARK: - Gauge ranges (data-driven, ±10% buffer — mirrors compute_gauge_ranges)

    struct GaugeRanges {
        var speedMin: Double = 0;    var speedMax: Double = 60
        var cadenceMin: Double = 0;  var cadenceMax: Double = 120
        var hrMin: Double = 40;      var hrMax: Double = 160
        var elevMin: Double = 0;     var elevMax: Double = 2000
        var gradMin: Double = -20;   var gradMax: Double = 20
    }

    static func computeRanges(flattenRows: [FlattenRow]) -> GaugeRanges {
        guard !flattenRows.isEmpty else { return GaugeRanges() }

        var speedVals: [Double] = [], cadVals: [Double] = [], hrVals: [Double] = []
        var elevVals: [Double] = [], gradVals: [Double] = []

        for r in flattenRows {
            speedVals.append(r.speedKmh)
            if let v = r.cadenceRpm { cadVals.append(v) }
            if let v = r.hrBpm     { hrVals.append(v) }
            elevVals.append(r.elevation)
            gradVals.append(r.gradientPct)
        }

        func range(_ vals: [Double], floorMin: Double? = nil) -> (Double, Double) {
            guard !vals.isEmpty, let lo = vals.min(), let hi = vals.max() else { return (0, 100) }
            let dMin = lo >= 0 ? lo * 0.9 : lo * 1.1
            let dMax = hi >= 0 ? hi * 1.1 : hi * 0.9
            return (floorMin.map { max($0, dMin) } ?? dMin, dMax)
        }

        let (sMin, sMax) = range(speedVals, floorMin: 0)
        let (cMin, cMax) = range(cadVals, floorMin: 0)
        let (hMin, hMax) = range(hrVals)
        let (eMin, eMax) = range(elevVals)
        let (_, gMax) = range(gradVals)
        let gBound = max(abs(gradVals.min() ?? 0) * 1.1, gMax)

        var r = GaugeRanges()
        r.speedMin = sMin;   r.speedMax = sMax
        r.cadenceMin = cMin; r.cadenceMax = cMax
        r.hrMin = hMin;      r.hrMax = hMax
        r.elevMin = eMin;    r.elevMax = eMax
        r.gradMin = -gBound; r.gradMax = gBound
        return r
    }

    // MARK: - Telemetry lookup (nearest epoch within 2s)

    private static func lookupTelemetry(flattenRows: [FlattenRow], epoch: Double) -> GaugeTelemetry {
        guard !flattenRows.isEmpty else { return GaugeTelemetry() }
        guard let nearest = flattenRows.min(by: { abs($0.gpxEpoch - epoch) < abs($1.gpxEpoch - epoch) }),
              abs(nearest.gpxEpoch - epoch) <= 2.0 else { return GaugeTelemetry() }
        return GaugeTelemetry(
            elevM: nearest.elevation,
            gradientPct: nearest.gradientPct,
            speedKmh: nearest.speedKmh,
            hrBpm: nearest.hrBpm,
            cadenceRpm: nearest.cadenceRpm
        )
    }

    // MARK: - Single gauge cell

    /// Arc geometry matches draw_gauge.py:
    ///   PIL 150° → CG: PIL is CW from 3-o'clock; CG is CCW from 3-o'clock.
    ///   PIL 150° (CW from E) = 180° - 150° + 180° offset... simplest: negate and convert.
    ///   PIL start=150° → CG start = -(150° - 180°) = 30° ... actually:
    ///   PIL 0°=E CW → CG 0°=E CCW. To convert PIL angle p to CG: CG = -p (in radians).
    ///   PIL start=150° → CG = -150° * π/180
    ///   PIL end=390°   → CG = -390° * π/180 (= -30° after mod, i.e. -π/6)
    ///   Sweep: CG draws from startAngle to endAngle in the clockwise=false (CCW) direction.
    ///   But PIL sweeps CW, so we need clockwise=true in CG with start=-150° end=-390°.
    static func drawGaugeCell(in ctx: CGContext,
                               rect: CGRect,
                               value: Double?,
                               minVal: Double, maxVal: Double,
                               label: String, unit: String) {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let gaugeSize = min(rect.width, rect.height)
        let pad: CGFloat = 6 * gaugeSize / 160
        let radius = gaugeSize / 2 - pad
        let lineW: CGFloat = max(6, 10 * gaugeSize / 160)

        // Dark background circle
        let bgR = radius + lineW / 2 + 1
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 100.0/255.0))
        ctx.fillEllipse(in: CGRect(x: centre.x - bgR, y: centre.y - bgR,
                                   width: bgR * 2, height: bgR * 2))

        // Arc angles: PIL 150°→390° CW becomes CG -150°→-390° clockwise=true
        let startAngle = CGFloat(-150.0 * .pi / 180.0)
        let endAngle   = CGFloat(-390.0 * .pi / 180.0)

        // Dim arc (full span)
        ctx.setStrokeColor(CGColor(red: 0/255, green: 55/255, blue: 22/255, alpha: 1))
        ctx.setLineWidth(lineW)
        ctx.addArc(center: centre, radius: radius,
                   startAngle: startAngle, endAngle: endAngle, clockwise: true)
        ctx.strokePath()

        // Green filled arc (proportional)
        if let v = value {
            let span = maxVal - minVal
            let frac = span != 0 ? max(0, min(1, (v - minVal) / span)) : 0
            if frac > 0 {
                // Span is 240°; fill frac * 240° clockwise from start
                let fillEnd = startAngle - CGFloat(frac * 240.0 * .pi / 180.0)
                ctx.setStrokeColor(CGColor(red: 0/255, green: 230/255, blue: 77/255, alpha: 1))
                ctx.setLineWidth(lineW)
                ctx.addArc(center: centre, radius: radius,
                           startAngle: startAngle, endAngle: fillEnd, clockwise: true)
                ctx.strokePath()
            }
        }

        // Value text — nudged slightly above centre
        let nudge = 8 * gaugeSize / 160
        let valueStr = value.map { formatValue($0, label: label) } ?? "--"
        let valFontSize = 44 * gaugeSize / 160
        let valCentre = CGPoint(x: centre.x, y: centre.y + nudge)
        drawCentredText(valueStr, in: ctx, centredAt: valCentre,
                        fontSize: valFontSize,
                        color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        // Unit and label share the same font size; increase gap between all three elements
        let subFontSize = 17 * gaugeSize / 160
        let gap = 18 * gaugeSize / 160
        let valH = valFontSize * 1.2
        let unitCentre = CGPoint(x: centre.x, y: valCentre.y - valH - gap)
        drawCentredText(unit, in: ctx, centredAt: unitCentre,
                        fontSize: subFontSize,
                        color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        // Label — in the open gap at the bottom of the arc
        let titleFontSize = subFontSize
        let titleY = centre.y - (radius * 0.5 + lineW / 2 + 6 * gaugeSize / 160)
        let titleCentre = CGPoint(x: centre.x, y: titleY)
        drawCentredText(label, in: ctx, centredAt: titleCentre,
                        fontSize: titleFontSize,
                        color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    }

    // MARK: - Helpers

    private static func formatValue(_ v: Double, label: String) -> String {
        label == "GRADIENT" ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }

    private static func makeBitmapContext(width: Int, height: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Start fully transparent
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    private static func drawCentredText(_ text: String, in ctx: CGContext,
                                         centredAt point: CGPoint,
                                         fontSize: CGFloat, color: CGColor) {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("SFNS-Regular" as CFString, fontSize, nil),
            kCTForegroundColorAttributeName: color
        ]
        let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: point.x - bounds.width / 2 - bounds.minX,
                                   y: point.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    private static func saveContext(_ ctx: CGContext, to url: URL) throws {
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
