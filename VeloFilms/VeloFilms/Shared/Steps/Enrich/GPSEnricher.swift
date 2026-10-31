// GPSEnricher.swift
// Looks up the GPS telemetry for a grid time, with speed and gradient averaged over the clip.

import Foundation

/// Attaches GPS telemetry to extract rows via binary search on flatten.jsonl epochs.
/// Nearest-neighbour lookup within `AppConfig.gpxTolerance` (same as `gps_enricher.py` in the original Python app).
struct GPSEnricher {
    /// The flatten points, indexed by time.
    let index: GPXIndex

    /// Builds the index. `flattenRows` must be in time order, as FlattenStep writes them.
    /// - Parameter flattenRows: The rows of `flatten.jsonl`.
    init(flattenRows: [FlattenRow]) {
        let points = flattenRows.map { row -> GPXPoint in
            GPXPoint(epoch: row.gpxEpoch, lat: row.lat, lon: row.lon,
                     elevation: row.elevation, hr: row.hrBpm, cadence: row.cadenceRpm,
                     speedKmh: row.speedKmh, gradientPct: row.gradientPct)
        }
        self.index = GPXIndex(points: points)
    }

    /// Returns the nearest GPX point for `epoch`.
    /// - Parameter epoch: Grid time in Unix seconds.
    /// - Returns: The point, or `nil` if none is within the tolerance (e.g. before the GPS started).
    func enrich(epoch: Double) -> GPXPoint? {
        index.nearest(epoch: epoch, tolerance: AppConfig.gpxTolerance)
    }

    /// Returns the nearest GPX point for `epoch`, with speed and gradient replaced by their averages over the
    /// clip `window`, so a moment is scored on the whole clip rather than one second of it.
    /// - Parameters:
    ///   - epoch: Grid time in Unix seconds; supplies position, elevation, heart rate and cadence.
    ///   - window: The clip's time span in Unix seconds.
    /// - Returns: The point, or `nil` if none is within the tolerance of `epoch`. Speed and gradient stay those
    ///   of the nearest point when no GPX point falls inside `window`.
    func enrich(epoch: Double, over window: ClosedRange<Double>) -> GPXPoint? {
        guard var point = enrich(epoch: epoch) else { return nil }
        let inWindow = index.points(in: window)
        guard !inWindow.isEmpty else { return point }
        let n = Double(inWindow.count)
        point.speedKmh    = inWindow.reduce(0) { $0 + $1.speedKmh } / n
        point.gradientPct = inWindow.reduce(0) { $0 + $1.gradientPct } / n
        return point
    }
}
