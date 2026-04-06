import SwiftUI
import Charts

// MARK: - Main View

struct PSSView: View {
    @State private var history: [PSSRecord] = []
    @State private var dueStatus: PSSDueStatus?
    @State private var isLoading = true
    @State private var showSheet = false
    @State private var isShortMode = false  // false = PSS-10, true = PSS-4
    @State private var lssToday: LifeStressScore? = nil
    @State private var lssTrend: [LifeStressScore] = []
    @State private var showBreathworkAfter = false  // shown after moderate/high PSS result

    var body: some View {
        ZStack {
            AmbientBackground(color: .purple)

                if isLoading {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // Bandeau "test dû" si applicable
                            if let due = dueStatus, due.isDue, let msg = due.message {
                                PSSdueBanner(message: msg) {
                                    isShortMode = false
                                    showSheet = true
                                }
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.03)
                            }

                            // Breathwork suggestion after moderate/high result
                            if showBreathworkAfter {
                                NavigationLink { BreathworkView() } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "lungs.fill").font(.system(size: 16)).foregroundColor(.green)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Décompresser — cohérence cardiaque")
                                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                            Text("5 min recommandées après un score élevé")
                                                .font(.system(size: 11)).foregroundColor(.gray)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.gray)
                                    }
                                    .padding(14)
                                    .glassCard(color: .green, intensity: 0.07)
                                    .cornerRadius(14)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.02)
                            }

                            // LSS compact card
                            if let lss = lssToday {
                                LSSCompactCard(lss: lss, trend: lssTrend)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.04)
                            }

                            // KPIs
                            if !history.isEmpty {
                                PSSKPIRow(history: history)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.05)
                            }

                            // PSS trend chart (only if >= 3 full records)
                            let fullRecords = history.filter { $0.type == "full" }
                            if fullRecords.count >= 3 {
                                PSSTrendChart(records: fullRecords)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.07)
                            }

                            // Historique
                            if history.isEmpty {
                                PSSEmptyState { showSheet = true }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("HISTORIQUE")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(2).foregroundColor(.gray)
                                        .padding(.horizontal, 16)
                                    ForEach(history) { record in
                                        PSSHistoryRow(record: record)
                                            .padding(.horizontal, 16)
                                    }
                                }
                                .appearAnimation(delay: 0.08)
                            }

                            Spacer(minLength: 32)
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, contentBottomPadding)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable { await loadData() }
                }
            }
            .navigationTitle("Stress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // PSS-10 dû (>28j) → full ; sinon → check-in rapide
                        isShortMode = !(dueStatus?.isDue == true)
                        showSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.purple)
                    }
                }
            }
            .sheet(isPresented: $showSheet) {
                PSSQuestionnaireSheet(isShort: isShortMode, onSaved: { record in
                    showBreathworkAfter = (record?.category == "moderate" || record?.category == "high")
                    await loadData()
                })
            }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        async let histTask = APIService.shared.fetchPSSHistory()
        async let dueTask  = APIService.shared.checkPSSDue(type: "full")
        async let lssTask  = APIService.shared.fetchLifeStressScore()
        async let trendTask = APIService.shared.fetchLifeStressTrend(days: 14)
        history    = (try? await histTask) ?? []
        dueStatus  = try? await dueTask
        lssToday   = try? await lssTask
        lssTrend   = (try? await trendTask) ?? []
        isLoading  = false
    }
}

// MARK: - Due Banner

struct PSSdueBanner: View {
    let message: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16)).foregroundColor(.purple)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12)).foregroundColor(.gray)
            }
            .padding(14)
            .glassCard(color: .purple, intensity: 0.08)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - KPI Row

struct PSSKPIRow: View {
    let history: [PSSRecord]

    private var fullRecords: [PSSRecord] { history.filter { $0.type == "full" } }
    private var latest: PSSRecord? { fullRecords.first }
    private var previous: PSSRecord? { fullRecords.dropFirst().first }
    private var latestShort: PSSRecord? { history.first(where: { $0.type == "short" }) }
    private var streak: Int { history.first?.streak ?? 0 }

    private var delta: Int? {
        guard let l = latest, let p = previous else { return nil }
        return l.score - p.score
    }

    var body: some View {
        HStack(spacing: 10) {
            if let r = latest {
                let deltaStr: String = {
                    guard let d = delta else { return r.categoryLabel }
                    if d > 0 { return "↑ +\(d) vs mois passé" }
                    if d < 0 { return "↓ \(d) vs mois passé" }
                    return "─ stable"
                }()
                PSSKPICell(
                    value: "\(r.score)/40",
                    label: "PSS-10",
                    sublabel: deltaStr,
                    color: r.categoryColor
                )
            }
            if let r = latestShort {
                PSSKPICell(
                    value: "\(r.score)/16",
                    label: "PSS-4",
                    sublabel: r.categoryLabel,
                    color: r.categoryColor
                )
            }
            if streak >= 2 {
                PSSKPICell(
                    value: "×\(streak)",
                    label: "Régularité",
                    sublabel: streak >= 3 ? "Tracker régulier" : "Bonne cadence",
                    color: .yellow
                )
            }
        }
    }
}

struct PSSKPICell: View {
    let value: String
    let label: String
    let sublabel: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .black)).foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
            Text(sublabel)
                .font(.system(size: 9)).foregroundColor(.gray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCard(color: color, intensity: 0.05)
        .cornerRadius(12)
    }
}

// MARK: - History Row

struct PSSHistoryRow: View {
    let record: PSSRecord
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header tap pour expand
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    // Score ring mini
                    ZStack {
                        Circle()
                            .stroke(record.categoryColor.opacity(0.15), lineWidth: 5)
                            .frame(width: 44, height: 44)
                        Circle()
                            .trim(from: 0, to: CGFloat(record.score) / CGFloat(record.maxScore))
                            .stroke(record.categoryColor,
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 44)
                        Text("\(record.score)")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(record.categoryColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(record.categoryLabel)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(record.categoryColor)
                            Text(record.type == "full" ? "PSS-10" : "PSS-4")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.gray.opacity(0.12))
                                .cornerRadius(4)
                        }
                        Text(record.date)
                            .font(.system(size: 11)).foregroundColor(.gray)
                    }

                    Spacer()

                    if record.streak >= 3 {
                        Text("×\(record.streak)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.12))
                            .cornerRadius(4)
                    }

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            // Détails expandable
            if expanded {
                Divider().background(Color.white.opacity(0.06))
                VStack(alignment: .leading, spacing: 10) {
                    // Insights
                    ForEach(Array(record.insights.enumerated()), id: \.0) { _, insight in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").font(.system(size: 12)).foregroundColor(record.categoryColor)
                            Text(insight)
                                .font(.system(size: 12)).foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Notes
                    if let notes = record.notes, !notes.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "note.text")
                                .font(.system(size: 11)).foregroundColor(.blue)
                            Text(notes)
                                .font(.system(size: 12)).foregroundColor(.gray.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Déclencheurs
                    if !record.triggerRatings.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(record.triggerRatings.keys.sorted()), id: \.self) { key in
                                if let val = record.triggerRatings[key] {
                                    Text("\(key) : \(val)/4")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(5)
                                }
                            }
                        }
                    }
                }
                .padding([.horizontal, .bottom], 12)
            }
        }
        .background(Color(hex: "11111c"))
        .cornerRadius(12)
    }
}

// MARK: - Empty State

struct PSSEmptyState: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44)).foregroundColor(.purple.opacity(0.4))
            Text("Aucun bilan stress")
                .font(.system(size: 16, weight: .medium)).foregroundColor(.gray)
            Text("Le PSS-10 mesure ton niveau de stress perçu\ndu dernier mois (3 min).")
                .font(.system(size: 13)).foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
            Button(action: onStart) {
                Text("Commencer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Color.purple.opacity(0.7))
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Questionnaire Sheet

struct PSSQuestionnaireSheet: View {
    let isShort: Bool
    let onSaved: (PSSRecord?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var questions: [PSSQuestion] = []
    @State private var responses: [Int: Int] = [:]   // questionId → 0-4
    @State private var notes = ""
    @State private var triggerRatings: [String: Int] = [:]
    @State private var userTriggers: [String] = []   // max 2, chargés depuis UserDefaults
    @State private var currentPage = 0               // 0 = questionnaire, 1 = résultats
    @State private var submittedRecord: PSSRecord?
    @State private var isSaving = false
    @State private var isLoadingQ = true

    private let responseLabels = ["Jamais", "Presque\njamais", "Parfois", "Assez\nsouvent", "Très\nsouvent"]

    private var allAnswered: Bool {
        questions.allSatisfy { responses[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0C0C18").ignoresSafeArea()

                if isLoadingQ {
                    ProgressView().tint(.purple)
                } else if currentPage == 0 {
                    questionnaireBody
                } else {
                    resultsBody
                }
            }
            .navigationTitle(currentPage == 0 ? (isShort ? "PSS-4 rapide" : "PSS-10 complet") : "Résultats")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(.gray)
                }
            }
        }
        .task { await loadQuestions() }
    }

    // ── Questionnaire page ────────────────────────────────────────────────────

    private var questionnaireBody: some View {
        let answeredCount = questions.filter { responses[$0.id] != nil }.count
        let total = max(questions.count, 1)
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Progress bar
                VStack(spacing: 6) {
                    HStack {
                        Text("\(answeredCount) / \(questions.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.purple)
                        Spacer()
                        Text(answeredCount == questions.count ? "Prêt ✓" : "\(Int(Double(answeredCount) / Double(total) * 100))%")
                            .font(.system(size: 12))
                            .foregroundColor(answeredCount == questions.count ? .green : .gray)
                    }
                    ProgressView(value: Double(answeredCount), total: Double(total))
                        .tint(.purple)
                        .animation(.easeInOut(duration: 0.2), value: answeredCount)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

                // Intro
                VStack(spacing: 6) {
                    Text("Au cours du **dernier mois**…")
                        .font(.system(size: 14)).foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Text("Échelle 0 à 4")
                        .font(.system(size: 12)).foregroundColor(.gray.opacity(0.6))
                }
                .padding(.vertical, 12)

                // Questions
                ForEach(Array(questions.enumerated()), id: \.1.id) { idx, q in
                    PSSQuestionCard(
                        index: idx + 1,
                        question: q,
                        selected: responses[q.id],
                        labels: responseLabels
                    ) { val in
                        responses[q.id] = val
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .appearAnimation(delay: Double(idx) * 0.04)
                }

                // Déclencheurs (si configurés)
                if !userTriggers.isEmpty {
                    TriggerRatingSection(
                        triggers: userTriggers,
                        ratings: $triggerRatings
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                // Bouton soumettre
                VStack(spacing: 10) {
                    if !allAnswered {
                        Text("Réponds à toutes les questions pour continuer")
                            .font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Button(action: submitQuestionnaire) {
                        HStack(spacing: 8) {
                            if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                            Text(isSaving ? "Calcul…" : "Calculer mon score")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(allAnswered ? Color.purple : Color.gray.opacity(0.3))
                        .cornerRadius(14)
                    }
                    .disabled(!allAnswered || isSaving)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // ── Résultats page ────────────────────────────────────────────────────────

    private var resultsBody: some View {
        Group {
            if let record = submittedRecord {
                PSSResultsContent(record: record, notes: $notes, onFinish: {
                    Task { await onSaved(submittedRecord); dismiss() }
                })
            } else {
                ProgressView().tint(.purple)
            }
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    private func loadQuestions() async {
        isLoadingQ = true
        questions = (try? await APIService.shared.fetchPSSQuestions(isShort: isShort)) ?? []
        userTriggers = (UserDefaults.standard.array(forKey: "pss_triggers") as? [String]) ?? []
        isLoadingQ = false
    }

    private func submitQuestionnaire() {
        guard allAnswered else { return }
        isSaving = true

        let orderedResponses = questions.map { responses[$0.id] ?? 0 }
        let ratings = triggerRatings.isEmpty ? [:] : triggerRatings

        Task {
            do {
                let record = try await APIService.shared.submitPSS(
                    responses:      orderedResponses,
                    isShort:        isShort,
                    notes:          notes.isEmpty ? nil : notes,
                    triggers:       userTriggers,
                    triggerRatings: ratings
                )
                submittedRecord = record
                withAnimation { currentPage = 1 }
            } catch {
                print("[PSS] submit error: \(error)")
            }
            isSaving = false
        }
    }
}

// MARK: - Results Content

struct PSSResultsContent: View {
    let record: PSSRecord
    @Binding var notes: String
    let onFinish: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                PSSScoreRing(record: record)
                    .padding(.horizontal, 24)
                    .appearAnimation(delay: 0.05)

                insightsSection

                // Breathwork CTA for non-low scores
                if record.category != "low" {
                    NavigationLink { BreathworkView() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lungs.fill").font(.system(size: 16)).foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Décompresser maintenant")
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                Text("Cohérence cardiaque · 5 min recommandées")
                                    .font(.system(size: 12)).foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.gray)
                        }
                        .padding(14)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .appearAnimation(delay: 0.13)
                }

                notesSection

                Button("Terminer", action: onFinish)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple.opacity(0.7))
                    .cornerRadius(14)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                    .appearAnimation(delay: 0.18)
            }
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANALYSE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            ForEach(Array(record.insights.enumerated()), id: \.0) { _, insight in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11)).foregroundColor(.yellow)
                    Text(insight)
                        .font(.system(size: 13)).foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.white.opacity(0.03))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .appearAnimation(delay: 0.1)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE OPTIONNELLE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            TextField("Qu'est-ce qui t'a aidé ou stressé ce mois-ci ?", text: $notes, axis: .vertical)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .lineLimit(3...5)
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .appearAnimation(delay: 0.14)
    }
}

// MARK: - Question Card

struct PSSQuestionCard: View {
    let index: Int
    let question: PSSQuestion
    let selected: Int?
    let labels: [String]
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            questionHeader
            selectorRow
        }
        .padding(14)
        .background(Color(hex: "11111c"))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected != nil ? Color.purple.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    private var questionHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.purple)
                .frame(width: 18, height: 18)
                .background(Color.purple.opacity(0.12))
                .clipShape(Circle())
            Text(question.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectorRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { val in
                PSSResponseButton(val: val, label: labels[val], isSelected: selected == val) {
                    withAnimation(.easeInOut(duration: 0.15)) { onSelect(val) }
                }
            }
        }
    }
}

struct PSSResponseButton: View {
    let val: Int
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("\(val)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isSelected ? .white : .gray.opacity(0.6))
                Text(label)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .gray.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.purple.opacity(0.7) : Color.white.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trigger Rating Section

struct TriggerRatingSection: View {
    let triggers: [String]
    @Binding var ratings: [String: Int]

    private let labels = ["Jamais", "Rarement", "Parfois", "Souvent", "Très souvent"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MES DÉCLENCHEURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            ForEach(triggers, id: \.self) { trigger in
                VStack(alignment: .leading, spacing: 8) {
                    Text("« \(trigger) » t'a stressé(e) ce mois-ci ?")
                        .font(.system(size: 13)).foregroundColor(.white)
                    HStack(spacing: 4) {
                        ForEach(0..<5) { val in
                            Button {
                                ratings[trigger] = val
                            } label: {
                                VStack(spacing: 3) {
                                    Text("\(val)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(ratings[trigger] == val ? .white : .gray.opacity(0.5))
                                    Text(labels[val])
                                        .font(.system(size: 7))
                                        .foregroundColor(ratings[trigger] == val ? .white.opacity(0.7) : .gray.opacity(0.4))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(ratings[trigger] == val ? Color.orange.opacity(0.6) : Color.white.opacity(0.04))
                                .cornerRadius(7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "11111c"))
        .cornerRadius(12)
    }
}

// MARK: - Score Ring (résultats)

struct PSSScoreRing: View {
    let record: PSSRecord

    private var pct: Double { Double(record.score) / Double(record.maxScore) }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(record.categoryColor.opacity(0.12), lineWidth: 16)
                    .frame(width: 140, height: 140)
                Circle()
                    .trim(from: 0, to: CGFloat(pct))
                    .stroke(record.categoryColor,
                            style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 140, height: 140)
                    .animation(.easeOut(duration: 1.0), value: pct)
                VStack(spacing: 4) {
                    Text("\(record.score)")
                        .font(.system(size: 44, weight: .black))
                        .foregroundColor(record.categoryColor)
                    Text("/ \(record.maxScore)")
                        .font(.system(size: 14)).foregroundColor(.gray)
                }
            }

            VStack(spacing: 4) {
                Text(record.categoryLabel)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(record.categoryColor)
                Text(record.type == "full" ? "PSS-10" : "PSS-4")
                    .font(.system(size: 12)).foregroundColor(.gray)
                if record.streak >= 3 {
                    HStack(spacing: 4) {
                        Image(systemName: "medal.fill").foregroundColor(.yellow)
                        Text("Tracker régulier ×\(record.streak)")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.yellow)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(color: record.categoryColor, intensity: 0.06)
        .cornerRadius(20)
    }
}

// MARK: - LSS Compact Card

struct LSSCompactCard: View {
    let lss: LifeStressScore
    let trend: [LifeStressScore]

    private var scoreColor: Color {
        switch lss.score {
        case 80...: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default:      return .red
        }
    }

    private var scoreLabel: String {
        switch lss.score {
        case 80...: return "Faible"
        case 60..<80: return "Modéré"
        case 40..<60: return "Élevé"
        default:      return "Critique"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                // Score
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(scoreColor.opacity(0.15), lineWidth: 4)
                            .frame(width: 44, height: 44)
                        Circle()
                            .trim(from: 0, to: CGFloat(lss.score) / 100)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 44)
                        Text("\(Int(lss.score))")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(scoreColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stress \(scoreLabel)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(scoreColor)
                        Text("Score de stress LSS · automatique")
                            .font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
                Spacer()
            }

            // Components row
            HStack(spacing: 12) {
                if let sleep = lss.components.sleepQuality {
                    LSSComponentPill(icon: "moon.fill", color: .indigo, label: "Sommeil", value: Int(sleep))
                }
                if let hrv = lss.components.hrvTrend {
                    LSSComponentPill(icon: "waveform.path.ecg", color: .green, label: "HRV", value: Int(hrv))
                }
                if let fat = lss.components.trainingFatigue {
                    LSSComponentPill(icon: "bolt.fill", color: .orange, label: "Fatigue", value: Int(fat))
                }
            }

            if !lss.recommendations.isEmpty {
                Text(lss.recommendations[0])
                    .font(.system(size: 12)).foregroundColor(.gray)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .glassCard(color: scoreColor, intensity: 0.05)
        .cornerRadius(14)
    }
}

struct LSSComponentPill: View {
    let icon: String
    let color: Color
    let label: String
    let value: Int

    private var pillColor: Color {
        switch value {
        case 70...: return .green
        case 45..<70: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(color)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(.gray)
            Text("\(value)").font(.system(size: 9, weight: .bold)).foregroundColor(pillColor)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(color.opacity(0.08))
        .cornerRadius(6)
    }
}

// MARK: - PSS Trend Chart

struct PSSTrendChart: View {
    let records: [PSSRecord]  // filtered full records, most-recent first

    // Reverse so oldest is left, newest is right
    private var sorted: [PSSRecord] {
        records.prefix(8).reversed().map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TENDANCE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            Chart {
                ForEach(sorted) { record in
                    LineMark(
                        x: .value("Date", record.date),
                        y: .value("Score", record.score)
                    )
                    .foregroundStyle(Color.purple.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", record.date),
                        y: .value("Score", record.score)
                    )
                    .foregroundStyle(record.categoryColor)
                    .symbolSize(40)
                }
            }
            .chartYScale(domain: 0...40)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 13, 26, 40]) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                    AxisValueLabel()
                        .font(.system(size: 9))
                        .foregroundStyle(Color.gray)
                }
            }
            .frame(height: 80)

            // Zone labels
            HStack {
                Text("Faible ≤13").font(.system(size: 9)).foregroundColor(.green)
                Spacer()
                Text("Modéré ≤26").font(.system(size: 9)).foregroundColor(.orange)
                Spacer()
                Text("Élevé ≤40").font(.system(size: 9)).foregroundColor(.red)
            }
        }
        .padding(14)
        .glassCard(color: .purple, intensity: 0.04)
        .cornerRadius(14)
    }
}
