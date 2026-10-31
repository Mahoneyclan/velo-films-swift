// ClipWindowScorer.swift
// Scores a whole clip from several frames and finds the clip start with the most action. Pure rules, no video.

import Foundation

/// Scores the frames around a shortlisted moment and chooses where its clip should start.
///
/// Times are seconds relative to the clip's default start (the moment minus the pre-roll). The clip may slide
/// within `shiftRange`; for each candidate start the frames inside the clip are scored together, so a moment is
/// judged on its whole clip rather than its first frame. Used by `ClipRefiner`.
enum ClipWindowScorer {

    /// What YOLO found in one frame.
    struct Frame: Equatable {
        /// Seconds after the clip's default start (negative is before it).
        var offset: Double
        /// Highest (confidence × class weight) in the frame, 0–1 (`YOLODetector.detect`).
        var detectScore: Double
        /// Summed (box area × class weight) in the frame, 0–1 (`YOLODetector.detect`).
        var presence: Double
    }

    /// The chosen clip and its scores.
    struct Result: Equatable {
        /// Seconds to move the clip start (negative is earlier).
        var shift: Double
        /// Mean of the two best frame detection scores inside the clip.
        var detectScore: Double
        /// How much objects grew or shrank in view during the clip, 0–1.
        var actionScore: Double
        /// Offset of the frame to show as the moment's thumbnail (the strongest detection in the clip).
        var thumbnailOffset: Double
    }

    /// Chooses the clip start and scores the clip.
    /// - Parameters:
    ///   - frames: Frames around the moment, any order. Offsets outside every candidate clip are ignored.
    ///   - clipLength: Output clip length in seconds.
    ///   - shiftRange: Allowed shifts of the clip start; the caller limits it to the video files.
    ///   - detectWeight: Weight of the detection score, so the choice matches the composite score.
    ///   - actionWeight: Weight of the action score.
    /// - Returns: The best clip, or `nil` if no candidate clip contains a frame.
    static func best(frames: [Frame], clipLength: Double, shiftRange: ClosedRange<Double>,
                     detectWeight: Double, actionWeight: Double) -> Result? {
        // Candidate starts: no shift, plus every frame inside the allowed range, so each clip begins on a frame.
        let candidates = ([0] + frames.map(\.offset)).filter { shiftRange.contains($0) }
        var best: (value: Double, result: Result)?
        for shift in Set(candidates) {
            guard let result = score(frames: frames, shift: shift, clipLength: clipLength) else { continue }
            let value = result.detectScore * detectWeight + result.actionScore * actionWeight
            // On a tie, the smaller shift wins so the clip stays close to the sampled moment.
            if let b = best, value < b.value || (value == b.value && abs(shift) >= abs(b.result.shift)) {
                continue
            }
            best = (value, result)
        }
        return best?.result
    }

    /// Scores the clip that starts `shift` seconds after the default start.
    /// - Parameters:
    ///   - frames: Frames around the moment.
    ///   - shift: Clip start relative to the default start.
    ///   - clipLength: Clip length in seconds.
    /// - Returns: The scores, or `nil` if no frame falls inside the clip.
    static func score(frames: [Frame], shift: Double, clipLength: Double) -> Result? {
        // A small tolerance keeps a frame exactly at the clip's end (e.g. the next grid point) inside it.
        let inside = frames.filter { $0.offset >= shift - 0.01 && $0.offset <= shift + clipLength + 0.01 }
        guard let strongest = inside.max(by: { $0.detectScore < $1.detectScore }) else { return nil }
        // Mean of the two best frames: one stray detection can't carry the clip, one missed frame can't sink it.
        let top = inside.map(\.detectScore).sorted(by: >).prefix(2)
        let detect = top.reduce(0, +) / Double(top.count)
        let presences = inside.map(\.presence)
        let change = (presences.max() ?? 0) - (presences.min() ?? 0)
        let action = min(1, max(0, change - AppConfig.actionNoiseArea) / AppConfig.actionFullScaleArea)
        return Result(shift: shift, detectScore: detect, actionScore: action, thumbnailOffset: strongest.offset)
    }

    /// Offsets at which to read frames for a moment: from the earliest shift to the end of the latest clip, at
    /// most `AppConfig.refineMaxFrames` frames and never closer than 1 s apart.
    /// - Parameters:
    ///   - clipLength: Clip length in seconds.
    ///   - maxShift: Largest shift either way.
    /// - Returns: Offsets in time order.
    static func sampleOffsets(clipLength: Double, maxShift: Double) -> [Double] {
        let span = clipLength + 2 * maxShift
        let step = max(1, span / Double(max(1, AppConfig.refineMaxFrames - 1)))
        return Array(stride(from: -maxShift, through: clipLength + maxShift + 0.001, by: step))
    }
}
