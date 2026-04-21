import Foundation

/// One row in flatten.csv — 1-second telemetry sample.
/// Mirrors flatten.py output schema exactly.
struct FlattenRow: Codable {
    var gpxEpoch: Double        // Unix timestamp (seconds)
    var gpxTimeUtc: String      // ISO8601 string
    var lat: Double
    var lon: Double
    var elevation: Double       // metres
    var hrBpm: Double?          // nil if no HR in GPX
    var cadenceRpm: Double?     // nil if no cadence in GPX
    var speedKmh: Double
    var gradientPct: Double

    enum CodingKeys: String, CodingKey {
        case gpxEpoch    = "gpx_epoch"
        case gpxTimeUtc  = "gpx_time_utc"
        case lat, lon, elevation
        case hrBpm       = "hr_bpm"
        case cadenceRpm  = "cadence_rpm"
        case speedKmh    = "speed_kmh"
        case gradientPct = "gradient_pct"
    }
}
