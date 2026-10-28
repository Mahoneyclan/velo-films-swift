// RideTimelineView.swift
// The ride timeline at the top of the Fine Tune screen: elevation behind, lap lines, a tick for every clip in the
// reel and a marker for the open moment. Tap or drag to jump; VoiceOver users swipe up or down to step.

import SwiftUI

/// The whole ride at a glance, used to see gaps in the reel and jump to any part of the ride.
struct RideTimelineView: View {
    /// Elevation scaled 0…1, evenly spaced across the ride (may be empty).
    let elevation: [Double]
    /// Laps as (short label, position 0…1).
    let laps: [(label: String, position: Double)]
    /// Positions (0…1) of the clips in the reel.
    let reelPositions: [Double]
    /// Position (0…1) of the open moment, or `nil` if none.
    let current: Double?
    /// Clock text of the open moment, e.g. "0:16:05".
    let currentClock: String
    /// Clock text of the ride's length.
    let totalClock: String
    /// Called with the position (0…1) tapped or dragged to.
    let onScrub: (Double) -> Void
    /// Called with -1 or +1 when VoiceOver users adjust the timeline.
    let onStep: (Int) -> Void

    /// Header, drawing and legend.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ride timeline · tap or drag to jump")
                Spacer()
                Text("\(currentClock) of \(totalClock)").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            GeometryReader { geo in
                Canvas { ctx, size in draw(in: &ctx, size: size) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        onScrub(min(1, max(0, value.location.x / max(1, geo.size.width))))
                    })
            }
            .frame(height: 72)
            .accessibilityElement()
            .accessibilityLabel("Ride timeline")
            .accessibilityValue("\(currentClock) of \(totalClock), \(reelPositions.count) clips in the reel")
            .accessibilityHint("Swipe up or down to move between moments")
            .accessibilityAdjustableAction { direction in
                onStep(direction == .increment ? 1 : -1)
            }

            legend
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Explains the marks; shapes as well as colour, so the meaning doesn't rely on colour alone.
    private var legend: some View {
        WrapLayout(spacing: 12) {
            Label { Text("Clip in reel") } icon: {
                RoundedRectangle(cornerRadius: 1).fill(.orange).frame(width: 3, height: 10)
            }
            Label { Text("Lap") } icon: {
                Rectangle().fill(.secondary).frame(width: 1, height: 10)
            }
            Label { Text("Elevation") } icon: {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.35)).frame(width: 12, height: 8)
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    /// Draws elevation, laps, reel ticks and the open-moment marker.
    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let top: CGFloat = 16, profileHeight = size.height - top
        if elevation.count > 1 {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, e) in elevation.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(elevation.count - 1)
                // Keep 15% headroom so the highest point doesn't touch the reel ticks.
                path.addLine(to: CGPoint(x: x, y: size.height - profileHeight * 0.85 * CGFloat(e)))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            ctx.fill(path, with: .style(.secondary.opacity(0.25)))
            ctx.stroke(path, with: .style(.secondary.opacity(0.6)), lineWidth: 1)
        }
        for lap in laps {
            let x = size.width * lap.position
            ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .style(.secondary.opacity(0.6)))
            ctx.draw(Text(lap.label).font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: x + 3, y: 0), anchor: .topLeading)
        }
        for p in reelPositions {
            let rect = CGRect(x: size.width * p - 1.5, y: top, width: 3, height: 10)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.orange))
        }
        if let current {
            let x = size.width * current
            ctx.fill(Path(CGRect(x: x - 1, y: top - 4, width: 2, height: size.height - top + 4)),
                     with: .style(.primary))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 6, y: size.height - 12, width: 12, height: 12)),
                     with: .style(.primary))
        }
    }
}
