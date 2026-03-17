import SwiftUI

struct MoodTrackerView: View {
    @State private var entries: [MoodEntry] = []
    @State private var emotions: [MoodEmotion] = []
    @State private var showLogSheet = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var nextOffset: Int? = nil

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
