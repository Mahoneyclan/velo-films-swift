// GaugeRenderer.swift
// Draws the strip of five round gauges (elevation, gradient, speed, heart rate, cadence) for each clip.

import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders the 5-cell gauge strip: one image per second of clip, so the needles move during the clip.
/// macOS feeds the PNGs to FFmpeg as an image sequence; iOS loads them into the video compositor.
/// Based on `gauge_prerenderer.py` and `draw_gauge.py` in the original Python app.
///
/// Strip layout (L→R): elev | gradient | speed | hr | cadence
/// Each cell: 194×194px. Total strip: 972×194px.
struct GaugeRenderer {

    /// Values for one frame; `nil` shows the gauge without a reading.
    struct GaugeTelemetry {
        /// Elevation in metres.
        var elevM: Double?
        /// Gradient in percent.
        var gradientPct: Double?
        /// Speed in km/h.
        var speedKmh: Double?
        /// Heart rate in bpm.
        var hrBpm: Double?
        /// Cadence in rpm.
        var cadenceRpm: Double?
    }

    /// Renders per-second gauge frames as images held in memory. Not currently used (see `writeFramesToDisk`).
    /// - Parameters:
    ///   - flattenRows: The whole ride at 1 Hz.
    ///   - clipEpoch: Time of the first frame.
    /// - Returns: `ceil(clipOutLenS) + 1` frames.
    /// - Throws: `PipelineError.renderFailed` if drawing fails.
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

    /// Write per-second gauge frames to a temp directory as PNGs for FFmpeg input.
    /// Returns the directory URL; files are named gauge_0001.png, gauge_0002.png, …
    /// The caller is responsible for deleting the directory after FFmpeg finishes.
    /// - Parameters:
    ///   - flattenRows: The whole ride at 1 Hz.
    ///   - clipEpoch: Time of the first frame.
    ///   - clipIndex: Used in the folder name (`vf_gauge_N` in the temporary folder); an existing folder is replaced.
    /// - Returns: The folder holding `ceil(clipOutLenS) + 1` frames.
    /// - Throws: `PipelineError.renderFailed` or file errors.
    static func writeFramesToDisk(
        flattenRows: [FlattenRow],
        clipEpoch: Double,
        clipIndex: Int
    ) throws -> URL {
        let numFrames = Int(ceil(AppConfig.clipOutLenS)) + 1
        let ranges = computeRanges(flattenRows: flattenRows)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "vf_gauge_\(clipIndex)")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for sec in 0..<numFrames {
            let telem = lookupTelemetry(flattenRows: flattenRows, epoch: clipEpoch + Double(sec))
            let image = try renderStripImage(telemetry: telem, ranges: ranges)
            let fileURL = dir.appending(path: String(format: "gauge_%04d.png", sec + 1))
            try writePNG(image, to: fileURL)
        }
        return dir
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
#if os(macOS)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw PipelineError.renderFailed("Failed to encode gauge PNG")
        }
        try data.write(to: url)
#else
        guard let data = UIImage(cgImage: image).pngData() else {
            throw PipelineError.renderFailed("Failed to encode gauge PNG")
        }
        try data.write(to: url)
#endif
    }

    /// Renders a single gauge strip frame (no file I/O).
    /// - Parameters:
    ///   - telemetry: The values to show.
    ///   - ranges: Scale of each gauge.
    /// - Returns: A `gaugeCompositeW` × `gaugeCompositeH` image.
    /// - Throws: `PipelineError.renderFailed` if the drawing context can't be created.
    static func renderStripImage(telemetry: GaugeTelemetry,
                                  ranges: GaugeRanges = GaugeRanges()) throws -> CGImage {
        let W = AppConfig.HUD.gaugeCompositeW
        let H = AppConfig.HUD.gaugeCompositeH
        let cellW = AppConfig.HUD.gaugeCellSize
        let ctx = try makeBitmapContext(width: W, height: H)

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

    /// Minimum and maximum of each gauge's scale. Defaults are used for a ride with no data.
    struct GaugeRanges {
        /// Speed scale, km/h.
        var speedMin: Double = 0;    var speedMax: Double = 60
        /// Cadence scale, rpm.
        var cadenceMin: Double = 0;  var cadenceMax: Double = 120
        /// Heart-rate scale, bpm.
        var hrMin: Double = 40;      var hrMax: Double = 160
        /// Elevation scale, m.
        var elevMin: Double = 0;     var elevMax: Double = 2000
        /// Gradient scale, %, symmetric around 0.
        var gradMin: Double = -20;   var gradMax: Double = 20
    }

    /// Fits each gauge's scale to the ride's values with about 10% headroom, so the needles use the full arc.
    /// - Parameter flattenRows: The whole ride.
    /// - Returns: The ranges; gradient is made symmetric so 0% is at the top.
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

    // MARK: - Telemetry lookup (nearest epoch within 2s, O(log n))

    private static func lookupTelemetry(flattenRows: [FlattenRow], epoch: Double) -> GaugeTelemetry {
        guard !flattenRows.isEmpty else { return GaugeTelemetry() }
        guard let nearest = binarySearchNearest(flattenRows, epoch: epoch),
              abs(nearest.gpxEpoch - epoch) <= 2.0 else { return GaugeTelemetry() }
        return GaugeTelemetry(
            elevM: nearest.elevation,
            gradientPct: nearest.gradientPct,
            speedKmh: nearest.speedKmh,
            hrBpm: nearest.hrBpm,
            cadenceRpm: nearest.cadenceRpm
        )
    }

    private static func binarySearchNearest(_ rows: [FlattenRow], epoch: Double) -> FlattenRow? {
        var lo = 0, hi = rows.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if rows[mid].gpxEpoch < epoch { lo = mid + 1 } else { hi = mid }
        }
        var best: FlattenRow? = nil
        var bestDiff = Double.infinity
        for idx in [lo - 1, lo, lo + 1] {
            guard (0..<rows.count).contains(idx) else { continue }
            let diff = abs(rows[idx].gpxEpoch - epoch)
            if diff < bestDiff { bestDiff = diff; best = rows[idx] }
        }
        return best
    }

    // MARK: - Single gauge cell

    /// Draws one round gauge: dark disc, dim full arc, green arc for the value, value text, unit and label.
    ///
    /// Arc geometry matches `draw_gauge.py`: a 240° arc from 150° to 390° in PIL's convention (0° = 3 o'clock,
    /// clockwise). Core Graphics measures counter-clockwise, so each PIL angle p becomes -p and the arc is drawn
    /// with `clockwise: true` from -150° to -390°.
    /// - Parameters:
    ///   - ctx: The strip's drawing context.
    ///   - rect: The cell to draw in.
    ///   - value: The reading, or `nil` to show "--" with an empty arc.
    ///   - minVal: Value at the start of the arc.
    ///   - maxVal: Value at the end of the arc (values outside the range are clamped).
    ///   - label: Name under the gauge, e.g. "SPEED".
    ///   - unit: Unit under the value, e.g. "km/h".
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

    private static func makeBitmapContext(width: Int, height: Int) throws -> CGContext {
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PipelineError.renderFailed("GaugeRenderer: CGContext creation failed")
        }
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

}
