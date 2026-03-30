import SwiftUI
import Charts

struct MoodTrackerView: View {
    @State private var entries: [MoodEntry] = []
    @State private var emotions: [MoodEmotion] = []
    @State private var showLogSheet = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var nextOffset: Int? = nil
    @State private var rpeByDate: [String: Double] = [:]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 50))
                            .foregroundColor(.yellow)
                        Text("Aucune humeur loggée")
                            .font(.headline)
                        Text("Commence à tracker ton humeur pour voir tes tendances.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Correlation chart header
                        let correlationPoints = entries.compactMap { e -> (Int, Double)? in
                            guard let rpe = rpeByDate[String(e.date.prefix(10))] else { return nil }
                            return (e.score, rpe)
                        }
                        if correlationPoints.count >= 3 {
                            Section {
                                MoodRPECorrelationCard(points: correlationPoints)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets())
                            }
                        }

                        ForEach(entries) { entry in
                            MoodEntryRow(entry: entry, emotions: emotions)
                        }
                        if hasMore {
                            Button { Task { await loadMore() } } label: {
                                HStack {
                                    Spacer()
                                    if isLoadingMore {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Text("Charger plus…")
                                            .font(.subheadline).foregroundColor(.yellow)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }

            // FAB
            Button { showLogSheet = true } label: {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(18)
                    .background(Color.yellow)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(24)
        }
        .navigationTitle("Humeur")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogSheet, onDismiss: { Task { await loadData() } }) {
            MoodLogSheet(emotions: emotions)
        }
        .task { await loadData() }
    }

    private func loadData() async {
        async let e  = try? APIService.shared.fetchMoodEmotions()
        async let pg = try? APIService.shared.fetchMoodHistory()
        let (em, page) = await (e, pg)
        await MainActor.run {
            emotions = em ?? []
            if let page {
                entries    = page.items
                hasMore    = page.hasMore
                nextOffset = page.nextOffset
            }
            isLoading = false
        }
        // Load RPE by date from stats cache
        if let cached = CacheService.shared.load(for: "stats_data"),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any],
           let sessions = json["sessions"] as? [String: [String: Any]] {
            let map = Dictionary(uniqueKeysWithValues: sessions.compactMap { (date, s) -> (String, Double)? in
                guard let rpe = s["rpe"] as? Double else { return nil }
                return (date, rpe)
            })
            await MainActor.run { rpeByDate = map }
        }
    }

    private func loadMore() async {
        guard let offset = nextOffset, !isLoadingMore else { return }
        isLoadingMore = true
        if let pg = try? await APIService.shared.fetchMoodHistory(offset: offset) {
            entries.append(contentsOf: pg.items)
            hasMore    = pg.hasMore
            nextOffset = pg.nextOffset
        }
        isLoadingMore = false
    }
}

// MARK: - Row

private struct MoodEntryRow: View {
    let entry: MoodEntry
    let emotions: [MoodEmotion]

    private var emotionLabels: String {
        let map = Dictionary(uniqueKeysWithValues: emotions.map { ($0.id, "\($0.emoji) \($0.label)") })
        return entry.emotions.compactMap { map[$0] }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                MoodScoreChip(score: entry.score)
            }
            if !emotionLabels.isEmpty {
                Text(emotionLabels)
                    .font(.subheadline)
            }
            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MoodScoreChip: View {
    let score: Int
    private var color: Color {
        switch score {
        case 8...10: return .green
        case 5...7:  return .yellow
        default:     return .red
        }
    }
    var body: some View {
        Text("\(score)/10")
            .font(.caption.bold())
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(8)
    }
}

// MARK: - Log Sheet

struct MoodLogSheet: View {
    var emotions: [MoodEmotion] = []

    @Environment(\.dismiss) private var dismiss
    @State private var score: Double = 7
    @State private var selectedEmotions: Set<String> = []
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var errorMsg: String?

    @State private var emotionList: [MoodEmotion] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Comment tu te sens ? (\(Int(score))/10)") {
                    Slider(value: $score, in: 1...10, step: 1)
                        .tint(sliderColor)
                    HStack {
                        Text("😞 1")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("10 😄")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Émotions (optionnel)") {
                    EmotionChipGrid(
                        emotions: emotionList.isEmpty ? emotions : emotionList,
                        selected: $selectedEmotions
                    )
                }

                Section("Notes (optionnel)") {
                    TextField("Qu'est-ce qui se passe ?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let err = errorMsg {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Loguer l'humeur")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { submit() }
                        .disabled(isSubmitting)
                }
            }
            .task {
                if emotionList.isEmpty {
                    emotionList = (try? await APIService.shared.fetchMoodEmotions()) ?? emotions
                }
            }
        }
    }

    private var sliderColor: Color {
        switch Int(score) {
        case 8...10: return .green
        case 5...7:  return .yellow
        default:     return .red
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            do {
                _ = try await APIService.shared.submitMood(
                    score:    Int(score),
                    emotions: Array(selectedEmotions),
                    notes:    notes.isEmpty ? nil : notes,
                    triggers: []
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

private struct EmotionChipGrid: View {
    let emotions: [MoodEmotion]
    @Binding var selected: Set<String>

    var body: some View {
        FlowLayoutMH(spacing: 8) {
            ForEach(emotions) { emotion in
                EmotionChip(emotion: emotion, isSelected: selected.contains(emotion.id)) {
                    if selected.contains(emotion.id) {
                        selected.remove(emotion.id)
                    } else {
                        selected.insert(emotion.id)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EmotionChip: View {
    let emotion: MoodEmotion
    let isSelected: Bool
    let onTap: () -> Void

    private var chipColor: Color {
        switch emotion.valence {
        case  1: return .green
        case -1: return .red
        default: return .gray
        }
    }

    var body: some View {
        Button(action: onTap) {
            Text("\(emotion.emoji) \(emotion.label)")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? chipColor.opacity(0.25) : Color(.tertiarySystemFill))
                .foregroundColor(isSelected ? chipColor : .primary)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? chipColor : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// Simple wrapping flow layout for chips
struct FlowLayoutMH: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                height   += rowHeight + spacing
                rowWidth  = 0
                rowHeight = 0
            }
            rowWidth  += size.width + spacing
            rowHeight  = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y  += rowHeight + spacing
                x   = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x         += size.width + spacing
            rowHeight  = max(rowHeight, size.height)
        }
    }
}

// MARK: - Mood / RPE Correlation Card
private struct MoodRPECorrelationCard: View {
    let points: [(mood: Int, rpe: Double)]

    private var correlation: Double {
        guard points.count >= 2 else { return 0 }
        let n  = Double(points.count)
        let xs = points.map { Double($0.mood) }
        let ys = points.map { $0.rpe }
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let dx  = xs.map { pow($0 - mx, 2) }.reduce(0, +)
        let dy  = ys.map { pow($0 - my, 2) }.reduce(0, +)
        let den = sqrt(dx * dy)
        return den == 0 ? 0 : num / den
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HUMEUR vs RPE")
                    .font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.secondary)
                Spacer()
                let r = correlation
                Text("r = \(String(format: "%.2f", r))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(abs(r) > 0.4 ? .yellow : .secondary)
            }

            Chart(points.indices, id: \.self) { i in
                PointMark(
                    x: .value("Humeur", points[i].mood),
                    y: .value("RPE", points[i].rpe)
                )
                .foregroundStyle(Color.yellow.opacity(0.7))
                .symbolSize(60)
            }
            .chartXAxis {
                AxisMarks(values: [1, 3, 5, 7, 9, 10]) { v in
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.caption2) }
                }
            }
            .chartYAxis {
                AxisMarks(values: [6, 7, 8, 9, 10]) { v in
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.caption2) }
                }
            }
            .chartXAxisLabel("Humeur (1–10)", alignment: .center)
            .chartYAxisLabel("RPE", position: .leading)
            .frame(height: 150)

            let r = correlation
            Text(r < -0.3 ? "Bonne humeur → RPE plus bas" : r > 0.3 ? "Humeur élevée → effort intense" : "Pas de corrélation claire")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 4)
    }
}
