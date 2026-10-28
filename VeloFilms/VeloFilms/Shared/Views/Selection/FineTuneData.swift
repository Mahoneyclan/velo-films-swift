// FineTuneData.swift
// Reads what the Fine Tune screen shows: the picks (select.jsonl), the moments worth reviewing, Strava laps and
// the elevation profile for the ride timeline.

import Foundation

/// A Strava lap placed on the ride's clock (local-time-as-UTC, like `momentId`).
struct RideLap: Equatable {
    /// Lap name from Strava, e.g. "Lap 3".
    let name: String
    /// Lap start on the ride's clock, in seconds.
    let startEpoch: Double
}

/// Everything the Fine Tune screen needs, read once when it opens.
struct FineTuneData {
    /// Every row of `select.jsonl`, one per camera frame.
    var rows: [SelectRow]
    /// Strava laps, or empty if the ride has none.
    var laps: [RideLap]
    /// Elevation evenly spaced across the ride, scaled 0 (lowest) to 1 (highest). Empty without GPS data.
    var elevation: [Double]

    /// Number of points in the elevation profile: enough for a smooth outline at iPad width, few enough to draw
    /// instantly.
    static let elevationSamples = 200

    /// Reads the project's selection, laps and track.
    /// - Parameters:
    ///   - project: The ride project.
    ///   - reader: JSONL reader (injectable for tests).
    /// - Returns: The data; laps and elevation are empty if their files are missing or unreadable.
    /// - Throws: File or decoding errors for `select.jsonl`, which the screen can't work without.
    /// - Note: Runs on the main actor; `select.jsonl` is a few MB, read once per screen.
    static func load(project: Project, reader: JSONLReader = JSONLReader()) throws -> FineTuneData {
        let rows: [SelectRow] = try reader.read(from: project.selectJSONL)
        let times = rows.map { Double($0.base.momentId) }
        let start = times.min() ?? 0, end = times.max() ?? 0

        let rawLaps = (try? Data(contentsOf: project.lapsJSON)).map { parseLaps($0) } ?? []
        let offset = lapOffset(rideStartEpoch: start, laps: rawLaps)
        let laps = rawLaps.map { RideLap(name: $0.name, startEpoch: $0.startEpoch + offset) }
            .filter { $0.startEpoch >= start && $0.startEpoch <= end }

        let flatten: [FlattenRow] = (try? reader.read(from: project.flattenJSONL)) ?? []
        let elevation = elevationProfile(flatten, from: start, to: end, samples: elevationSamples)
        return FineTuneData(rows: rows, laps: laps, elevation: elevation)
    }

    // MARK: - Moments to review

    /// The moments shown on the screen: the best `max(2 × target, picks + 20)` by score, the best moment of every
    /// camera file (so no part of the ride is missing), and the moments just before and after each pick (to compare
    /// and swap).
    /// - Parameters:
    ///   - moments: All moments of the ride.
    ///   - recommendedIds: Moments currently in the reel.
    ///   - target: Clips wanted.
    /// - Returns: The moments to show, in time order.
    static func reviewPool(_ moments: [PartnerMatcher.Moment], recommendedIds: Set<Int>,
                           target: Int) -> [PartnerMatcher.Moment] {
        let sorted = moments.sorted { $0.momentId < $1.momentId }
        let limit = max(target * 2, recommendedIds.count + 20)
        var keep = Set(sorted.sorted { $0.bestScore > $1.bestScore }.prefix(limit).map(\.momentId))
        keep.formUnion(recommendedIds)

        var bestPerFile: [Int: PartnerMatcher.Moment] = [:]
        for m in sorted {
            // Both cameras' rows of a moment count as one file: the lower clip number, as ClipSelector did.
            let key = [m.fly12Row?.clipNum, m.fly6Row?.clipNum].compactMap { $0 }.min() ?? 0
            if (bestPerFile[key]?.bestScore ?? -1) < m.bestScore { bestPerFile[key] = m }
        }
        keep.formUnion(bestPerFile.values.map(\.momentId))

        for (i, m) in sorted.enumerated() where recommendedIds.contains(m.momentId) {
            if i > 0 { keep.insert(sorted[i - 1].momentId) }
            if i < sorted.count - 1 { keep.insert(sorted[i + 1].momentId) }
        }
        return sorted.filter { keep.contains($0.momentId) }
    }

    // MARK: - Laps

    /// Strava `laps.json` entry.
    private struct LapRecord: Decodable {
        let name: String
        let startDate: String
        enum CodingKeys: String, CodingKey {
            case name
            case startDate = "start_date"
        }
    }

    /// Parses Strava laps.
    /// - Parameter data: Contents of `laps.json`.
    /// - Returns: Lap names and start times in true UTC; empty if the data isn't a lap list.
    static func parseLaps(_ data: Data) -> [RideLap] {
        guard let laps = try? JSONDecoder().decode([LapRecord].self, from: data) else { return [] }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return laps.compactMap { lap in
            guard let date = withFraction.date(from: lap.startDate) ?? plain.date(from: lap.startDate) else {
                return nil
            }
            return RideLap(name: lap.name, startEpoch: date.timeIntervalSince1970)
        }
    }

    /// Seconds to add to Strava lap times (true UTC) so they line up with the ride's clock, which Cycliq records as
    /// local time labelled UTC. Rounded to whole hours to absorb the gap between pressing record and the first lap.
    /// - Parameters:
    ///   - rideStartEpoch: First moment of the ride.
    ///   - laps: Laps in true UTC.
    /// - Returns: The offset in seconds, or 0 without laps.
    static func lapOffset(rideStartEpoch: Double, laps: [RideLap]) -> Double {
        guard rideStartEpoch > 0, let earliest = laps.map(\.startEpoch).min() else { return 0 }
        return ((rideStartEpoch - earliest) / 3600).rounded() * 3600
    }

    // MARK: - Elevation

    /// Elevation across [start, end] in `samples` evenly spaced points, scaled 0…1. Each point is the track point
    /// nearest in time, so stops and camera gaps keep their place on the timeline.
    /// - Parameters:
    ///   - track: Track points (any order).
    ///   - start: Ride start, seconds.
    ///   - end: Ride end, seconds.
    ///   - samples: Points wanted.
    /// - Returns: The profile, or empty if the track is empty or the ride has no length.
    static func elevationProfile(_ track: [FlattenRow], from start: Double, to end: Double,
                                 samples: Int) -> [Double] {
        let points = track.sorted { $0.gpxEpoch < $1.gpxEpoch }
        guard !points.isEmpty, end > start, samples > 1 else { return [] }
        var raw: [Double] = []
        var j = 0
        for i in 0..<samples {
            let t = start + (end - start) * Double(i) / Double(samples - 1)
            while j + 1 < points.count, abs(points[j + 1].gpxEpoch - t) <= abs(points[j].gpxEpoch - t) { j += 1 }
            raw.append(points[j].elevation)
        }
        guard let lo = raw.min(), let hi = raw.max(), hi > lo else { return raw.map { _ in 0 } }
        return raw.map { ($0 - lo) / (hi - lo) }
    }
}
