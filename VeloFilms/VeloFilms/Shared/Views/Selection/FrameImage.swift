// FrameImage.swift
// One camera frame on the Fine Tune screen: the JPEG saved during analysis, or a frame read from the video when
// the JPEG is missing. Also holds the wrapping layout used for chips.

import SwiftUI
import ImageIO

/// A camera frame, decoded off the main thread at no more than `maxPixel` on its long side.
struct FrameImage: View {
    /// The camera row whose frame is shown.
    let row: EnrichRow
    /// The project: its `frames/` folder, and its video folder for frames missing there.
    let project: Project
    /// Longest side in pixels after decoding; small for film-strip thumbnails, large for the open moment.
    let maxPixel: Int

    @State private var image: CGImage?

    /// The frame, or a placeholder with a spinner while it loads.
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipped()
        .task(id: row.index) {
            image = nil
            image = await Self.load(row: row, project: project, maxPixel: maxPixel)
        }
    }

    /// Loads the frame: the saved JPEG if present, otherwise the video at the start of the moment's clip.
    /// - Parameters:
    ///   - row: The camera row.
    ///   - project: The project holding the frame and the video.
    ///   - maxPixel: Longest side after decoding.
    /// - Returns: The image, or `nil` if neither source could be read.
    static func load(row: EnrichRow, project: Project, maxPixel: Int) async -> CGImage? {
        // Security: the index comes from a project file; keep only its last path component so it can't point
        // outside frames/.
        let name = URL(fileURLWithPath: row.index).lastPathComponent
        let jpeg = project.framesDir.appending(path: "\(name).jpg")
        let decoded = await Task.detached(priority: .userInitiated) {
            decode(jpeg, maxPixel: maxPixel)
        }.value
        if let decoded { return decoded }
        let second = max(0, row.clipAnchorEpoch - row.clipStartEpoch - AppConfig.clipPreRollS)
        return await FrameSampler.extractFrame(videoURL: project.videoURL(forStoredPath: row.videoPath),
                                                atSecond: second)
    }

    /// Decodes a JPEG scaled down to `maxPixel` (ImageIO thumbnails avoid decoding the full 2560-pixel frame).
    nonisolated private static func decode(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}

/// Lays children out left to right, wrapping onto new lines, for chips that must never be cut off at large text
/// sizes.
struct WrapLayout: Layout {
    /// Space between chips, both across and down.
    var spacing: CGFloat = 6

    /// The size needed to wrap the chips in the proposed width.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    /// Places each chip on its line.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    /// Splits the chips into lines that fit `width`.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([i], size.width, size.height)
            } else {
                current = (current.indices + [i], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
