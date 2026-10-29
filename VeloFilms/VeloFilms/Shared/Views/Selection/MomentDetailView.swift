// MomentDetailView.swift
// The open moment on the Fine Tune screen: its front and rear frames (tap one to use it), its time and pick status,
// the "Why this moment" lines, and the bottom controls (previous, add/remove, next).

import SwiftUI

/// The open moment's camera frames, front and rear together, under its time and pick status. Tapping a frame
/// puts that camera's clip in the reel (or takes the moment out if it is already the one in the reel).
struct MomentFrames: View {
    /// The moment's camera rows, front first.
    let rows: [EnrichRow]
    /// The camera whose clip is in the reel, if any.
    let reelCamera: String?
    /// The project: its `frames/` folder, and its video folder for frames missing there.
    let project: Project
    /// Clock text, e.g. "0:16:05".
    let clock: String
    /// How the moment came to be in or out of the reel.
    let status: FineTuneModel.PickStatus
    /// `true` to stack the frames (iPhone, where side by side would make each one tiny); side by side otherwise.
    let stacked: Bool
    /// Called with the tapped frame's camera.
    let onTap: (String) -> Void

    /// Time and status on one line, the frames below.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(clock).font(.headline.monospacedDigit())
                Spacer()
                badge(status.label, highlighted: status == .aiPick || status == .userPick)
            }
            .accessibilityElement(children: .combine)
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 10))
                                 : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                ForEach(rows, id: \.camera) { cameraFrame($0) }
            }
        }
    }

    /// One camera's frame as a button; the one in the reel has an orange border and badge.
    private func cameraFrame(_ row: EnrichRow) -> some View {
        let inReel = row.camera == reelCamera
        let name = CameraNames.label(for: row.camera)
        return Button { onTap(row.camera) } label: {
            FrameImage(row: row, project: project, maxPixel: 1600)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange, lineWidth: inReel ? 4 : 0))
                .overlay(alignment: .topLeading) { badge(name, highlighted: false).padding(8) }
                .overlay(alignment: .topTrailing) {
                    if inReel { badge("In reel", highlighted: true).padding(8) }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) camera")
        .accessibilityValue(inReel ? "In reel" : "Not in reel")
        .accessibilityHint(inReel ? "Takes this moment out of the reel" : "Puts this camera's clip in the reel")
    }

    /// A small label; the dark backing keeps it readable on any footage.
    private func badge(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(highlighted ? Color.black : Color.white)
            .background(highlighted ? Color.orange : Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// How to choose a camera (or which one filmed the moment) and the reasons the moment stands out.
struct MomentInfo: View {
    /// Cameras that filmed this moment (`EnrichRow.camera` names).
    let cameras: [String]
    /// Why the moment is worth including.
    let reasons: [MomentReason]

    /// Camera hint above the reasons.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if cameras.count > 1 {
                    Label("Tap the front or rear frame to put that camera's clip in the reel", systemImage: "hand.tap")
                } else if let only = cameras.first {
                    Label("Only the \(CameraNames.label(for: only).lowercased()) camera filmed this moment",
                          systemImage: "video")
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
            if !reasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why this moment").font(.caption).foregroundStyle(.secondary)
                    WrapLayout {
                        ForEach(reasons) { reason in
                            Label(reason.text, systemImage: icon(for: reason.kind))
                                .font(.footnote)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(reason.kind == .stravaPR ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// SF Symbol for a reason.
    private func icon(for kind: MomentReason.Kind) -> String {
        switch kind {
        case .stravaPR: return "trophy"
        case .segment:  return "flag"
        case .riders:   return "person.2"
        case .climb:    return "arrow.up.right"
        case .descent:  return "arrow.down.right"
        case .speed:    return "speedometer"
        }
    }
}

/// Previous, add/remove and next, in the thumb zone. Arrow keys and Space work on a Mac keyboard.
struct ReelControls: View {
    /// `true` if the open moment is in the reel.
    let inReel: Bool
    /// Moves to the previous (-1) or next (+1) moment.
    let onStep: (Int) -> Void
    /// Adds or removes the open moment.
    let onToggle: () -> Void

    /// Three buttons, the middle one widest.
    var body: some View {
        HStack(spacing: 10) {
            Button { onStep(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 52, height: 52)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Previous moment")
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button(action: onToggle) {
                Label(inReel ? "In reel · tap to remove" : "Add to reel",
                      systemImage: inReel ? "checkmark.circle.fill" : "plus.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(inReel ? Color.black : Color.orange)
                    .background(inReel ? Color.orange : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange, lineWidth: inReel ? 0 : 2))
            }
            .keyboardShortcut(.space, modifiers: [])

            Button { onStep(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 52, height: 52)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Next moment")
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .buttonStyle(.plain)
        .font(.title3.weight(.semibold))
    }
}

/// Plain names for the Cycliq cameras.
enum CameraNames {
    /// "Front" for the Fly12 Sport, "Rear" for the Fly6 Pro, otherwise the raw name.
    static func label(for camera: String) -> String {
        switch camera {
        case AppConfig.CameraName.fly12Sport.rawValue: return "Front"
        case AppConfig.CameraName.fly6Pro.rawValue:    return "Rear"
        default:                                       return camera
        }
    }
}
