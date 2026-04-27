import SwiftUI

// MARK: - Journal View

struct JournalView: View {
    @StateObject private var api = APIService.shared
    @State private var entries:         [JournalEntry] = []
    @State private var contextualPrompt: ContextualPrompt? = nil
    @State private var showEntrySheet   = false
    @State private var isLoading        = true
    @State private var isLoadingMore    = false
    @State private var hasMore          = false
    @State private var nextOffset: Int? = nil
    @State private var searchText       = ""

    private var filtered: [JournalEntry] {
        guard !searchText.isEmpty else { return entries }
        let q = searchText.lowercased()
        return entries.filter {
            $0.content.lowercased().contains(q) || $0.prompt.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                // Prompt contextuel du jour
                if let cp = contextualPrompt {
                    Section {
                        Button { showEntrySheet = true } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: cp.signal.icon)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(cp.signal.color)
                                    Text(cp.signal.label.uppercased())
                                        .font(.system(size: 9, weight: .black)).tracking(1.5)
                                        .foregroundColor(cp.signal.color)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(cp.signal.color.opacity(0.1))
                                .clipShape(Capsule())

                                Text(cp.prompt)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text("Appuie pour écrire →")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Label("Prompt du jour", systemImage: "lightbulb.fill")
                            .font(.caption.bold())
                            .foregroundColor(.yellow)
                    }
                }

                // Historique
                if !filtered.isEmpty {
                    Section("Entrées récentes") {
                        ForEach(filtered) { entry in
                            JournalEntryRow(entry: entry)
                        }
                        if hasMore && searchText.isEmpty {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoadingMore {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Text("Charger plus…")
                                            .font(.subheadline).foregroundColor(.indigo)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if !isLoading {
                    Section {
                        Text("Aucune entrée trouvée.")
                            .foregroundColor(.secondary).font(.subheadline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Rechercher dans le journal")
            .overlay { if isLoading { ProgressView() } }

            // FAB
            Button { showEntrySheet = true } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title2).foregroundColor(.white)
                    .padding(18)
                    .background(Color.indigo)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(24)
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEntrySheet, onDismiss: { Task { await loadData() } }) {
            JournalEntrySheet(prompt: contextualPrompt?.prompt ?? "")
        }
        .task { await loadData() }
    }

    private func loadData() async {
        // Load in parallel: entries + PSS + mood + dashboard
        async let entriesTask  = try? APIService.shared.fetchJournalEntries()
        async let pssTask      = try? APIService.shared.fetchPSSHistory()
        async let moodTask     = try? APIService.shared.fetchMoodHistory(days: 14, limit: 14)
        let (pg, pssHistory, moodPage) = await (entriesTask, pssTask, moodTask)

        let dash     = APIService.shared.dashboard
        let sessions = dash?.sessions ?? [:]
        let recentSessions = sessions.sorted { $0.key > $1.key }.prefix(5).map { $0.value }
        let avgRPE: Double? = {
            let rpes = recentSessions.compactMap { $0.rpe }
            guard !rpes.isEmpty else { return nil }
            return rpes.reduce(0, +) / Double(rpes.count)
        }()
        let moodEntries = moodPage?.items ?? []
        let latestPSS   = pssHistory?.first

        let cp = JournalPromptEngine.generate(
            pssRecord:    latestPSS,
            moodEntries:  moodEntries,
            avgRPE:       avgRPE,
            sessionCount: sessions.count
        )

        await MainActor.run {
            contextualPrompt = cp
            if let pg {
                entries    = pg.items
                hasMore    = pg.hasMore
                nextOffset = pg.nextOffset
            }
            isLoading = false
        }
    }

    private func loadMore() async {
        guard let offset = nextOffset, !isLoadingMore else { return }
        isLoadingMore = true
        if let pg = try? await APIService.shared.fetchJournalEntries(offset: offset) {
            entries.append(contentsOf: pg.items)
            hasMore    = pg.hasMore
            nextOffset = pg.nextOffset
        }
        isLoadingMore = false
    }
}

// MARK: - Contextual Prompt Engine

struct ContextualPrompt {
    struct Signal {
        let label: String
        let icon: String
        let color: Color
    }
    let prompt: String
    let signal: Signal
}

enum JournalPromptEngine {

    static func generate(
        pssRecord:    PSSRecord?,
        moodEntries:  [MoodEntry],
        avgRPE:       Double?,
        sessionCount: Int
    ) -> ContextualPrompt {

        // 1. Stress élevé (PSS)
        if let pss = pssRecord, pss.category == "high" || pss.score >= 27 {
            return ContextualPrompt(
                prompt: highStressPrompt(pss: pss),
                signal: .init(label: "Stress élevé détecté", icon: "exclamationmark.triangle.fill", color: .red)
            )
        }

        // 2. Stress modéré (PSS)
        if let pss = pssRecord, pss.category == "moderate" || (pss.score >= 14 && pss.score < 27) {
            return ContextualPrompt(
                prompt: moderateStressPrompt(triggers: pss.triggers),
                signal: .init(label: "Stress modéré", icon: "brain.head.profile", color: .orange)
            )
        }

        // 3. Humeur en baisse (mood trend négatif)
        if let moodTrend = computeMoodTrend(entries: moodEntries), moodTrend < -0.5 {
            let avg = moodEntries.prefix(7).map { Double($0.score) }.reduce(0, +) / 7.0
            return ContextualPrompt(
                prompt: lowMoodPrompt(avgScore: avg),
                signal: .init(label: "Humeur en baisse", icon: "arrow.down.heart.fill", color: .orange)
            )
        }

        // 4. Séance intense (RPE élevé)
        if let rpe = avgRPE, rpe >= 8.5 {
            return ContextualPrompt(
                prompt: intenseSessionPrompt(rpe: rpe),
                signal: .init(label: "Effort intense récent", icon: "flame.fill", color: .red)
            )
        }

        // 5. Humeur élevée / momentum positif
        if let moodTrend = computeMoodTrend(entries: moodEntries), moodTrend > 0.5 {
            return ContextualPrompt(
                prompt: positiveMomentumPrompt(),
                signal: .init(label: "Momentum positif", icon: "arrow.up.heart.fill", color: .green)
            )
        }

        // 6. Milestone session count
        if [25, 50, 100, 150, 200].contains(sessionCount) {
            return ContextualPrompt(
                prompt: "Tu viens d'atteindre \(sessionCount) séances. Qu'est-ce que cette régularité dit de toi ? Qu'est-ce qui a changé depuis le début ?",
                signal: .init(label: "Milestone \(sessionCount) séances", icon: "trophy.fill", color: .yellow)
            )
        }

        // 7. Neutre — prompt de fond
        return ContextualPrompt(
            prompt: neutralPrompts.randomElement() ?? neutralPrompts[0],
            signal: .init(label: "Réflexion du jour", icon: "lightbulb.fill", color: .yellow)
        )
    }

    // MARK: - Prompt banks

    private static func highStressPrompt(pss: PSSRecord) -> String {
        let prompts = [
            "Ton niveau de stress est élevé en ce moment. Qu'est-ce qui pèse le plus ? Essaie de le mettre en mots sans te juger.",
            "Qu'est-ce qui est hors de ton contrôle en ce moment ? Comment pourrais-tu lâcher prise sur ce point ?",
            "Décris une situation récente où tu t'es senti dépassé. Qu'aurais-tu pu faire différemment ?",
            "Si tu pouvais supprimer une source de stress de ta vie demain matin, laquelle choisirais-tu ? Pourquoi ?"
        ]
        if !pss.triggers.isEmpty {
            let t = pss.triggers.prefix(2).joined(separator: ", ")
            return "Tu as identifié \(t) comme sources de stress. Lequel affecte le plus ton entraînement, et qu'est-ce que tu pourrais faire concrètement ?"
        }
        return prompts[abs(Calendar.current.component(.day, from: Date())) % prompts.count]
    }

    private static func moderateStressPrompt(triggers: [String]) -> String {
        if !triggers.isEmpty {
            let t = triggers.first ?? "ce défi"
            return "Avec '\(t)' qui occupe de l'espace mental, comment ça se reflète sur ta motivation à t'entraîner ? Que fais-tu pour tenir ?"
        }
        return "Ton stress est modéré. Qu'est-ce qui t'aide à tenir la tête hors de l'eau en ce moment ? Qu'est-ce que ton entraînement t'apporte dans cette période ?"
    }

    private static func lowMoodPrompt(avgScore: Double) -> String {
        let prompts = [
            "Ton humeur semble être en baisse ces derniers jours. Nomme 3 choses qui t'ont quand même fait sourire cette semaine, même petites.",
            "Qu'est-ce qui te manque en ce moment pour te sentir bien dans ta peau ?",
            "Si un ami traversait ce que tu traverses, que lui dirais-tu ? Applique ça à toi-même.",
            "Qu'est-ce qui draine ton énergie en ce moment, et qu'est-ce qui la recharge — même un peu ?"
        ]
        return prompts[abs(Calendar.current.component(.day, from: Date())) % prompts.count]
    }

    private static func intenseSessionPrompt(rpe: Double) -> String {
        let prompts = [
            "Tes séances récentes ont été très intenses (RPE ~\(String(format: "%.1f", rpe))/10). Qu'est-ce qui te pousse à aller aussi fort ? Motivation ou fuite ?",
            "Après des efforts intenses, qu'est-ce qui t'aide le plus à descendre en pression — physiquement et mentalement ?",
            "Comment sais-tu que tu pousses trop fort ? Quels sont tes signaux d'alarme personnels ?"
        ]
        return prompts[abs(Calendar.current.component(.day, from: Date())) % prompts.count]
    }

    private static func positiveMomentumPrompt() -> String {
        let prompts = [
            "Tu es sur une belle lancée en ce moment. Qu'est-ce qui explique cet élan ? Comment le préserver quand la motivation baissera ?",
            "Qu'est-ce qui te motive le plus en ce moment dans ton entraînement ? Qu'est-ce qui a changé ?",
            "Une chose que tu as faite cette semaine dont tu es fier, même si ça semble petit ?"
        ]
        return prompts[abs(Calendar.current.component(.day, from: Date())) % prompts.count]
    }

    private static let neutralPrompts: [String] = [
        "Qu'est-ce qui compte vraiment pour toi dans ton entraînement en ce moment — au-delà des chiffres ?",
        "Une leçon que tu as apprise sur toi-même cette semaine, à la salle ou ailleurs.",
        "Quel aspect de ton entraînement te donne le plus de satisfaction ? Pourquoi ce n'est pas toujours ça que tu priorises ?",
        "Si tu pouvais envoyer un message à la version de toi dans 6 mois, que dirais-tu ?",
        "Qu'est-ce que ton corps essaie de te dire en ce moment que tu ignores peut-être ?",
        "Quelle habitude récente t'a le plus surpris par son impact positif ou négatif ?"
    ]

    // MARK: - Mood trend helper

    private static func computeMoodTrend(entries: [MoodEntry]) -> Double? {
        let scores = entries.prefix(7).map { Double($0.score) }
        guard scores.count >= 4 else { return nil }
        let half = scores.count / 2
        let recent = Array(scores.prefix(half))
        let older  = Array(scores.dropFirst(half))
        let avgRecent = recent.reduce(0, +) / Double(recent.count)
        let avgOlder  = older.reduce(0, +) / Double(older.count)
        return avgRecent - avgOlder  // positive = improving, negative = declining
    }
}

// MARK: - Journal Entry Row

private struct JournalEntryRow: View {
    let entry: JournalEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date)
                    .font(.caption).foregroundColor(.secondary)
                if let m = entry.moodScore {
                    moodDot(m)
                }
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption).foregroundColor(.secondary)
            }
            Text(entry.prompt)
                .font(.caption.italic()).foregroundColor(.secondary)
                .lineLimit(expanded ? nil : 1)
            Text(entry.content)
                .font(.subheadline)
                .lineLimit(expanded ? nil : 2)
        }
        .padding(.vertical, 4)
        .onTapGesture { withAnimation { expanded.toggle() } }
    }

    private func moodDot(_ score: Int) -> some View {
        let color: Color = score >= 7 ? .green : score >= 4 ? .orange : .red
        return Circle()
            .fill(color.opacity(0.8))
            .frame(width: 7, height: 7)
    }
}

// MARK: - Entry Sheet

struct JournalEntrySheet: View {
    let prompt: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("journal_draft") private var draftContent = ""
    @State private var content      = ""
    @State private var moodEnabled  = false
    @State private var moodValue: Double = 5
    @State private var isSubmitting = false
    @State private var errorMsg: String?

    private var moodInt: Int { Int(moodValue.rounded()) }
    private var moodColor: Color {
        switch moodInt {
        case 1...3: return .red
        case 4...6: return .orange
        case 7...8: return .yellow
        default:    return .green
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    Text(prompt.isEmpty ? "Écris librement…" : prompt)
                        .font(.subheadline.italic()).foregroundColor(.secondary)
                }
                Section("Ton entrée") {
                    TextField("Commence à écrire…", text: $content, axis: .vertical)
                        .lineLimit(6...20)
                        .onChange(of: content) { draftContent = $0 }
                }
                Section {
                    Toggle(isOn: $moodEnabled.animation(.easeInOut(duration: 0.2))) {
                        Label("Humeur du moment", systemImage: "face.smiling").foregroundColor(.indigo)
                    }
                    .tint(.indigo)
                    if moodEnabled {
                        VStack(spacing: 12) {
                            Text("\(moodInt)")
                                .font(.system(size: 42, weight: .black)).foregroundColor(moodColor)
                                .frame(maxWidth: .infinity)
                            Slider(value: $moodValue, in: 1...10, step: 1).tint(moodColor)
                            HStack {
                                Text("😞 Très bas").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text("Excellent 😄").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Humeur (optionnel)")
                }
                if let err = errorMsg {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Nouvelle entrée")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if content.isEmpty && !draftContent.isEmpty { content = draftContent } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { submit() }
                        .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            do {
                _ = try await APIService.shared.submitJournalEntry(
                    prompt: prompt, content: content,
                    moodScore: moodEnabled ? moodInt : nil
                )
                await MainActor.run { draftContent = ""; dismiss() }
            } catch {
                await MainActor.run { errorMsg = error.localizedDescription; isSubmitting = false }
            }
        }
    }
}
