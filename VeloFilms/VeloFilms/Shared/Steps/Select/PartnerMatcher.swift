import Foundation

/// Matches front and rear camera rows that share the same moment_id (1-second bucket).
/// Mirrors select.py dual-camera grouping logic.
struct PartnerMatcher {

    struct Moment {
        var momentId: Int
        var rows: [EnrichRow]

        var fly12Row: EnrichRow? { rows.first { $0.camera == AppConfig.CameraName.fly12Sport.rawValue } }
        var fly6Row:  EnrichRow? { rows.first { $0.camera == AppConfig.CameraName.fly6Pro.rawValue } }

        var isSingleCamera: Bool { fly12Row == nil || fly6Row == nil }

        /// Best score for this moment, with dual-camera bonus applied.
        var bestScore: Double {
            let s12 = fly12Row?.scoreWeighted ?? 0
            let s6  = fly6Row?.scoreWeighted  ?? 0
            let base = max(s12, s6)
            return isSingleCamera ? base : base + AppConfig.ScoreWeights.dualCamera
        }

        /// The primary (higher-scoring) row.
        var primary: EnrichRow? {
            guard let r12 = fly12Row, let r6 = fly6Row else {
                return fly12Row ?? fly6Row
            }
            return r12.scoreWeighted >= r6.scoreWeighted ? r12 : r6
        }

        /// The secondary (PiP) row, if available.
        var secondary: EnrichRow? {
            guard let r12 = fly12Row, let r6 = fly6Row else { return nil }
            return r12.scoreWeighted >= r6.scoreWeighted ? r6 : r12
        }
    }

    /// Group enriched rows by moment_id.
    static func group(_ rows: [EnrichRow]) -> [Moment] {
        var byMoment: [Int: [EnrichRow]] = [:]
        for row in rows {
            byMoment[row.momentId, default: []].append(row)
        }
        return byMoment.map { Moment(momentId: $0.key, rows: $0.value) }
                       .sorted { $0.momentId < $1.momentId }
    }
}
