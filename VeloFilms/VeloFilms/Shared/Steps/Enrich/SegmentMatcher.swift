import Foundation

/// Matches a frame epoch against Strava segment efforts and returns the boost value.
/// Mirrors segment_matcher.py: pr_rank=1 → 1.0, rank 2-3 → 0.7, any segment → 0.3.
struct SegmentMatcher {
    struct SegmentEffort: Codable {
        var name: String
        var startTime: String    // ISO8601
        var elapsedTime: Double  // seconds
        var prRank: Int?
        var distance: Double?
        var averageGrade: Double?

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

    /// Returns the highest applicable boost for a given epoch, or 0 if no match.
    func boost(epoch: Double) -> Double {
        efforts
            .filter { epoch >= $0.startEpoch && epoch <= $0.endEpoch }
            .map { $0.boost }
            .max() ?? 0.0
    }
}
