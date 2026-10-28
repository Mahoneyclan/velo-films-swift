// FilmStripView.swift
// The horizontal film strip on the Fine Tune screen: one column per moment passing the filter, with a tick on the
// clip in the reel. Two rows (front above rear) on iPad and Mac, one row on iPhone. Scrolls to keep the open
// moment in view.

import SwiftUI

/// Thumbnails of the visible moments; tapping one opens it (the camera is chosen on the large frames, so scrolling
/// and tapping here never changes a pick).
struct FilmStripView: View {
    /// The Fine Tune state.
    let model: FineTuneModel
    /// The project's `frames/` folder.
    let framesDir: URL
    /// Thumbnail width; height follows at 16:9.
    let thumbWidth: CGFloat
    /// `true` for a front row above a rear row; `false` for one row showing the camera in the reel (or the
    /// higher-scoring one).
    let twoRows: Bool
    /// Called when the user asks to restore the app's picks (the caller confirms first).
    let onReset: () -> Void

    /// Title row and the scrolling strip.
    var body: some View {
        let shown = model.visible
        let openId = model.current?.momentId
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(model.filter == .all ? "Moments" : model.filter.label) · \(shown.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset to AI picks", action: onReset)
                    .font(.caption)
                    .disabled(!model.hasManualChanges)
                    .frame(minHeight: 44)
            }
            HStack(alignment: .top, spacing: 8) {
                if twoRows { rowLabels }
                strip(shown, openId: openId)
            }
        }
    }

    /// The camera rows: front on top. Matched by `EnrichRow.camera`.
    private static let cameraRows = [AppConfig.CameraName.fly12Sport.rawValue, AppConfig.CameraName.fly6Pro.rawValue]
    /// Thumbnail height at 16:9.
    private var thumbHeight: CGFloat { thumbWidth * 9 / 16 }

    /// "Front" and "Rear" beside the two rows.
    private var rowLabels: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(Self.cameraRows, id: \.self) { camera in
                Text(CameraNames.label(for: camera))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(height: thumbHeight)
            }
        }
        .padding(.vertical, 4)   // lines up with the cells: strip padding (2) + column padding (2)
        .accessibilityHidden(true)
    }

    /// The scrolling columns.
    private func strip(_ shown: [PartnerMatcher.Moment], openId: Int?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(shown, id: \.momentId) { m in
                        column(m, isOpen: m.momentId == openId)
                            .id(m.momentId)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: openId) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// One moment: a button holding one or two thumbnails, outlined when open.
    private func column(_ m: PartnerMatcher.Moment, isOpen: Bool) -> some View {
        let inReel = model.isInReel(m.momentId)
        let clock = model.clock(Double(m.momentId))
        let reelCamera = model.reelCamera(of: m.momentId)
        return Button { model.open(m.momentId) } label: {
            VStack(spacing: 6) {
                if twoRows {
                    ForEach(Self.cameraRows, id: \.self) { camera in
                        cell(m.rows.first { $0.camera == camera }, inReel: camera == reelCamera,
                             clock: camera == Self.cameraRows[0] ? clock : nil)
                    }
                } else {
                    cell(model.shownRow(for: m), inReel: inReel, clock: clock)
                }
            }
            .padding(2)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOpen ? Color.primary : .clear, lineWidth: 2))
            .opacity(inReel || isOpen ? 1 : 0.75)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(clock: clock, reelCamera: reelCamera))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    /// One thumbnail: orange border and tick when it is the clip in the reel; an empty tile when that camera didn't
    /// film the moment.
    /// - Parameters:
    ///   - row: The camera frame, or `nil` if that camera has none.
    ///   - inReel: `true` if this frame's clip is in the reel.
    ///   - clock: Ride time to print on the tile, or `nil` for none (the rear row, to avoid repeating it).
    private func cell(_ row: EnrichRow?, inReel: Bool, clock: String?) -> some View {
        ZStack {
            if let row {
                FrameImage(row: row, framesDir: framesDir, maxPixel: 360)
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: "video.slash").foregroundStyle(.secondary)
            }
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .overlay(alignment: .topTrailing) {
            if inReel {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black, .orange)
                    .padding(4)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let clock {
                Text(clock).font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(.black.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(inReel ? Color.orange : .clear, lineWidth: 2))
    }

    /// VoiceOver text for a column, e.g. "0:16:05, in reel, rear camera".
    private func accessibilityText(clock: String, reelCamera: String?) -> String {
        guard let reelCamera else { return "\(clock), not in reel" }
        return "\(clock), in reel, \(CameraNames.label(for: reelCamera).lowercased()) camera"
    }
}
