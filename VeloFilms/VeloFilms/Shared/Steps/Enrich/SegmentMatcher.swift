// SegmentMatcher.swift
// Matches grid times to Strava segment efforts (segments.json) and scores them.

import Foundation

/// Matches a time against Strava segment efforts and returns the segment score.
/// Scores (from `AppConfig.StravaBoost`): PR (rank 1) 1.0, rank 2–3 0.7, any other effort 0.3.
/// Same rules as `segment_matcher.py` in the original Python app.
struct SegmentMatcher {
    /// One effort from `segments.json` (written by StravaClient).
    struct SegmentEffort: Codable {
        /// Segment name.
        var name: String
        /// Effort start, ISO 8601 in true UTC.
        var startTime: String
        /// Effort duration in seconds.
        var elapsedTime: Double
        /// 1 for a personal record, 2 or 3 for second or third best; `nil` otherwise.
        var prRank: Int?
        /// Segment length in metres.
        var distance: Double?
        /// Segment average gradient in percent.
        var averageGrade: Double?

        /// JSON key names used in `segments.json`.
        enum CodingKeys: String, CodingKey {
            case name
            case startTime    = "start_time"
            case elapsedTime  = "elapsed_time"
            case prRank       = "pr_rank"
            case distance
            case averageGrade = "average_grade"
        }
    }

    private let efforts: [(startEpoch: Double, endEpoch: Double, boost: Double, effort: SegmentEffort)]

    /// Loads `segments.json`. A missing or unreadable file means no segments (all scores 0).
    /// - Parameter segmentsURL: The project's `segments.json`.
    init(segmentsURL: URL) {
        guard let data = try? Data(contentsOf: segmentsURL),
              let segments = try? JSONDecoder().decode([SegmentEffort].self, from: data) else {
            efforts = []
            return
        }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmt2 = ISO8601DateFormatter()
        fmt2.formatOptions = [.withInternetDateTime]

        efforts = segments.compactMap { seg -> (Double, Double, Double, SegmentEffort)? in
            let start = (fmt.date(from: seg.startTime) ?? fmt2.date(from: seg.startTime))
                            .map { $0.timeIntervalSince1970 }
            guard let startEpoch = start else { return nil }
            let endEpoch = startEpoch + seg.elapsedTime

            let boost: Double
            switch seg.prRank {
            case 1:       boost = AppConfig.StravaBoost.rank1
            case 2, 3:    boost = AppConfig.StravaBoost.rank2_3
            default:      boost = AppConfig.StravaBoost.any
            }
            return (startEpoch, endEpoch, boost, seg)
        }
    }

    /// Returns the highest segment score among efforts covering `epoch`, or 0 if none.
    /// - Parameter epoch: Time in the same clock as the efforts (true UTC).
    /// - Returns: A score from 0 upward (see `AppConfig.StravaBoost`).
    func boost(epoch: Double) -> Double {
        efforts
            .filter { epoch >= $0.startEpoch && epoch <= $0.endEpoch }
            .map { $0.boost }
            .max() ?? 0.0
    }

    /// Returns the highest-scoring effort covering `epoch`, or `nil`.
    /// - Parameter epoch: Time in true UTC.
    /// - Returns: The effort, or `nil` if none covers `epoch`.
    func effort(epoch: Double) -> SegmentEffort? {
        efforts
            .filter { epoch >= $0.startEpoch && epoch <= $0.endEpoch }
            .max(by: { $0.boost < $1.boost })
            .map(\.effort)
    }

    /// Whole-hour offset to add to Strava epochs (true UTC) so they align with
    /// abs_time_epoch (Cycliq local-time-as-UTC). Returns 0 if no efforts loaded.
    /// Assumes the earliest effort starts within about half an hour of the ride start.
    /// - Parameter rideStartEpoch: Ride start on the camera clock.
    /// - Returns: Offset in seconds (a multiple of 3,600).
    func stravaOffset(rideStartEpoch: Double) -> Double {
        guard rideStartEpoch > 0,
              let earliest = efforts.map(\.startEpoch).min() else { return 0 }
        return ((rideStartEpoch - earliest) / 3600).rounded() * 3600
    }
}
