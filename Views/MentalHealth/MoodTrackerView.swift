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
                            .foregroundColor(Color.forge)
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
                                            .font(.subheadline).foregroundColor(Color.forge)
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
                    .background(Color.forge)
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
        // sequential — async let LIFO crash on iOS 26 beta
        let em   = try? await APIService.shared.fetchMoodEmotions()
        let page = try? await APIService.shared.fetchMoodHistory()
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
    private var color: Color { Color.moodColor(for: score) }
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

    // Creuser (optionnel)
    @State private var isCreuserExpanded: Bool = false
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var backdateEnabled: Bool = false
    @State private var backdateValue: Date = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MENTAL & ÂME")
                            .font(.appMicro.weight(.semibold))
                            .tracking(1.6)
                            .foregroundColor(.forge)
                        Text("Loguer l'humeur")
                            .font(.appTitle)
                            .foregroundColor(.appTextPrimary)
                        Text("Prends quelques secondes pour faire le point.")
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Comment tu te sens aujourd'hui ?")
                                    .font(.appHeadline)
                                    .foregroundColor(.appTextPrimary)
                                Text("Sur une échelle de 1 à 10")
                                    .font(.appCaption)
                                    .foregroundColor(.appTextSecondary)
                            }
                            Spacer()
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(Int(score))")
                                    .font(.appCardHero)
                                    .foregroundColor(.appTextPrimary)
                                Text("/10")
                                    .font(.appLabel.weight(.semibold))
                                    .foregroundColor(.appTextMuted)
                            }
                        }

                        Text(scoreDescriptor)
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(scoreSemanticColor)

                        Slider(value: $score, in: 1...10, step: 1)
                            .tint(scoreSemanticColor)
                            .accessibilityLabel("Humeur")
                            .accessibilityValue("\(Int(score)) sur 10, \(scoreDescriptor)")

                        HStack(spacing: 0) {
                            ForEach(1...10, id: \.self) { marker in
                                Text("\(marker)")
                                    .font(.appMicro.weight(marker == Int(score) ? .bold : .regular))
                                    .foregroundColor(marker == Int(score) ? .appTextPrimary : .appTextSecondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        HStack {
                            Text("Très mal").foregroundColor(.appDanger)
                            Spacer()
                            Text("Neutre").foregroundColor(.appTextSecondary)
                            Spacer()
                            Text("Au top").foregroundColor(.appSuccess)
                        }
                        .font(.appCaption.weight(.medium))
                    }
                    .padding(18)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Émotions")
                                    .font(.appHeadline)
                                    .foregroundColor(.appTextPrimary)
                                Text("Qu'est-ce qui décrit le mieux ton état ?")
                                    .font(.appCaption)
                                    .foregroundColor(.appTextSecondary)
                            }
                            Spacer()
                            if !selectedEmotions.isEmpty {
                                Text("\(selectedEmotions.count) sélectionnée\(selectedEmotions.count > 1 ? "s" : "")")
                                    .font(.appMicro.weight(.semibold))
                                    .foregroundColor(.appTextMuted)
                            }
                        }
                        EmotionChipGrid(
                            emotions: emotionList.isEmpty ? emotions : emotionList,
                            selected: $selectedEmotions
                        )
                    }
                    .padding(18)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notes")
                            .font(.appHeadline)
                            .foregroundColor(.appTextPrimary)
                        Text("Qu'est-ce qui influence ton humeur ?")
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)
                        TextField("Écris quelques mots…", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.appBody)
                            .foregroundColor(.appTextPrimary)
                            .padding(12)
                            .background(Color.appSurfaceInset)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(18)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        DisclosureGroup(isExpanded: $isCreuserExpanded) {
                            creuserContent
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Creuser davantage")
                                    .font(.appHeadline)
                                    .foregroundColor(.appTextPrimary)
                                Text("Ajoute du contexte si tu veux comprendre ta journée.")
                                    .font(.appCaption)
                                    .foregroundColor(.appTextSecondary)
                            }
                        }
                        .tint(.forge)
                    }
                    .padding(18)
                    .glassCard()

                    if let err = errorMsg {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.appDanger)
                            Text(err)
                                .font(.appCaption)
                                .foregroundColor(.appTextPrimary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appSurfaceInset)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    PrimaryButton(title: "Enregistrer l'entrée", isLoading: isSubmitting, action: submit)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, .appPagePadding)
                .padding(.vertical, 20)
            }
            .background(Color.appBg)
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Annuler")
                }
            }
            .task {
                if emotionList.isEmpty {
                    emotionList = (try? await APIService.shared.fetchMoodEmotions()) ?? emotions
                }
            }
        }
    }

    private var scoreDescriptor: String {
        switch Int(score) {
        case 1...2: return "Très mal"
        case 3...4: return "Difficile"
        case 5:     return "Neutre"
        case 6:     return "Correct"
        case 7:     return "Plutôt bien"
        case 8:     return "Bien"
        case 9:     return "Très bien"
        default:    return "Au top"
        }
    }

    private var scoreSemanticColor: Color {
        switch Int(score) {
        case 1...4: return .appDanger
        case 5...6: return .appWarning
        default:    return .appSuccess
        }
    }

    // MARK: - Creuser content

    @ViewBuilder
    private var creuserContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Tags
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.appTextSecondary)

                if !tags.isEmpty {
                    FlowLayoutMH(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag).font(.caption)
                                Button {
                                    removeTag(tag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.appTextSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.appInfo.opacity(0.10))
                            .overlay(Capsule().stroke(Color.appInfo.opacity(0.25), lineWidth: 1))
                            .clipShape(Capsule())
                        }
                    }
                }

                TextField("travail · sommeil · sport…", text: $tagInput)
                    .onSubmit { addTag() }
                    .onChange(of: tagInput) { _, new in
                        if new.hasSuffix(",") { addTag() }
                    }
            }

            // Backdate
            Toggle("Loguer pour un autre jour", isOn: $backdateEnabled)
            if backdateEnabled {
                DatePicker(
                    "Date",
                    selection: $backdateValue,
                    in: (Date().addingTimeInterval(-7 * 86400))...Date(),
                    displayedComponents: .date
                )
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Tags

    private func addTag() {
        let cleaned = tagInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        defer { tagInput = "" }
        guard !cleaned.isEmpty,
              !tags.contains(where: { $0.lowercased() == cleaned.lowercased() })
        else { return }
        tags.append(cleaned)
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    // Inclut le tag en cours (non commité) pour que l'aperçu ne mente pas.
    private var pendingTags: [String] {
        let live = tagInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        guard !live.isEmpty,
              !tags.contains(where: { $0.lowercased() == live.lowercased() })
        else { return tags }
        return tags + [live]
    }

    // MARK: - Récap

    private var recapText: String {
        var parts: [String] = ["Score \(Int(score))/10"]
        let n = selectedEmotions.count
        if n > 0 { parts.append("\(n) émotion\(n > 1 ? "s" : "")") }
        if !pendingTags.isEmpty { parts.append("avec contexte") }
        if backdateEnabled {
            let df = DateFormatter()
            df.locale = Locale(identifier: "fr_FR")
            df.dateFormat = "d MMM"
            parts.append("daté du \(df.string(from: backdateValue))")
        }
        return parts.joined(separator: " · ")
    }

    private func iso8601Day(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current
        return df.string(from: d)
    }

    // MARK: - Submit

    private func submit() {
        // Capture le tag en cours si tapé mais non commité (Retour/virgule)
        if !tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addTag()
        }
        isSubmitting = true
        Task {
            do {
                _ = try await APIService.shared.submitMood(
                    score:    Int(score),
                    emotions: Array(selectedEmotions),
                    notes:    notes.isEmpty ? nil : notes,
                    triggers: tags,
                    date:     backdateEnabled ? iso8601Day(backdateValue) : nil
                )
                await MainActor.run {
                    ActionFeedbackManager.shared.show(.moodLogged)
                    dismiss()
                }
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
        VStack(alignment: .leading, spacing: 8) {
            emotionGroup(title: "Ressources", emotions: emotions.filter { $0.valence == 1 })
            emotionGroup(title: "Neutres", emotions: emotions.filter { $0.valence == 0 })
            emotionGroup(title: "Difficiles", emotions: emotions.filter { $0.valence == -1 })
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func emotionGroup(title: String, emotions: [MoodEmotion]) -> some View {
        if !emotions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.appMicro.weight(.semibold))
                    .tracking(0.8)
                    .foregroundColor(.appTextMuted)
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
            }
        }
    }
}

private struct EmotionChip: View {
    let emotion: MoodEmotion
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(emotion.emoji)
                Text(emotion.label)
                    .font(.appLabel)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(isSelected ? Color.selectedControlBackground : Color.appSurfaceInset)
            .foregroundColor(isSelected ? Color.selectedControlForeground : Color.appTextPrimary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.selectedControlBackground : Color.appSeparatorSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(emotion.label)
        .accessibilityValue(isSelected ? "Sélectionnée" : "Non sélectionnée")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.secondary)
                Spacer()
                let r = correlation
                Text("r = \(String(format: "%.2f", r))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(abs(r) > 0.4 ? .statusYellow : .secondary)
            }

            Chart(points.indices, id: \.self) { i in
                PointMark(
                    x: .value("Humeur", points[i].mood),
                    y: .value("RPE", points[i].rpe)
                )
                .foregroundStyle(Color.statusYellow.opacity(0.7))
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
