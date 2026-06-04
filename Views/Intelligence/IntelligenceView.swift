import SwiftUI
import Combine
import OSLog

private let logger = Logger(subsystem: "TrainingOS", category: "Intelligence")

struct IntelligenceView: View {
    @State private var messages: [ChatMessage] = []
    @AppStorage("intelligence_history") private var historyData: String = "[]"
    @State private var input = ""
    @State private var isLoading = false
    @State private var showPropose = false
    @State private var proposals: [AIProposal] = []
    @State private var isLoadingProposals = false
    @State private var correlations: CorrelationsData? = nil
    @State private var isLoadingCorrelations = false
    @State private var showInsights = false
    @ObservedObject private var api   = APIService.shared
    @ObservedObject private var units = UnitSettings.shared
    @State private var narrative:        String?                  = nil
    @State private var isLoadingNarrative = false
    @State private var recoveryData:    [RecoveryEntry]          = []
    @State private var weightsData:     [String: WeightData]     = [:]
    @State private var bodyWeightData:  [BodyWeightEntry]        = []
    @State private var muscleStatsData: [String: MuscleStatEntry] = [:]
    @State private var sessionsData:    [String: SessionEntry]   = [:]
    @State private var acwrData:        ACWRData?                = nil
    @State private var lssData:         LifeStressScore?         = nil
    @State private var proposalError:   String?                  = nil
    @State private var generatedProgram: GeneratedProgram?       = nil
    @State private var isGeneratingProgram                       = false
    @State private var showProgramPreview                        = false
    @State private var programError:    String?                  = nil
    @State private var selectedSection: CoachSection = .chat
    @ObservedObject private var memoryStore = CoachMemoryStore.shared
    @State private var nutritionHistory: [NutritionDayHistory]  = []
    @State private var showNutritionInsight                     = true
    @State private var weeklyReportData: WeeklyReport?          = nil
    @State private var showWeeklyReport                         = false
    @State private var isLoadingWeeklyReport                    = false
    @State private var dailyInsight: DailyInsight? = nil
    @State private var isLoadingInsight = false
    @State private var postSessionData: PostSessionData? = nil
    @AppStorage("post_session_logged_at") private var postSessionLoggedAt: String = ""
    @State private var cardioData: [CardioEntry] = []
    @State private var mesocycleInfo: MesocycleInfo? = nil
    @State private var mentalData: MentalHealthSummary? = nil
    @State private var userHasInteracted = false  // gates auto-scroll; set only when user sends a message

    // New intelligence features
    @State private var overtrainingRisk: OvertrainingRisk? = nil
    @State private var mesocycleStatus: MesocycleStatus? = nil
    @State private var painJournal: PainJournalResponse? = nil
    @State private var oneRMData: OneRMResponse? = nil
    @State private var isLoadingOvertraining = false

    // Pattern engine
    @State private var patternData: PatternResponse? = nil
    @State private var isLoadingPatterns = false
    @State private var expandedBilan: Set<String> = []

    // Tab-switch callback injected from ContentView
    var onOpenSession: (() -> Void)? = nil

    private var todayRecovery: RecoveryEntry? { recoveryData.first }

    private var shouldShowPostSeanceCard: Bool {
        guard let loggedAt = ISO8601DateFormatter().date(from: postSessionLoggedAt) else { return false }
        return Date().timeIntervalSince(loggedAt) < 7200
    }

    // Bilan hero stats (last 7 days)
    private var bilanRecentSessions: [SessionEntry] {
        let cutoff = DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 7 * 86400))
        return sessionsData.filter { $0.key >= cutoff }.map { $0.value }
    }
    private var bilanSessionCount: Int { bilanRecentSessions.count }
    private var bilanAvgRpe: Double? {
        let vals = bilanRecentSessions.compactMap { $0.rpe }.filter { $0 > 0 }
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }
    private var bilanRestDays: Int { max(0, 7 - bilanSessionCount) }
    private var bilanTotalVolume: Double { bilanRecentSessions.compactMap { $0.sessionVolume }.reduce(0, +) }

    // MARK: - Section Navigation

    private enum CoachSection: String, CaseIterable {
        case chat      = "Chat"
        case patterns  = "Patterns"
        case programme = "Programme"
        case bilan     = "Bilan"
        case memoire   = "Mémoire"

        var icon: String {
            switch self {
            case .chat:      return "bubble.left.and.bubble.right.fill"
            case .patterns:  return "chart.dots.scatter"
            case .programme: return "calendar.badge.plus"
            case .bilan:     return "chart.bar.doc.horizontal"
            case .memoire:   return "brain.head.profile"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header: greeting + context + optional CTA
                    if let dash = api.dashboard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                CoachGreetingHeader(dash: dash)
                                Spacer()
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { selectedSection = .memoire }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 13, weight: .semibold))
                                        if !memoryStore.entries.isEmpty {
                                            Text("\(memoryStore.entries.count)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.purple)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .foregroundColor(.purple)
                                }
                            }
                            CoachContextSummary(
                                lssData: lssData,
                                dashboard: api.dashboard,
                                nutritionHistory: nutritionHistory
                            )
                            if !dash.alreadyLoggedToday {
                                Button(action: { onOpenSession?() }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Commencer la séance")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    } else {
                        VStack(spacing: 8) {
                            SkeletonBar(height: 36, radius: 8)
                            SkeletonBar(height: 60, radius: 10)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }

                    // Section content
                    if selectedSection == .chat {
                        chatSectionView
                    } else if selectedSection == .patterns {
                        ScrollView(showsIndicators: false) {
                            summaryCardsView
                            patternsSectionView
                        }
                    } else if selectedSection == .programme {
                        ScrollView(showsIndicators: false) {
                            summaryCardsView
                            programmeSectionView
                        }
                    } else if selectedSection == .bilan {
                        ScrollView(showsIndicators: false) {
                            summaryCardsView
                            bilanSectionView
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            summaryCardsView
                            memoireSectionView
                        }
                    }

                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider().background(Color.white.opacity(0.08))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CoachSection.allCases, id: \.self) { section in
                                    Button {
                                        hideKeyboard()
                                        withAnimation(.easeInOut(duration: 0.2)) { selectedSection = section }
                                    } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: section.icon)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(section.rawValue)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        selectedSection == section
                                            ? Color.purple.opacity(0.22)
                                            : Color.white.opacity(0.06)
                                    )
                                    .foregroundColor(
                                        selectedSection == section ? .purple : Color(white: 0.55)
                                    )
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(
                                            selectedSection == section
                                                ? Color.purple.opacity(0.45)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 8)
                    .background(Color.appBg)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Chat always starts empty — no history restore
                messages = []
                historyData = "[]"
                if api.dashboard == nil { await api.fetchDashboard() }
                Task { generatedProgram = try? await APIService.shared.fetchLatestGeneratedProgram() }
                await loadContextData()
                await MainActor.run { purgeStaleMemoryEntries() }
                Task { await loadDailyInsight() }
                // Post-séance: if session already logged, ensure timestamp is set for today
                if api.dashboard?.alreadyLoggedToday == true {
                    let today = DateFormatter.isoDate.string(from: Date())
                    if String(postSessionLoggedAt.prefix(10)) != today {
                        postSessionLoggedAt = ISO8601DateFormatter().string(from: Date())
                    }
                    if shouldShowPostSeanceCard { Task { await loadPostSession() } }
                }
            }
            .onChange(of: api.dashboard?.alreadyLoggedToday) { oldVal, newVal in
                if newVal == true && oldVal != true {
                    postSessionLoggedAt = ISO8601DateFormatter().string(from: Date())
                    Task { await loadPostSession() }
                }
            }
            .onChange(of: messages) {
                let toSave = messages.filter { !$0.content.hasPrefix("Erreur:") }
                if let data = try? JSONEncoder().encode(Array(toSave.suffix(50))),
                   let str = String(data: data, encoding: .utf8) {
                    historyData = str
                }
            }
            .fullScreenCover(isPresented: $showProgramPreview) {
                if let gp = generatedProgram {
                    ProgramPreviewSheet(program: gp) { _ in
                        showProgramPreview = false
                        var updated = gp
                        updated.status = .active
                        generatedProgram = updated
                    } onReject: {
                        showProgramPreview = false
                        generatedProgram = nil
                    }
                }
            }
            .sheet(isPresented: $showWeeklyReport) {
                if let r = weeklyReportData {
                    NavigationStack {
                        WeeklyReportView(report: r)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Fermer") { showWeeklyReport = false }.foregroundColor(.white)
                                }
                            }
                    }
                    .preferredColorScheme(.dark)
                    .presentationDetents([.large])
                }
            }
        }
    }
    }

    // MARK: - Section Views

    @ViewBuilder
    private var summaryCardsView: some View {
        if let insight = dailyInsight, !insight.isEmpty {
            InsightPrincipalCard(
                insight: insight,
                onNavigateToProgramme: {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedSection = .programme }
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        } else if isLoadingInsight {
            SkeletonBar(height: 90, radius: 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        if shouldShowPostSeanceCard, let psd = postSessionData {
            PostSeanceCard(data: psd)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        if !weightsData.isEmpty {
            ProgressionCard(
                weightsData: weightsData,
                goal: api.dashboard?.profile.goal
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var chatSectionView: some View {
        VStack(spacing: 0) {
            ChatPanel(
                messages: $messages,
                input: $input,
                isLoading: $isLoading,
                userHasInteracted: $userHasInteracted,
                sendMessage: sendMessage,
                chips: {
                    QuestionChipsView(
                        lssData: lssData,
                        dashboard: api.dashboard,
                        nutritionHistory: nutritionHistory,
                        onTap: { sendQuery($0) }
                    )
                }
            ) {
                TopicExplorer { q in sendQuery(q) }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
            }
        }
        .animation(.easeOut(duration: 0.25), value: messages.isEmpty)
    }

    @ViewBuilder
    private var patternsSectionView: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Plateau Detection ─────────────────────────────────────────────
            PlateauSection()
                .background(Color.appCard)
                .cornerRadius(14)
                .padding(.horizontal, 16)

            // ── Workout DNA ───────────────────────────────────────────────────
            WorkoutDNASection()
                .background(Color.appCard)
                .cornerRadius(14)
                .padding(.horizontal, 16)

            // ── Pattern du jour ───────────────────────────────────────────────
            if isLoadingPatterns {
                PatternCardSkeleton()
                    .padding(.horizontal, 16)
            } else if let daily = patternData?.daily {
                PatternDailyCard(pattern: daily) {
                    Task { await togglePin(pattern: daily) }
                }
                .padding(.horizontal, 16)

                if daily.family == "C", daily.macroThreshold != nil {
                    MacroThresholdDetail(pattern: daily)
                        .padding(.horizontal, 16)
                }
            } else if patternData != nil {
                // No daily pattern (data insufficient)
                HStack(spacing: 8) {
                    Image(systemName: "chart.dots.scatter")
                        .foregroundColor(.purple.opacity(0.5))
                    Text("Pas encore assez de données — reviens dans quelques semaines.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.45))
                }
                .padding(.horizontal, 16)
            }

            // ── Patterns suivis (pinned) ───────────────────────────────────
            if let pinned = patternData?.pinned, !pinned.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.purple)
                        Text("MES PATTERNS SUIVIS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(white: 0.45))
                    }
                    .padding(.horizontal, 16)

                    ForEach(pinned) { pattern in
                        PatternPinnedChip(pattern: pattern) {
                            Task { await unpin(pattern: pattern) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }

            // ── Time Capsule ──────────────────────────────────────────────
            TimeCapsuleSection()
                .background(Color.appCard)
                .cornerRadius(14)
                .padding(.horizontal, 16)

            // ── Corrélations rapides (existing engine) ────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("CORRÉLATIONS GLOBALES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                    .padding(.horizontal, 16)

                if isLoadingCorrelations {
                    SkeletonBar(height: 100, radius: 14).padding(.horizontal, 16)
                } else if let corr = correlations {
                    InsightsCard(data: corr, onDismiss: { correlations = nil; showInsights = false })
                        .padding(.horizontal, 16)
                } else {
                    Button { loadInsights() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.dots.scatter").font(.system(size: 13))
                            Text("Analyser les corrélations").font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.purple.opacity(0.10))
                        .foregroundColor(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
        .onAppear {
            if patternData == nil && !isLoadingPatterns { loadPatterns() }
            if correlations == nil && !isLoadingCorrelations { loadInsights() }
        }
    }

    private func loadPatterns() {
        guard !isLoadingPatterns else { return }
        isLoadingPatterns = true
        Task {
            let result = try? await APIService.shared.fetchPatterns()
            await MainActor.run {
                patternData      = result
                isLoadingPatterns = false
            }
        }
    }

    private func togglePin(pattern: PatternEntry) async {
        do {
            if pattern.pinned {
                try await APIService.shared.unpinPattern(id: pattern.id)
            } else {
                try await APIService.shared.pinPattern(id: pattern.id)
            }
            let refreshed = try? await APIService.shared.fetchPatterns()
            await MainActor.run { patternData = refreshed }
        } catch {
            logger.error("togglePin error: \(error)")
        }
    }

    private func unpin(pattern: PatternEntry) async {
        do {
            try await APIService.shared.unpinPattern(id: pattern.id)
            let refreshed = try? await APIService.shared.fetchPatterns()
            await MainActor.run { patternData = refreshed }
        } catch {
            logger.error("unpin error: \(error)")
        }
    }

    @ViewBuilder
    private var programmeSectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let meso = mesocycleInfo {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MÉSOCYCLE ACTIF")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("S\(meso.week)/8")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            Text(meso.phase)
                                .font(.system(size: 13))
                                .foregroundColor(.purple)
                        }
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 1, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("RPE cible")
                                .font(.system(size: 11))
                                .foregroundColor(Color(white: 0.5))
                            Text(meso.rpeTarget)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        if !meso.note.isEmpty {
                            Spacer()
                            Text(meso.note)
                                .font(.system(size: 12))
                                .foregroundColor(Color(white: 0.5))
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }

            if generatedProgram != nil && !isGeneratingProgram {
                Button { showProgramPreview = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 13))
                        Text("Voir le dernier programme généré")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.4))
                    }
                    .padding(14)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
            }

            if !proposals.isEmpty {
                ProposalsCard(proposals: proposals, onDismiss: { proposals = []; proposalError = nil })
                    .padding(.horizontal, 16)
            }

            if let err = proposalError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    Text(err).font(.system(size: 12)).foregroundColor(.gray)
                    Spacer()
                    Button { proposalError = nil } label: {
                        Image(systemName: "xmark").foregroundColor(.gray)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
            }

            if let err = programError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    Text(err).font(.system(size: 12)).foregroundColor(.gray)
                    Spacer()
                    Button { programError = nil } label: {
                        Image(systemName: "xmark").foregroundColor(.gray)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                Button { loadProposals() } label: {
                    HStack(spacing: 6) {
                        if isLoadingProposals {
                            ProgressView().tint(.purple).scaleEffect(0.75)
                        } else {
                            Image(systemName: "wand.and.stars").font(.system(size: 13))
                        }
                        Text("Propositions").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isLoadingProposals)

                Button { generateProgram() } label: {
                    HStack(spacing: 6) {
                        if isGeneratingProgram {
                            ProgressView().tint(.blue).scaleEffect(0.75)
                        } else {
                            Image(systemName: "calendar.badge.plus").font(.system(size: 13))
                        }
                        Text("Générer").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isGeneratingProgram)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var bilanSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {

            // NIVEAU 1 — Hero résumé 7 jours
            bilanHeroCard
                .padding(.horizontal, 16)

            // NIVEAU 2 — Signaux (chips)
            bilanSignauxStrip

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            // NIVEAU 3a — Récit IA (accordion)
            bilanAccordionRow(id: "recit", icon: "text.quote", label: "Récit IA", accent: .teal) {
                if isLoadingNarrative {
                    SkeletonBar(height: 80, radius: 12).padding(.horizontal, 16).padding(.bottom, 4)
                } else if let text = narrative {
                    NarrativeCard(text: text, onDismiss: { narrative = nil }).padding(.horizontal, 16).padding(.bottom, 4)
                } else {
                    Text("Aucun récit généré pour cette semaine.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.45))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }

            // NIVEAU 3b — Analyses (accordion)
            bilanAccordionRow(id: "analyses", icon: "chart.dots.scatter", label: "Analyses", accent: .purple) {
                if let dash = api.dashboard {
                    SmartInsightsSection(
                        dash: dash, weightsData: weightsData, sessionsData: sessionsData,
                        recovery: todayRecovery, recoveryLog: recoveryData,
                        nutritionHistory: nutritionHistory
                    )
                    .padding(.horizontal, 16)
                }
                if let risk = overtrainingRisk {
                    OvertrainingRiskCard(risk: risk).padding(.horizontal, 16)
                }
                if let meso = mesocycleStatus {
                    MesocycleStatusCard(status: meso).padding(.horizontal, 16)
                }
                if let pain = painJournal, !pain.byExercise.isEmpty {
                    PainJournalCard(data: pain).padding(.horizontal, 16)
                }
                if let oneRM = oneRMData, !oneRM.exercises.isEmpty {
                    OneRMProgrammingCard(data: oneRM).padding(.horizontal, 16)
                }
                if overtrainingRisk == nil && mesocycleStatus == nil {
                    Text("Chargement des analyses…")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.45))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }

            // Bilan complet — accès direct au rapport
            Button { openWeeklyReport() } label: {
                HStack(spacing: 10) {
                    if isLoadingWeeklyReport {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 14))
                    }
                    Text("Bilan de la semaine").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(Color.white.opacity(0.05))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
            .disabled(isLoadingWeeklyReport)
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
        .onAppear {
            if narrative == nil && !isLoadingNarrative { loadNarrative() }
            if overtrainingRisk == nil { Task { await loadIntelligenceFeatures() } }
        }
    }

    @ViewBuilder
    private var bilanHeroCard: some View {
        let sessionCount = bilanSessionCount
        let restDays = bilanRestDays
        let avgRpe = bilanAvgRpe
        let totalVol = bilanTotalVolume
        VStack(alignment: .leading, spacing: 10) {
            Text("SEMAINE EN COURS")
                .font(.system(size: 10, weight: .black))
                .tracking(1.2)
                .foregroundColor(Color(white: 0.45))
            HStack(spacing: 0) {
                bilanStatCell(value: "\(sessionCount)", label: "séances")
                Divider().frame(height: 36).background(Color.white.opacity(0.1))
                bilanStatCell(value: restDays == 0 ? "—" : "\(restDays)", label: "repos")
                if let rpe = avgRpe {
                    Divider().frame(height: 36).background(Color.white.opacity(0.1))
                    bilanStatCell(value: String(format: "%.1f", rpe), label: "RPE moy")
                }
                if totalVol > 0 {
                    Divider().frame(height: 36).background(Color.white.opacity(0.1))
                    bilanStatCell(value: _formatK(units.display(totalVol)), label: "\(units.label) vol")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func bilanStatCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.45))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var bilanSignauxStrip: some View {
        let acwr = acwrData
        let risk = overtrainingRisk
        let meso = mesocycleStatus
        if acwr != nil || risk != nil || meso != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let a = acwr {
                        bilanSignalChip(
                            icon: "figure.run",
                            label: "ACWR \(String(format: "%.2f", a.ratio))",
                            color: acwrZoneColor(a.zone.color)
                        )
                    }
                    if let r = risk {
                        let label = r.level == "low" ? "Charge OK" : r.level == "moderate" ? "Surcharge mod." : "Surcharge élevée"
                        let color: Color = r.level == "low" ? .green : r.level == "moderate" ? .orange : .red
                        bilanSignalChip(
                            icon: r.level == "low" ? "checkmark.circle" : "exclamationmark.triangle",
                            label: label, color: color
                        )
                    }
                    if let m = meso {
                        bilanSignalChip(
                            icon: m.icon.isEmpty ? "calendar" : m.icon,
                            label: "S\(m.weekInCycle) — \(m.phaseLabel)",
                            color: .purple
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func bilanSignalChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func bilanAccordionRow<C: View>(
        id: String, icon: String, label: String, accent: Color,
        @ViewBuilder content: () -> C
    ) -> some View {
        let isExpanded = expandedBilan.contains(id)
        VStack(spacing: 0) {
            Button {
                let expanding = !expandedBilan.contains(id)
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedBilan.contains(id) { expandedBilan.remove(id) }
                    else { expandedBilan.insert(id) }
                }
                if expanding && id == "recit" && narrative == nil && !isLoadingNarrative {
                    loadNarrative()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 20)
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func acwrZoneColor(_ colorStr: String) -> Color {
        switch colorStr {
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        default:       return .gray
        }
    }

    @ViewBuilder
    private var memoireSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if memoryStore.entries.isEmpty {
                Text("Aucune mémoire enregistrée.\nLe coach apprend tes patterns au fil des semaines.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .padding(.horizontal, 16)
            } else {
                Text("MÉMOIRE DU COACH")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                    .padding(.horizontal, 16)

                ForEach(memoryStore.entries, id: \.id) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.type.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.purple)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.type.rawValue)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.purple.opacity(0.7))
                            Text(entry.content)
                                .font(.system(size: 13))
                                .foregroundColor(Color(white: 0.82))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button {
                            withAnimation { CoachMemoryStore.shared.delete(id: entry.id) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundColor(Color(white: 0.3))
                                .padding(6)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }
            }

            if !messages.isEmpty {
                Button(role: .destructive) {
                    messages = []
                    historyData = "[]"
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 13))
                        Text("Effacer la conversation").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }


    // MARK: - Nutrition × Performance Insight

    private var iso14DaysAgo: String {
        DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 14 * 86400))
    }

    private var nutritionPerfInsight: NutritionPerfInsight? {
        guard let ns = api.dashboard?.nutritionSettings,
              let calTarget = ns.calories, calTarget > 0,
              nutritionHistory.count >= 5 else { return nil }

        let recent = Array(nutritionHistory.suffix(7))
        let avgCal  = recent.map { $0.calories }.reduce(0, +) / Double(recent.count)
        let avgProt = recent.map { $0.proteines }.reduce(0, +) / Double(recent.count)
        let calRatio = avgCal / calTarget

        // 1. Protein deficit + high session volume
        if let protTarget = ns.proteines, protTarget > 0, avgProt < protTarget * 0.78 {
            let sessions14d = sessionsData.filter { $0.key >= iso14DaysAgo }.count
            if sessions14d >= 5 {
                return NutritionPerfInsight(
                    kind: .proteinVolume,
                    title: "Protéines insuffisantes vs volume",
                    detail: "Moy. \(Int(avgProt))g/j — objectif \(Int(protTarget))g (\(Int(avgProt / protTarget * 100))%) · \(sessions14d) séances en 14j",
                    actionHint: "Augmenter les protéines réduit le catabolisme lors d'un volume élevé."
                )
            }
        }

        // 2. Caloric deficit + lift stagnation
        if calRatio < 0.87 {
            let hasProgress = weightsData.values.contains { wd in
                guard let hist = wd.history, hist.count >= 2 else { return false }
                let w14 = hist.filter { ($0.date ?? "") >= iso14DaysAgo }.sorted { ($0.date ?? "") < ($1.date ?? "") }
                guard w14.count >= 2 else { return false }
                return (w14.last?.weight ?? 0) > (w14.first?.weight ?? 0)
            }
            if !hasProgress {
                return NutritionPerfInsight(
                    kind: .deficitStagnation,
                    title: "Déficit calorique + stagnation des charges",
                    detail: "Moy. \(Int(avgCal)) kcal/j (\(Int(calRatio * 100))% de l'objectif) · aucune progression en 14j",
                    actionHint: "Un déficit prolongé sans progression signale un risque de catabolisme musculaire."
                )
            }
        }

        // 3. Caloric deficit + HRV decline
        if calRatio < 0.85 {
            let hrvValues = recoveryData.compactMap { $0.hrv }
            if hrvValues.count >= 10 {
                let avgRecent = hrvValues.prefix(7).reduce(0, +) / 7.0
                let avgPrev   = Array(hrvValues.dropFirst(7).prefix(7)).reduce(0, +) / 7.0
                if avgPrev > 0 && avgRecent < avgPrev * 0.88 {
                    let drop = Int((1 - avgRecent / avgPrev) * 100)
                    return NutritionPerfInsight(
                        kind: .deficitFatigue,
                        title: "Déficit calorique + HRV en baisse",
                        detail: "Moy. \(Int(avgCal)) kcal/j (\(Int(calRatio * 100))%) · HRV −\(drop)% sur 7j",
                        actionHint: "Déficit + HRV bas = stress systémique. Considérer un jour de repos ou plus de calories."
                    )
                }
            }
        }

        return nil
    }

    // Subset of stats_data cache fields we need
    private struct StatsSnapshot: Codable {
        let weights:     [String: WeightData]
        let sessions:    [String: SessionEntry]
        let bodyWeight:  [BodyWeightEntry]
        let recoveryLog: [RecoveryEntry]
        let muscleStats: [String: MuscleStatEntry]
        enum CodingKeys: String, CodingKey {
            case weights, sessions
            case bodyWeight  = "body_weight"
            case recoveryLog = "recovery_log"
            case muscleStats = "muscle_stats"
        }
    }

    private func loadDailyInsight() async {
        await MainActor.run { isLoadingInsight = true }
        do {
            let insight = try await APIService.shared.fetchDailyInsight()
            await MainActor.run { dailyInsight = insight; isLoadingInsight = false }
        } catch {
            await MainActor.run { isLoadingInsight = false }
        }
    }

    private func loadPostSession() async {
        guard shouldShowPostSeanceCard else { return }
        do {
            let data = try await APIService.shared.fetchPostSession()
            await MainActor.run { postSessionData = data }
        } catch { }
    }

    private func loadContextData() async {
        // 1. Prefer stats_data cache (already warm if StatsView was visited)
        if let cached  = CacheService.shared.load(for: "stats_data"),
           let decoded = try? APIService.decoder.decode(StatsSnapshot.self, from: cached) {
            await MainActor.run {
                recoveryData    = decoded.recoveryLog
                weightsData     = decoded.weights
                bodyWeightData  = decoded.bodyWeight
                muscleStatsData = decoded.muscleStats
                sessionsData    = decoded.sessions
            }
        } else {
            // Parallel via withTaskGroup — safe on iOS 26 beta (async let has LIFO crash).
            // @MainActor in each task: network awaits yield the actor, fetches run concurrently.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    self.recoveryData = (try? await APIService.shared.fetchRecoveryData()) ?? []
                }
                group.addTask { @MainActor in
                    self.weightsData = (try? await APIService.shared.fetchWeights()) ?? [:]
                }
            }
        }

        // 2+3: ACWR, LSS, nutrition, cardio, mesocycle, mental — all parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                self.acwrData = try? await APIService.shared.fetchACWR()
            }
            group.addTask { @MainActor in
                self.lssData = try? await APIService.shared.fetchLifeStressScore()
            }
            group.addTask { @MainActor in
                if let h = try? await APIService.shared.fetchNutritionHistory(), !h.isEmpty {
                    self.nutritionHistory = h
                    self.showNutritionInsight = true
                }
            }
            group.addTask { @MainActor in
                if let c = try? await APIService.shared.fetchCardioData() { self.cardioData = c }
            }
            group.addTask { @MainActor in
                if let m = (try? await APIService.shared.fetchSeanceData())?.mesocycle { self.mesocycleInfo = m }
            }
            group.addTask { @MainActor in
                if let m = try? await APIService.shared.fetchMentalHealthSummary(days: 7) { self.mentalData = m }
            }
        }

        // 4. Weekly memory auto-analysis (no-op if run < 7 days ago)
        let snap = await MainActor.run {
            (sessions: sessionsData,
             recovery: recoveryData,
             weights:  weightsData,
             goals:    api.dashboard?.goals ?? [:])
        }
        CoachMemoryStore.shared.runAnalysisIfNeeded(
            sessions:     snap.sessions,
            recovery:     snap.recovery,
            weights:      snap.weights,
            goals:        snap.goals,
            correlations: correlations?.insights ?? []
        )
    }

    private func buildContext() -> String {
        guard let dash = api.dashboard else { return "no data" }
        var lines: [String] = []

        // Coach memory — injected first for maximum AI attention
        let memBlock = CoachMemoryStore.shared.contextBlock
        if !memBlock.isEmpty {
            lines.append("=== MÉMOIRE COACH (persistante) ===")
            lines.append(memBlock)
            lines.append("===")
        }

        // Profile + date (1 line)
        let p = dash.profile
        var info: [String] = []
        if let n = p.name    { info.append(n) }
        if let w = p.weight  { info.append("\(String(format: "%.0f", w))lbs") }
        if let a = p.age     { info.append("\(a)ans") }
        if let g = p.goal    { info.append(g) }
        if let l = p.level   { info.append(l) }
        lines.append("[\(info.joined(separator: " ")) | \(dash.todayDate) \(dash.today) S\(dash.week)]")

        // LSS + ACWR (1-2 lines)
        if let lss = lssData {
            let c = lss.components
            var t = "LSS:\(String(format: "%.0f", lss.score))"
            if let v = c.sleepQuality    { t += " som:\(String(format: "%.0f", v))" }
            if let v = c.hrvTrend        { t += " hrv:\(String(format: "%.0f", v))" }
            if let v = c.rhrTrend        { t += " rhr:\(String(format: "%.0f", v))" }
            if let v = c.subjectiveStress { t += " stress:\(String(format: "%.0f", v))" }
            if let v = c.trainingFatigue { t += " fatigue:\(String(format: "%.0f", v))" }
            var flags: [String] = []
            if lss.flags.hrvDrop          { flags.append("!hrv") }
            if lss.flags.sleepDeprivation { flags.append("!som") }
            if lss.flags.trainingOverload { flags.append("!surcharge") }
            if !flags.isEmpty { t += " \(flags.joined(separator: " "))" }
            lines.append(t)
        }
        if let acwr = acwrData {
            lines.append("ACWR:\(String(format: "%.2f", acwr.ratio)) \(acwr.zone.code) aiguë:\(String(format: "%.0f", acwr.acuteLoad)) chr:\(String(format: "%.0f", acwr.chronicLoad))")
        }

        // Mesocycle phase — critical context for RPE targets and volume expectations
        if let meso = mesocycleInfo {
            var mesoLine = "mésocycle: S\(meso.week)/8 \(meso.phase) cibleRPE:\(meso.rpeTarget)"
            if !meso.note.isEmpty { mesoLine += " (\(meso.note))" }
            lines.append(mesoLine)
        }

        // Schedule
        let sched = dash.schedule.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " ")
        if !sched.isEmpty { lines.append("prog: \(sched)") }

        // Recent sessions
        let allSessions = sessionsData.isEmpty ? dash.sessions : sessionsData
        let recent = allSessions.sorted { $0.key > $1.key }.prefix(12)
        if !recent.isEmpty {
            let count30 = allSessions.filter {
                $0.key >= DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 30 * 86400))
            }.count
            lines.append("séances(\(count30)/30j):")
            for (date, s) in recent {
                let dd = String(date.suffix(5))   // MM-DD
                var row = dd
                if let exos = s.exos, !exos.isEmpty { row += " \(exos.joined(separator: "+"))" }
                if let rpe = s.rpe        { row += " RPE:\(String(format: "%.1f", rpe))" }
                if let sets = s.totalSets { row += " sets:\(sets)" }
                if let dur = s.durationMin { row += " \(dur)m" }
                lines.append("  \(row)")
            }
        }

        // Recovery (last 8)
        let recov = recoveryData.prefix(8).compactMap { r -> String? in
            guard let date = r.date else { return nil }
            let dd = String(date.suffix(5))
            var t = dd
            if let v = r.sleepHours   { t += " \(String(format: "%.1f", v))h" }
            if let v = r.sleepQuality { t += " q:\(String(format: "%.0f", v))" }
            if let v = r.hrv          { t += " hrv:\(String(format: "%.0f", v))" }
            if let v = r.restingHr    { t += " rhr:\(String(format: "%.0f", v))" }
            if let v = r.soreness     { t += " soreness:\(String(format: "%.0f", v))" }
            return t
        }
        if !recov.isEmpty { lines.append("récup: " + recov.joined(separator: " | ")) }

        // Body weight trend (1 line)
        let bw = Array(bodyWeightData.prefix(5))
        if !bw.isEmpty {
            let pts = bw.map { e -> String in
                var s = "\(String(e.date.suffix(5))):\(String(format: "%.1f", e.weight))"
                if let bf = e.bodyFat { s += "(\(String(format: "%.0f", bf))%)" }
                return s
            }.joined(separator: " ")
            if bw.count >= 2 {
                let delta = bw[0].weight - bw[bw.count - 1].weight
                lines.append("poids(\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta))lbs): \(pts)")
            } else {
                lines.append("poids: \(pts)")
            }
        }

        // Muscle volume (top 6, 1 line)
        let muscles = muscleStatsData.sorted { $0.value.volume > $1.value.volume }.prefix(6)
        if !muscles.isEmpty {
            let ms = muscles.map { (m, s) in "\(m):\(String(format: "%.0f", UnitSettings.shared.display(s.volume)))\(UnitSettings.shared.label)(\(s.sessions)s)" }.joined(separator: " ")
            lines.append("muscles: \(ms)")
        }

        // Nutrition today (1 line)
        let nt = dash.nutritionTotals; let ns = dash.nutritionSettings
        var nutr: [String] = []
        if let cal = nt.calories {
            var s = "cal:\(String(format: "%.0f", cal))"
            if let target = ns?.calories, target > 0 {
                s += "/\(String(format: "%.0f", target))(\(Int((cal / target * 100).rounded()))%)"
            }
            nutr.append(s)
        }
        if let prot = nt.proteines {
            var s = "prot:\(String(format: "%.0f", prot))g"
            if let target = ns?.proteines, target > 0 {
                s += "/\(String(format: "%.0f", target))g(\(Int((prot / target * 100).rounded()))%)"
            }
            nutr.append(s)
        }
        if let carbs = nt.glucides { nutr.append("carbs:\(String(format: "%.0f", carbs))g") }
        if let fat = nt.lipides    { nutr.append("lip:\(String(format: "%.0f", fat))g") }
        if !nutr.isEmpty { lines.append("nutri: \(nutr.joined(separator: " "))") }
        let logged7 = nutritionHistory.prefix(7).filter { $0.calories > 0 || $0.proteines > 0 }.count
        if !nutritionHistory.isEmpty {
            lines.append("nutri-7j: \(logged7)/\(min(nutritionHistory.count, 7)) jours loggués")
        }

        // Mental health (7d summary)
        if let mental = mentalData {
            var mt: [String] = []
            if let mood = mental.avgMood { mt.append("humeur:\(String(format: "%.1f", mood))/10") }
            mt.append("trend:\(mental.moodTrend)")
            if let pss = mental.pssScore { mt.append("PSS:\(pss)") }
            if let cat = mental.pssCategory { mt.append("(\(cat))") }
            mt.append("autosoins:\(String(format: "%.0f", mental.selfCareRate * 100))%")
            if !mental.topEmotions.isEmpty { mt.append("émotions:\(mental.topEmotions.prefix(3).joined(separator: "/"))") }
            lines.append("mental(7j): \(mt.joined(separator: " "))")
        }

        // Goals (1 line)
        if !dash.goals.isEmpty {
            let gs = dash.goals.sorted { $0.key < $1.key }.map { (k, v) in
                "\(k):\(String(format: "%.0f", v.current))/\(String(format: "%.0f", v.goal))\(v.achieved ? "✓" : "")"
            }.joined(separator: " ")
            lines.append("goals: \(gs)")
        }

        // Lifts (top 12, 1 per line compressed)
        let lifts = weightsData.compactMap { (name, w) -> (String, WeightData)? in
            w.currentWeight != nil ? (name, w) : nil
        }.sorted { ($0.1.currentWeight ?? 0) > ($1.1.currentWeight ?? 0) }.prefix(12)
        if !lifts.isEmpty {
            lines.append("lifts:")
            for (name, w) in lifts {
                var row = "\(name):\(String(format: "%.0f", w.currentWeight ?? 0))lbs"
                if let r = w.lastReps   { row += "(\(r))" }
                if let d = w.lastLogged { row += " \(String(d.suffix(5)))" }
                lines.append("  \(row)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func purgeStaleMemoryEntries() {
        // Remove any milestone that references deleted test data (e.g. 450lbs squat)
        let stale = CoachMemoryStore.shared.entries.filter {
            $0.id == "milestone.strongest.lift" && $0.content.contains("450")
        }
        for entry in stale {
            CoachMemoryStore.shared.delete(id: entry.id)
        }
        if !stale.isEmpty {
            // Reset cooldown so analysis re-runs with corrected data on next load
            UserDefaults.standard.removeObject(forKey: "coach_memory_last_analysis")
        }
    }

    private func sendQuery(_ query: String) {
        input = query
        sendMessage()
    }

    private func sendMessage() {
        userHasInteracted = true
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let context = buildContext()
        messages.append(ChatMessage(role: .user, content: text))
        input = ""
        isLoading = true

        if messages.count > 50 { messages = Array(messages.suffix(50)) }
        // Keep last 12 messages (6 exchanges) — server caps at 20 but less is cheaper
        let history = messages.suffix(12).map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }

        Task {
            do {
                guard let url = URL(string: "\(APIService.shared.baseURL)/api/ai/coach") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 60
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: [
                    "context":  context,
                    "messages": history
                ])
                let (data, _) = try await URLSession.authed.data(for: req)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let reply = json["response"] as? String ?? json["error"] as? String ?? "Erreur inconnue"
                    await MainActor.run {
                        messages.append(ChatMessage(role: .assistant, content: reply))
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, content: "Erreur: \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }
    }

    private var currentWeekKey: String {
        // Weeks since first Monday after Unix epoch (Jan 5, 1970 = second 345600)
        // Avoids Calendar.current.component which recurses on iOS 26
        let weekIndex = Int((Date().timeIntervalSince1970 - 345_600) / 604_800)
        return "W\(weekIndex)"
    }

    private func loadNarrative() {
        guard !isLoadingNarrative else { return }
        // Return cached narrative for current week
        let cacheKey = "narrative_\(currentWeekKey)"
        if let cached = CacheService.shared.load(for: cacheKey),
           let text = String(data: cached, encoding: .utf8) {
            narrative = text; return
        }
        let context = buildContext()
        isLoadingNarrative = true
        Task {
            do {
                let text = try await APIService.shared.fetchWeeklyNarrative(context: context, weekKey: currentWeekKey)
                // Cache for the week
                if let data = text.data(using: .utf8) {
                    CacheService.shared.save(data, for: cacheKey)
                }
                await MainActor.run { narrative = text; isLoadingNarrative = false }
            } catch {
                await MainActor.run { isLoadingNarrative = false }
            }
        }
    }

    private func loadInsights() {
        guard !isLoadingCorrelations else { return }
        isLoadingCorrelations = true
        Task {
            do {
                let result = try await APIService.shared.fetchCorrelations()
                await MainActor.run {
                    correlations = result
                    showInsights = true
                    isLoadingCorrelations = false
                }
            } catch {
                await MainActor.run { isLoadingCorrelations = false }
            }
        }
    }

    private func generateProgram() {
        guard !isGeneratingProgram else { return }
        isGeneratingProgram = true
        programError = nil
        Task {
            do {
                let gp = try await APIService.shared.generateProgram()
                await MainActor.run {
                    generatedProgram    = gp
                    isGeneratingProgram = false
                    showProgramPreview  = true
                }
            } catch {
                await MainActor.run {
                    isGeneratingProgram = false
                    programError = error.localizedDescription
                }
            }
        }
    }

    private func loadProposals() {
        guard !isLoadingProposals else { return }
        isLoadingProposals = true
        proposals = []
        proposalError = nil
        Task {
            // Ensure dashboard is loaded
            if APIService.shared.dashboard == nil {
                await APIService.shared.fetchDashboard()
            }
            let context = buildContext()
            guard context != "no data" else {
                await MainActor.run {
                    isLoadingProposals = false
                    proposalError = "Données non disponibles — ouvre le dashboard d'abord."
                }
                return
            }
            do {
                guard let url = URL(string: "\(APIService.shared.baseURL)/api/ai/propose") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: ["context": context])
                let (data, response) = try await URLSession.authed.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                    await MainActor.run {
                        isLoadingProposals = false
                        proposalError = msg ?? "Erreur serveur (\(http.statusCode))"
                    }
                    return
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let raw = json["proposals"] as? [[String: Any]] {
                    let parsed = raw.compactMap { d -> AIProposal? in
                        guard let reason = d["reason"] as? String else { return nil }
                        return AIProposal(
                            jour: d["jour"] as? String ?? "",
                            action: d["action"] as? String ?? "",
                            exercise: d["exercise"] as? String ?? d["old_exercise"] as? String ?? "",
                            scheme: d["scheme"] as? String ?? "",
                            reason: reason
                        )
                    }
                    await MainActor.run {
                        proposals = parsed
                        isLoadingProposals = false
                        if parsed.isEmpty { proposalError = "Aucune proposition générée." }
                    }
                } else {
                    await MainActor.run {
                        isLoadingProposals = false
                        proposalError = "Réponse inattendue du serveur."
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingProposals = false
                    proposalError = "Erreur réseau : \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadIntelligenceFeatures() async {
        let base = APIService.shared.baseURL
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                guard let url = URL(string: "\(base)/api/overtraining_risk"),
                      let (d, _) = try? await URLSession.authed.data(from: url),
                      let r = try? APIService.decoder.decode(OvertrainingRisk.self, from: d)
                else { return }
                await MainActor.run { self.overtrainingRisk = r }
            }
            group.addTask {
                guard let url = URL(string: "\(base)/api/mesocycle_status"),
                      let (d, _) = try? await URLSession.authed.data(from: url),
                      let r = try? APIService.decoder.decode(MesocycleStatus.self, from: d)
                else { return }
                await MainActor.run { self.mesocycleStatus = r }
            }
            group.addTask {
                guard let url = URL(string: "\(base)/api/pain_journal"),
                      let (d, _) = try? await URLSession.authed.data(from: url),
                      let r = try? APIService.decoder.decode(PainJournalResponse.self, from: d)
                else { return }
                await MainActor.run { self.painJournal = r }
            }
            group.addTask {
                guard let url = URL(string: "\(base)/api/one_rm_programming"),
                      let (d, _) = try? await URLSession.authed.data(from: url),
                      let r = try? APIService.decoder.decode(OneRMResponse.self, from: d)
                else { return }
                await MainActor.run { self.oneRMData = r }
            }
        }
    }

    private func openWeeklyReport() {
        guard !isLoadingWeeklyReport else { return }
        let cacheKey = "weekly_report_\(currentWeekKey)"
        if let cached = CacheService.shared.load(for: cacheKey),
           let r = try? APIService.decoder.decode(WeeklyReport.self, from: cached) {
            weeklyReportData = r
            showWeeklyReport = true
            return
        }
        isLoadingWeeklyReport = true
        Task {
            if let r = try? await APIService.shared.fetchWeeklyReport() {
                if let data = try? JSONEncoder().encode(r) {
                    CacheService.shared.save(data, for: cacheKey)
                }
                await MainActor.run {
                    weeklyReportData    = r
                    isLoadingWeeklyReport = false
                    showWeeklyReport    = true
                }
            } else {
                await MainActor.run { isLoadingWeeklyReport = false }
            }
        }
    }
}

