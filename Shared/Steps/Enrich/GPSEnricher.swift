import Foundation

/// Attaches GPS telemetry to extract rows via binary search on flatten.csv epochs.
/// Mirrors gps_enricher.py: nearest-neighbour lookup within GPX_TOLERANCE.
struct GPSEnricher {
    let index: GPXIndex

    init(flattenRows: [FlattenRow]) {
        let points = flattenRows.map { row -> GPXPoint in
            GPXPoint(epoch: row.gpxEpoch, lat: row.lat, lon: row.lon,
                     elevation: row.elevation, hr: row.hrBpm, cadence: row.cadenceRpm,
                     speedKmh: row.speedKmh, gradientPct: row.gradientPct)
        }
        self.index = GPXIndex(points: points)
    }

    /// Returns the nearest GPX match for `epoch`, or nil if outside tolerance.
    func enrich(epoch: Double) -> GPXPoint? {
        index.nearest(epoch: epoch, tolerance: AppConfig.gpxTolerance)
    }
}
