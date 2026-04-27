import SwiftUI
import AVKit

// MARK: - Detection statistics computed from select rows

private struct DetectionStats {
    let totalFrames: Int
    let detectedCount: Int
    let avgDetectScore: Double
    let avgSpeed: Double
    let maxSpeed: Double
    let avgGradient: Double
    let classCounts: [(name: String, count: Int)]   // sorted descending by count

    init(rows: [SelectRow]) {
        totalFrames   = rows.count
        detectedCount = rows.filter { $0.base.objectDetected }.count
        avgDetectScore = rows.isEmpty ? 0 : rows.map { $0.base.detectScore }.reduce(0, +) / Double(rows.count)

        let speeds = rows.compactMap { $0.base.speedKmh }
        avgSpeed = speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count)
        maxSpeed = speeds.max() ?? 0

        let grads = rows.compactMap { $0.base.gradientPct }.map { abs($0) }
        avgGradient = grads.isEmpty ? 0 : grads.reduce(0, +) / Double(grads.count)

        var counts: [String: Int] = [:]
        for row in rows {
            for part in row.base.detectedClasses.split(separator: ",") {
                let cls = part.trimmingCharacters(in: .whitespaces)
                if !cls.isEmpty { counts[cls, default: 0] += 1 }
            }
        }
        classCounts = counts.sorted { $0.value > $1.value }.map { (name: $0.key, count: $0.value) }
    }

    var detectionRate: Double { totalFrames > 0 ? Double(detectedCount) / Double(totalFrames) : 0 }
}

// MARK: - Main view

struct ManualSelectionView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var selectRows: [SelectRow] = []
    @State private var moments: [PartnerMatcher.Moment] = []
    @State private var classFilter: String? = nil
    @State private var isLoaded = false

    var selectedCount: Int { selectRows.filter { $0.recommended }.count }
    var target: Int { AppConfig.targetClips }

    private var stats: DetectionStats { DetectionStats(rows: selectRows) }

    private var availableClasses: [String] {
        stats.classCounts.map(\.name)
    }

    private var filteredMoments: [PartnerMatcher.Moment] {
        guard let filter = classFilter else { return moments }
        return moments.filter { moment in
            [moment.fly12Row, moment.fly6Row].compactMap { $0 }.contains {
                $0.detectedClasses.localizedCaseInsensitiveContains(filter)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StatsStrip(stats: stats, selected: selectedCount, target: target)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                if !availableClasses.isEmpty {
                    Divider()
                    ClassFilterBar(classes: availableClasses,
                                   classCounts: Dictionary(uniqueKeysWithValues: stats.classCounts),
                                   activeFilter: $classFilter)
                        .padding(.vertical, 6)
                }

                Divider()

                if isLoaded && filteredMoments.isEmpty {
                    ContentUnavailableView(
                        classFilter != nil
                            ? "No clips detected with '\(classFilter!.capitalized)'"
                            : "No clips found",
                        systemImage: "eye.slash"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredMoments, id: \.momentId) { moment in
                                MomentCard(moment: moment,
                                           framesDir: project.framesDir,
                                           selectRows: $selectRows)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Select Clips (\(selectedCount) / \(target))")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Close") { save(); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 740, minHeight: 520)
        .task { await load() }
    }

    // MARK: - Data

    private func load() async {
        guard let rows = try? JSONLReader().read(from: project.selectJSONL) as [SelectRow] else { return }
        selectRows = rows

        let allMoments = PartnerMatcher.group(rows.map(\.base))
        let recommendedIds = Set(rows.filter { $0.recommended }.map { $0.base.momentId })
        let limit = max(AppConfig.targetClips * 2, recommendedIds.count + 20)

        // Top-N by score
        var topMoments = Set(
            allMoments
                .sorted { $0.bestScore > $1.bestScore }
                .prefix(limit)
                .map { $0.momentId }
        )

        // Guarantee at least 1 moment per raw video file — best moment per clip.
        // Groups by the lowest clip number among available cameras (same as ClipSelector).
        var byClip: [Int: PartnerMatcher.Moment] = [:]
        for m in allMoments {
            let c12 = m.fly12Row?.clipNum
            let c6  = m.fly6Row?.clipNum
            let key = (c12 != nil && c6 != nil) ? min(c12!, c6!) : (c12 ?? c6 ?? 0)
            if let existing = byClip[key] {
                if m.bestScore > existing.bestScore { byClip[key] = m }
            } else {
                byClip[key] = m
            }
        }
        for m in byClip.values { topMoments.insert(m.momentId) }

        moments = allMoments
            .filter { topMoments.contains($0.momentId) }
            .sorted { $0.momentId < $1.momentId }

        isLoaded = true
    }

    private func save() {
        try? JSONLWriter().write(rows: selectRows, to: project.selectJSONL)
    }
}

// MARK: - Stats strip

private struct StatsStrip: View {
    let stats: DetectionStats
    let selected: Int
    let target: Int

    var body: some View {
        HStack(spacing: 12) {
            StatPill(icon: "film.stack",
                     label: "\(stats.totalFrames)",
                     sub: "frames")
            StatPill(icon: "eye",
                     label: String(format: "%.0f%%", stats.detectionRate * 100),
                     sub: "detected",
                     tint: stats.detectionRate > 0.25 ? .green : .orange)
            StatPill(icon: "speedometer",
                     label: String(format: "%.0f km/h", stats.avgSpeed),
                     sub: "avg speed")
            StatPill(icon: "arrow.up.right",
                     label: String(format: "%.1f%%", stats.avgGradient),
                     sub: "avg grade")
            Spacer()
            // Selection counter
            HStack(spacing: 4) {
                Image(systemName: selected >= target ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected >= target ? .green : .secondary)
                Text("\(selected) / \(target)")
                    .font(.subheadline.bold())
                    .foregroundStyle(selected >= target ? .green : .primary)
                Text("clips")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatPill: View {
    let icon: String
    let label: String
    let sub: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Class filter chips

private struct ClassFilterBar: View {
    let classes: [String]
    let classCounts: [String: Int]
    @Binding var activeFilter: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ClassChip(label: "All", count: nil,
                          icon: "square.grid.2x2",
                          isActive: activeFilter == nil) {
                    activeFilter = nil
                }
                ForEach(classes, id: \.self) { cls in
                    ClassChip(label: cls.capitalized,
                               count: classCounts[cls],
                               icon: classIcon(for: cls),
                               isActive: activeFilter == cls) {
                        activeFilter = (activeFilter == cls) ? nil : cls
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

private struct ClassChip: View {
    let label: String
    let count: Int?
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption.bold())
                if let count {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isActive ? Color.white.opacity(0.3) : Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.12))
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private func classIcon(for name: String) -> String {
    switch name.lowercased() {
    case "person":        return "figure.walk"
    case "bicycle":       return "bicycle"
    case "car":           return "car"
    case "motorcycle":    return "motorcycle"
    case "bus":           return "bus"
    case "truck":         return "truck.box"
    case "traffic light": return "light.beacon.max"
    case "stop sign":     return "stop.fill"
    default:              return "tag"
    }
}

// MARK: - Moment card — two columns: Fly12Sport | Fly6Pro

private struct MomentCard: View {
    let moment: PartnerMatcher.Moment
    let framesDir: URL
    @Binding var selectRows: [SelectRow]

    private var fly12SelectRow: SelectRow? {
        guard let row = moment.fly12Row else { return nil }
        return selectRows.first { $0.base.index == row.index }
    }
    private var fly6SelectRow: SelectRow? {
        guard let row = moment.fly6Row else { return nil }
        return selectRows.first { $0.base.index == row.index }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Badges row
            HStack(spacing: 6) {
                // Timestamp
                if let ts = (moment.fly12Row ?? moment.fly6Row)?.absTimeIso.prefix(19) {
                    Label(String(ts), systemImage: "clock")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if moment.isSingleCamera {
                    BadgePill(text: "Single Camera", color: .orange, icon: "camera")
                }
                if fly12SelectRow?.stravaPR == true || fly6SelectRow?.stravaPR == true {
                    BadgePill(text: "Strava PR", color: .orange, icon: "trophy")
                }
                if let seg = fly12SelectRow?.segmentName ?? fly6SelectRow?.segmentName {
                    BadgePill(text: seg, color: .blue, icon: "location")
                }
            }
            .padding(.horizontal, 2)

            HStack(spacing: 8) {
                if let front = moment.fly12Row {
                    PerspectiveCard(primary: front,
                                    partner: moment.fly6Row,
                                    isSelected: isSelected(front),
                                    onTap: { toggle(front) },
                                    framesDir: framesDir)
                } else {
                    PlaceholderCard(label: "No front footage\n(Fly12 Sport)")
                }

                if let rear = moment.fly6Row {
                    PerspectiveCard(primary: rear,
                                    partner: moment.fly12Row,
                                    isSelected: isSelected(rear),
                                    onTap: { toggle(rear) },
                                    framesDir: framesDir)
                } else {
                    PlaceholderCard(label: "No rear footage\n(Fly6 Pro)")
                }
            }
        }
    }

    private func isSelected(_ row: EnrichRow) -> Bool {
        selectRows.first { $0.base.index == row.index }?.recommended ?? false
    }

    private func toggle(_ row: EnrichRow) {
        for i in selectRows.indices where selectRows[i].base.momentId == row.momentId {
            selectRows[i].recommended = (selectRows[i].base.index == row.index)
                ? !selectRows[i].recommended
                : false
        }
    }
}

// MARK: - Badge pill

private struct BadgePill: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text).font(.caption2.bold())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Placeholder card

private struct PlaceholderCard: View {
    let label: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Perspective card

private struct PerspectiveCard: View {
    let primary: EnrichRow
    let partner: EnrichRow?
    let isSelected: Bool
    let onTap: () -> Void
    let framesDir: URL

    @State private var primaryThumb: CGImage? = nil
    @State private var partnerThumb: CGImage? = nil

    private var detectedClasses: [String] {
        primary.detectedClasses
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail + overlays
            ZStack(alignment: .topTrailing) {
                GeometryReader { geo in
                    ZStack(alignment: .bottomTrailing) {
                        thumbView(primaryThumb)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                        if partner != nil {
                            let pipW = geo.size.width * 0.28
                            let pipH = pipW * 9 / 16
                            thumbView(partnerThumb)
                                .frame(width: pipW, height: pipH)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(.black.opacity(0.5), lineWidth: 1)
                                }
                                .padding(6)
                        }
                    }
                    // Camera label + score bottom-left
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(primary.camera)
                                .font(.caption2.bold().monospaced())
                            Text(String(format: "%.3f", primary.scoreWeighted))
                                .font(.caption2.monospaced())
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .padding(6)
                    }
                    // Detection class badges top-left
                    .overlay(alignment: .topLeading) {
                        if !detectedClasses.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(detectedClasses.prefix(4), id: \.self) { cls in
                                    HStack(spacing: 2) {
                                        Image(systemName: classIcon(for: cls))
                                            .font(.system(size: 8, weight: .bold))
                                        Text(cls.capitalized)
                                            .font(.system(size: 9, weight: .semibold))
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.black.opacity(0.65))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(6)
                        }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.title3)
                        .padding(8)
                }
            }
            .onTapGesture(perform: onTap)

            // Score breakdown bar
            ScoreBar(row: primary)
                .padding(.top, 4)

            // Speed + gradient row
            HStack(spacing: 10) {
                if let speed = primary.speedKmh {
                    Label(String(format: "%.0f km/h", speed), systemImage: "speedometer")
                }
                if let grad = primary.gradientPct {
                    Label(String(format: "%+.1f%%", grad), systemImage: "arrow.up.right")
                        .foregroundStyle(abs(grad) > 4 ? .orange : .secondary)
                }
                Spacer()
                if primary.sceneBoost > 0 {
                    Label(String(format: "+%.2f scene", primary.sceneBoost),
                          systemImage: "camera.aperture")
                        .foregroundStyle(.purple)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
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

// MARK: - Score breakdown bar

private struct ScoreBar: View {
    let row: EnrichRow

    private struct Segment {
        let label: String
        let value: Double   // 0–1 normalised contribution
        let color: Color
    }

    private var segments: [Segment] {
        let detect  = min(row.detectScore, 1.0)          * AppConfig.ScoreWeights.detectScore
        let speed   = min((row.speedKmh ?? 0) / AppConfig.speedNormDivisor, 1.0)
                                                          * AppConfig.ScoreWeights.speedKmh
        let grad    = min(abs(row.gradientPct ?? 0) / AppConfig.gradNormDivisor, 1.0)
                                                          * AppConfig.ScoreWeights.gradient
        let scene   = min(row.sceneBoost, 1.0)           * AppConfig.ScoreWeights.sceneBoost
        let bbox    = min(row.bboxArea / AppConfig.bboxNormDivisor, 1.0)
                                                          * AppConfig.ScoreWeights.bboxArea
        let segment = min(row.segmentBoost, 1.0)         * AppConfig.ScoreWeights.segmentBoost
        return [
            Segment(label: "detect",  value: detect,  color: .green),
            Segment(label: "speed",   value: speed,   color: .blue),
            Segment(label: "grade",   value: grad,    color: .orange),
            Segment(label: "scene",   value: scene,   color: .purple),
            Segment(label: "bbox",    value: bbox,    color: .yellow),
            Segment(label: "segment", value: segment, color: .teal),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments, id: \.label) { seg in
                    Rectangle()
                        .fill(seg.color)
                        .frame(width: max(1, geo.size.width * seg.value / 0.9))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .background(RoundedRectangle(cornerRadius: 2).fill(.quaternary))
        .help(scoreTooltip)
    }

    private var scoreTooltip: String {
        String(format: "Composite: %.3f  Weighted: %.3f\nDetect: %.3f  Speed: %.0f km/h  Grade: %.1f%%  Scene: %.3f",
               row.scoreComposite, row.scoreWeighted,
               row.detectScore, row.speedKmh ?? 0, row.gradientPct ?? 0, row.sceneBoost)
    }
}
