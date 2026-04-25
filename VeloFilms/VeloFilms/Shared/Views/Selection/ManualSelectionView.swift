import SwiftUI
import AVKit

/// Touch-optimised clip selection UI. Mirrors manual_selection_window.py.
/// Grid of moments; each moment always shows Fly12Sport (col 0) and Fly6Pro (col 1).
/// Missing camera = placeholder card. Tap to toggle; at most one selection per moment.
struct ManualSelectionView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var selectRows: [SelectRow] = []
    @State private var moments: [PartnerMatcher.Moment] = []

    var selectedCount: Int { selectRows.filter { $0.recommended }.count }
    var target: Int { AppConfig.targetClips }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(moments, id: \.momentId) { moment in
                        MomentCard(moment: moment, framesDir: project.framesDir,
                                   selectRows: $selectRows)
                    }
                }
                .padding()
            }
            .navigationTitle("Select Clips (\(selectedCount)/\(target))")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await load() }
    }

    private func load() async {
        guard let rows = try? JSONLReader().read(from: project.selectJSONL) as [SelectRow] else { return }
        let enriched = rows.map { r in
            EnrichRow(index: r.index, camera: r.camera, clipNum: r.clipNum,
                      frameNumber: r.frameNumber, videoPath: r.videoPath,
                      absTimeEpoch: r.absTimeEpoch, absTimeIso: r.absTimeIso,
                      sessionTsS: r.sessionTsS, clipStartEpoch: r.clipStartEpoch,
                      adjustedStartTime: r.adjustedStartTime, durationS: r.durationS,
                      source: r.source, fps: r.fps,
                      detectScore: r.detectScore, numDetections: r.numDetections,
                      bboxArea: r.bboxArea, detectedClasses: r.detectedClasses,
                      objectDetected: r.objectDetected, sceneBoost: r.sceneBoost,
                      gpxEpoch: r.gpxEpoch, gpxTimeUtc: r.gpxTimeUtc,
                      lat: r.lat, lon: r.lon, elevation: r.elevation,
                      hrBpm: r.hrBpm, cadenceRpm: r.cadenceRpm,
                      speedKmh: r.speedKmh, gradientPct: r.gradientPct,
                      scoreComposite: r.scoreComposite, scoreWeighted: r.scoreWeighted,
                      segmentBoost: r.segmentBoost, momentId: r.momentId)
        }
        selectRows = rows
        let allMoments = PartnerMatcher.group(enriched)

        let recommendedIds = Set(rows.filter { $0.recommended }.map { $0.momentId })
        let limit = max(AppConfig.targetClips * 2, recommendedIds.count + 20)
        moments = Array(
            allMoments
                .sorted { $0.bestScore > $1.bestScore }
                .prefix(limit)
        ).sorted { $0.momentId < $1.momentId }
    }

    private func save() {
        try? JSONLWriter().write(rows: selectRows, to: project.selectJSONL)
    }
}

// MARK: - Moment card — always two columns: Fly12Sport (col 0) | Fly6Pro (col 1)

private struct MomentCard: View {
    let moment: PartnerMatcher.Moment
    let framesDir: URL
    @Binding var selectRows: [SelectRow]

    var body: some View {
        HStack(spacing: 8) {
            // Column 0: Fly12Sport (front) as primary, Fly6Pro as PiP
            if let front = moment.fly12Row {
                PerspectiveCard(primary: front,
                                partner: moment.fly6Row,
                                isSelected: isSelected(front),
                                onTap: { toggle(front) },
                                framesDir: framesDir)
            } else {
                PlaceholderCard()
            }

            // Column 1: Fly6Pro (rear) as primary, Fly12Sport as PiP
            if let rear = moment.fly6Row {
                PerspectiveCard(primary: rear,
                                partner: moment.fly12Row,
                                isSelected: isSelected(rear),
                                onTap: { toggle(rear) },
                                framesDir: framesDir)
            } else {
                PlaceholderCard()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func isSelected(_ row: EnrichRow) -> Bool {
        selectRows.first { $0.index == row.index }?.recommended ?? false
    }

    private func toggle(_ row: EnrichRow) {
        for i in selectRows.indices where selectRows[i].momentId == row.momentId {
            selectRows[i].recommended = (selectRows[i].index == row.index)
                ? !selectRows[i].recommended
                : false
        }
    }
}

// MARK: - Placeholder card for missing camera

private struct PlaceholderCard: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(.secondary)
            Text("No footage")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Perspective card: primary full-size + partner PiP overlay (bottom-right ~30%)

private struct PerspectiveCard: View {
    let primary: EnrichRow
    let partner: EnrichRow?
    let isSelected: Bool
    let onTap: () -> Void
    let framesDir: URL

    @State private var primaryThumb: CGImage? = nil
    @State private var partnerThumb: CGImage? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ZStack(alignment: .bottomTrailing) {
                    // Primary thumbnail
                    thumbView(primaryThumb)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    // Partner PiP — ~30% width, bottom-right with 8pt margin
                    if partner != nil {
                        let pipW = geo.size.width * 0.30
                        let pipH = pipW * 9 / 16
                        thumbView(partnerThumb)
                            .frame(width: pipW, height: pipH)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(.black.opacity(0.4), lineWidth: 1)
                            }
                            .padding(8)
                    }
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                Text("\(primary.camera)  \(String(format: "%.2f", primary.scoreWeighted))")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55))
                    .foregroundStyle(.white)
                    .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(6)
            }
        }
        .onTapGesture(perform: onTap)
        .task(id: primary.index) {
            primaryThumb = await loadThumbnail(for: primary)
        }
        .task(id: partner?.index) {
            guard let p = partner else { return }
            partnerThumb = await loadThumbnail(for: p)
        }
    }

    @ViewBuilder
    private func thumbView(_ img: CGImage?) -> some View {
        if let img {
            Image(img, scale: 1, label: Text(""))
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay { ProgressView().controlSize(.small) }
        }
    }

    private func loadThumbnail(for row: EnrichRow) async -> CGImage? {
        let jpegURL = framesDir.appending(path: "\(row.index).jpg")
        if FileManager.default.fileExists(atPath: jpegURL.path),
           let src = CGImageSourceCreateWithURL(jpegURL as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return img
        }
        let sec = max(0, row.absTimeEpoch - row.clipStartEpoch - AppConfig.clipPreRollS)
        return await FrameSampler.extractFrame(
            videoURL: URL(fileURLWithPath: row.videoPath), atSecond: sec)
    }
}
