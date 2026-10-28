// GPSEnricher.swift
// Looks up the GPS telemetry nearest to a grid time.

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
}
