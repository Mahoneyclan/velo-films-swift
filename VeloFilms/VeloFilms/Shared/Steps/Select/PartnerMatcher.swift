// PartnerMatcher.swift
// Groups front and rear camera rows that were filmed at the same moment.

import Foundation

/// Matches front and rear camera rows that share the same moment_id (1-second bucket).
/// Same dual-camera grouping as `select.py` in the original Python app.
struct PartnerMatcher {

    /// One point in time with the rows from whichever cameras filmed it.
    struct Moment {
        /// Grid time rounded to whole seconds.
        var momentId: Int
        /// The rows at this time, one per camera.
        var rows: [EnrichRow]

        /// The Fly12 Sport (front) row, if any.
        var fly12Row: EnrichRow? { rows.first { $0.camera == AppConfig.CameraName.fly12Sport.rawValue } }
        /// The Fly6 Pro (rear) row, if any.
        var fly6Row:  EnrichRow? { rows.first { $0.camera == AppConfig.CameraName.fly6Pro.rawValue } }

        /// `true` if only one camera has a row.
        var isSingleCamera: Bool { fly12Row == nil || fly6Row == nil }

        /// Best score for this moment, with dual-camera bonus applied.
        var bestScore: Double {
            let s12 = fly12Row?.scoreWeighted ?? 0
            let s6  = fly6Row?.scoreWeighted  ?? 0
            let base = max(s12, s6)
            return isSingleCamera ? base : base + AppConfig.ScoreWeights.dualCamera
        }

        /// The primary (higher-scoring) row; the front camera wins a tie.
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

    /// Groups enriched rows by `momentId`.
    /// - Parameter rows: Rows from both cameras.
    /// - Returns: One moment per distinct `momentId`, in time order.
    static func group(_ rows: [EnrichRow]) -> [Moment] {
        var byMoment: [Int: [EnrichRow]] = [:]
        for row in rows {
            byMoment[row.momentId, default: []].append(row)
        }
        return byMoment.map { Moment(momentId: $0.key, rows: $0.value) }
                       .sorted { $0.momentId < $1.momentId }
    }
}
