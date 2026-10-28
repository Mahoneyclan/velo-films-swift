// FlattenRow.swift
// Row model for flatten.jsonl, written by FlattenStep and read by Extract and Enrich.

import Foundation

/// One row in `flatten.jsonl`: the GPX track resampled to one point per second.
/// The JSON keys match `flatten.py` in the original Python app, so files are interchangeable; they are permanent.
struct FlattenRow: Codable {
    /// Unix time of the sample, in seconds.
    var gpxEpoch: Double
    /// The same time as an ISO 8601 string.
    var gpxTimeUtc: String
    /// Latitude in degrees.
    var lat: Double
    /// Longitude in degrees.
    var lon: Double
    /// Elevation in metres.
    var elevation: Double
    /// Heart rate in beats per minute, or `nil` if the GPX has none.
    var hrBpm: Double?
    /// Pedalling cadence in rpm, or `nil` if the GPX has none.
    var cadenceRpm: Double?
    /// Speed in km/h.
    var speedKmh: Double
    /// Gradient in percent; negative is downhill.
    var gradientPct: Double

    /// JSON key names (snake_case). Permanent: existing files use them.
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
