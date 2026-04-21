import SwiftUI
import AVKit

/// Touch-optimised clip selection UI. Mirrors manual_selection_window.py.
/// Grid of moments; each moment shows front + rear perspectives.
/// Swipe or tap to toggle recommended flag; only one perspective per moment.
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
                LazyVStack(spacing: 16) {
                    ForEach(moments, id: \.momentId) { moment in
                        MomentCard(moment: moment, selectRows: $selectRows)
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
        .task { await load() }
    }

    private func load() async {
        guard let rows = try? CSVReader().read(from: project.selectCSV) as [SelectRow] else { return }
        let enriched = rows.map { r -> EnrichRow in
            // Convert SelectRow → EnrichRow for PartnerMatcher
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
        moments = PartnerMatcher.group(enriched)
    }

    private func save() {
        try? CSVWriter().write(rows: selectRows, to: project.selectCSV)
    }
}

private struct MomentCard: View {
    let moment: PartnerMatcher.Moment
    @Binding var selectRows: [SelectRow]

    var body: some View {
        HStack(spacing: 12) {
            ForEach([moment.fly12Row, moment.fly6Row].compactMap { $0 }, id: \.index) { row in
                PerspectiveCard(row: row, isSelected: isSelected(row),
                                onTap: { toggle(row) })
            }
        }
    }

    private func isSelected(_ row: EnrichRow) -> Bool {
        selectRows.first { $0.index == row.index }?.recommended ?? false
    }

    private func toggle(_ row: EnrichRow) {
        // Deselect all rows for this moment, then select tapped one
        for i in selectRows.indices {
            if selectRows[i].momentId == row.momentId {
                selectRows[i].recommended = (selectRows[i].index == row.index)
                    ? !selectRows[i].recommended
                    : false
            }
        }
    }
}

private struct PerspectiveCard: View {
    let row: EnrichRow
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(.quaternary)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay {
                    Text("\(row.camera)\n\(String(format: "%.2f", row.scoreWeighted))")
                        .font(.caption2.monospaced())
                        .multilineTextAlignment(.center)
                        .padding(4)
                }
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                )

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, .accentColor)
                    .padding(6)
            }
        }
        .onTapGesture(perform: onTap)
    }
}
