import SwiftUI
import Combine
import OSLog

private let logger = Logger(subsystem: "TrainingOS", category: "Intelligence")

struct IntelligenceView: View {
    @EnvironmentObject private var theme: AppTheme
    @StateObject private var dailyBriefService = DailyBriefService.shared
    @State private var correlations: CorrelationsData? = nil
    @State private var isLoadingCorrelations = false
    @State private var showInsights = false
    @ObservedObject private var api   = APIService.shared
    @ObservedObject private var units = UnitSettings.shared
    @State private var recoveryData:    [RecoveryEntry]          = []
    @State private var weightsData:     [String: WeightData]     = [:]
    @State private var bodyWeightData:  [BodyWeightEntry]        = []
    @State private var muscleStatsData: [String: MuscleStatEntry] = [:]
    @State private var sessionsData:    [String: SessionEntry]   = [:]
    @State private var acwrData:        ACWRData?                = nil
    @State private var lssData:         LifeStressScore?         = nil
    @State private var selectedSection: CoachSection = .briefing
    @ObservedObject private var memoryStore = CoachMemoryStore.shared
    @State private var nutritionHistory: [NutritionDayHistory]  = []
    @State private var showNutritionInsight                     = true
    @State private var weeklyReportData: WeeklyReport?          = nil
    @State private var showWeeklyReport                         = false
    @State private var isLoadingWeeklyReport                    = false
    @State private var dailyInsight: DailyInsight? = nil
    @State private var proactiveInsights: ProactiveInsightsResponse? = nil
    @State private var intelligenceInsights: [ProactiveInsightItem] = []
    @State private var isLoadingIntelligence = false
    @State private var isLoadingInsight = false
    @State private var postSessionData: PostSessionData? = nil
    @AppStorage("post_session_logged_at") private var postSessionLoggedAt: String = ""
    @State private var cardioData: [CardioEntry] = []
    @State private var mesocycleInfo: MesocycleInfo? = nil
    @State private var mentalData: MentalHealthSummary? = nil

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
    @State private var toast: ToastMessage? = nil

    // Éducatif
    @State private var educationalCapsules: [EducationalCapsule] = []
    @State private var isLoadingEducational = false
    @State private var selectedEducationalCategory: String? = nil
    @State private var selectedCapsule: EducationalCapsule? = nil

    private static let educationalCategories: [(key: String, label: String)] = [
        ("kine",           "Kiné"),
        ("anatomie",       "Anatomie"),
        ("sports_science", "Science"),
        ("well_being",     "Bien-être"),
        ("nutrition",      "Nutrition"),
    ]

    // Tab-switch callback injected from ContentView
    var onOpenSession: (() -> Void)? = nil

    private var todayRecovery: RecoveryEntry? { recoveryData.first }

    private var activeInsight: DailyInsight? {
        if let pi = proactiveInsights?.dashboardInsight { return pi.asDailyInsight() }
        if let di = dailyInsight, !di.isEmpty { return di }
        return nil
    }

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
        case briefing  = "Briefing"
        case patterns  = "Patterns"
        case programme = "Programme"
        case bilan     = "Bilan"
        case memoire   = "Mémoire"
        case educatif  = "Éducatif"

        var icon: String {
            switch self {
            case .briefing:  return "doc.text.fill"
            case .patterns:  return "chart.dots.scatter"
            case .programme: return "calendar.badge.plus"
            case .bilan:     return "chart.bar.doc.horizontal"
            case .memoire:   return "brain.head.profile"
            case .educatif:  return "graduationcap.fill"
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
                                            .font(.appLabel.weight(.semibold))
                                        if !memoryStore.entries.isEmpty {
                                            Text("\(memoryStore.entries.count)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.statusPurple)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Color.statusPurple.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .foregroundColor(.statusPurple)
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
                                    .foregroundColor(Color.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.forge)
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
                    if selectedSection == .briefing {
                        briefingSectionView
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
                    } else if selectedSection == .educatif {
                        educatifSectionView
                    } else {
                        ScrollView(showsIndicators: false) {
                            summaryCardsView
                            memoireSectionView
                        }
                    }

                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider().background(Color.appSeparatorStrong)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CoachSection.allCases, id: \.self) { section in
                                    Button {
                                        hideKeyboard()
                                        withAnimation(.easeInOut(duration: 0.2)) { selectedSection = section }
                                    } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: section.icon)
                                            .font(.appCaption.weight(.semibold))
                                        Text(section.rawValue)
                                            .font(.appLabel)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 11)
                                    .background(
                                        selectedSection == section
                                            ? Color.statusPurple.opacity(0.22)
                                            : Color.appSurfaceInset
                                    )
                                    .foregroundColor(
                                        selectedSection == section ? .statusPurple : Color.appTextSecondary
                                    )
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(
                                            selectedSection == section
                                                ? Color.statusPurple.opacity(0.45)
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
                if api.dashboard == nil { await api.fetchDashboard() }
                await loadContextData()
                let streak = computeStreak(from: sessionsData)
                await APIService.shared.syncDeloadFlag()
                NotificationService.scheduleStreakDanger(
                    streak: streak,
                    hasSessionToday: api.dashboard?.alreadyLoggedToday == true
                )
                await MainActor.run { purgeStaleMemoryEntries() }
                Task { await loadDailyInsight() }
                Task { await loadProactiveInsights() }
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
            .sheet(isPresented: $showWeeklyReport) {
                if let r = weeklyReportData {
                    NavigationStack {
                        WeeklyReportView(report: r)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Fermer") { showWeeklyReport = false }.foregroundColor(.appTextPrimary)
                                }
                            }
                    }
                    .preferredColorScheme(.dark)
                    .presentationDetents([.large])
                }
            }
            .sheet(item: $selectedCapsule) { capsule in
                EducationalCapsuleDetailSheet(capsule: capsule) {
                    selectedCapsule = nil
                }
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
            }
            .toast($toast)
        }
    }
    }

    // MARK: - Section Views

    @ViewBuilder
    private var summaryCardsView: some View {
        if let insight = activeInsight {
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
    private var briefingSectionView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                DailyBriefView(
                    brief: dailyBriefService.brief,
                    isLoading: dailyBriefService.isLoading,
                    isStale: dailyBriefService.isStale,
                    activeInsight: activeInsight
                )
                .padding(.horizontal, 16)

                if let dash = api.dashboard {
                    CoachMissionCard(
                        dash: dash,
                        onOpenSession: onOpenSession,
                        onRefreshBrief: { Task { await dailyBriefService.forceRefresh() } }
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
        .task {
            await dailyBriefService.loadIfNeeded()
        }
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
                        .foregroundColor(Color.statusPurple.opacity(0.5))
                    Text("Pas encore assez de données — reviens dans quelques semaines.")
                        .font(.appLabel)
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
                            .foregroundColor(.statusPurple)
                        Text("MES PATTERNS SUIVIS")
                            .font(.appCaption.weight(.bold))
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
                    .font(.appCaption.weight(.bold))
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
                            Image(systemName: "chart.dots.scatter").font(.appLabel)
                            Text("Analyser les corrélations").font(.appLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.statusPurple.opacity(0.10))
                        .foregroundColor(.statusPurple)
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
                        .font(.appCaption.weight(.bold))
                        .foregroundColor(.appTextMuted)
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("S\(meso.week)/8")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.appTextPrimary)
                            Text(meso.phase)
                                .font(.appLabel)
                                .foregroundColor(.statusPurple)
                        }
                        Rectangle()
                            .fill(Color.appSeparator)
                            .frame(width: 1, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("RPE cible")
                                .font(.appCaption)
                                .foregroundColor(.appTextMuted)
                            Text(meso.rpeTarget)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.appTextPrimary)
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
                .background(Color.appSurfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }

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
                .background(Color.appSurfaceInset)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            // NIVEAU 3b — Analyses (accordion)
            bilanAccordionRow(id: "analyses", icon: "chart.dots.scatter", label: "Analyses", accent: .statusPurple) {
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
                        .font(.appLabel)
                        .foregroundColor(Color(white: 0.45))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }

            // NIVEAU 3c — Intelligence proactive (accordion)
            bilanAccordionRow(id: "intelligence", icon: "sparkles", label: "Intelligence", accent: .statusBlue) {
                if isLoadingIntelligence {
                    SkeletonBar(height: 80, radius: 12)
                        .padding(.horizontal, 16).padding(.bottom, 4)
                } else if intelligenceInsights.isEmpty {
                    Text("Pas encore assez de données pour générer des insights.")
                        .font(.appLabel)
                        .foregroundColor(Color(white: 0.45))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                } else {
                    ForEach(intelligenceInsights, id: \.dimension) { insight in
                        intelligenceInsightCard(insight)
                    }
                }
            }

            // Bilan complet — accès direct au rapport
            Button { openWeeklyReport() } label: {
                HStack(spacing: 10) {
                    if isLoadingWeeklyReport {
                        ProgressView().tint(.onAccent).scaleEffect(0.8)
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
                .background(Color.appSurfaceInset)
                .foregroundColor(.appTextPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
            .disabled(isLoadingWeeklyReport)
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
        .onAppear {
            if overtrainingRisk == nil { Task { await loadIntelligenceFeatures() } }
            if intelligenceInsights.isEmpty && !isLoadingIntelligence { Task { await loadProactiveIntelligence() } }
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
                Divider().frame(height: 36).background(Color.appSeparatorStrong)
                bilanStatCell(value: restDays == 0 ? "—" : "\(restDays)", label: "repos")
                if let rpe = avgRpe {
                    Divider().frame(height: 36).background(Color.appSeparatorStrong)
                    bilanStatCell(value: String(format: "%.1f", rpe), label: "RPE moy")
                }
                if totalVol > 0 {
                    Divider().frame(height: 36).background(Color.appSeparatorStrong)
                    bilanStatCell(value: _formatK(units.display(totalVol)), label: "\(units.label) vol")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color.appSurfaceInset)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func bilanStatCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.appTextPrimary)
            Text(label)
                .font(.appCaption)
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
                        let color: Color = r.level == "low" ? .statusGreen : r.level == "moderate" ? .statusOrange : .statusRed
                        bilanSignalChip(
                            icon: r.level == "low" ? "checkmark.circle" : "exclamationmark.triangle",
                            label: label, color: color
                        )
                    }
                    if let m = meso {
                        bilanSignalChip(
                            icon: m.icon.isEmpty ? "calendar" : m.icon,
                            label: "S\(m.weekInCycle) — \(m.phaseLabel)",
                            color: .statusPurple
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
                .font(.appCaption.weight(.semibold))
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedBilan.contains(id) { expandedBilan.remove(id) }
                    else { expandedBilan.insert(id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 20)
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.appCaption)
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
        .background(Color.appSurfaceInset)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func acwrZoneColor(_ colorStr: String) -> Color {
        switch colorStr {
        case "green":  return .statusGreen
        case "orange": return .statusOrange
        case "red":    return .statusRed
        default:       return .gray
        }
    }

    private func insightAccentColor(_ colorStr: String) -> Color {
        switch colorStr {
        case "red":    return .statusRed
        case "orange": return .statusOrange
        case "yellow": return .statusYellow
        case "green":  return .statusGreen
        case "teal":   return .statusCyan
        case "blue":   return .statusBlue
        case "purple": return .statusPurple
        default:       return .gray
        }
    }

    @ViewBuilder
    private func intelligenceInsightCard(_ insight: ProactiveInsightItem) -> some View {
        let accent = insightAccentColor(insight.color)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.icon)
                .font(.appBody.weight(.semibold))
                .foregroundColor(accent)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text(insight.message)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .glassCardAccent(accent, cornerRadius: 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Éducatif

    private var filteredEducationalCapsules: [EducationalCapsule] {
        guard let cat = selectedEducationalCategory else { return educationalCapsules }
        return educationalCapsules.filter { $0.category == cat }
    }

    private var visibleEducationalGroups: [(key: String, label: String, items: [EducationalCapsule])] {
        let source = filteredEducationalCapsules
        return Self.educationalCategories.compactMap { cat in
            let items = source.filter { $0.category == cat.key }
            return items.isEmpty ? nil : (key: cat.key, label: cat.label, items: items)
        }
    }

    @ViewBuilder
    private var educatifSectionView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                educationalFilterBar

                if isLoadingEducational && educationalCapsules.isEmpty {
                    VStack(spacing: 10) {
                        SkeletonBar(height: 80, radius: 14)
                        SkeletonBar(height: 80, radius: 14)
                        SkeletonBar(height: 80, radius: 14)
                    }
                    .padding(.horizontal, 16)
                } else if filteredEducationalCapsules.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "book")
                            .foregroundColor(Color.statusPurple.opacity(0.5))
                        Text("Aucune capsule dans cette catégorie.")
                            .font(.appLabel)
                            .foregroundColor(Color(white: 0.45))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                } else {
                    ForEach(visibleEducationalGroups, id: \.key) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.label.uppercased())
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(Color(white: 0.45))
                                .padding(.horizontal, 16)
                            ForEach(group.items) { capsule in
                                EducationalCapsuleCard(capsule: capsule) {
                                    selectedCapsule = capsule
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .onAppear {
            if educationalCapsules.isEmpty && !isLoadingEducational {
                loadEducationalContent()
            }
        }
    }

    @ViewBuilder
    private var educationalFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                educationalFilterChip(key: nil, label: "Tous")
                ForEach(Self.educationalCategories, id: \.key) { cat in
                    educationalFilterChip(key: cat.key, label: cat.label)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func educationalFilterChip(key: String?, label: String) -> some View {
        let isSelected = selectedEducationalCategory == key
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedEducationalCategory = key
            }
        } label: {
            Text(label)
                .font(.appLabel)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.statusPurple.opacity(0.22) : Color.appSurfaceInset)
                .foregroundColor(isSelected ? .statusPurple : Color.appTextSecondary)
                .clipShape(Capsule())
        }
    }

    private func loadEducationalContent() {
        guard !isLoadingEducational else { return }
        isLoadingEducational = true
        Task {
            do {
                let capsules = try await APIService.shared.fetchEducationalContent()
                await MainActor.run {
                    self.educationalCapsules = capsules
                    self.isLoadingEducational = false
                }
            } catch {
                logger.error("educational content fetch failed: \(error.localizedDescription)")
                await MainActor.run { self.isLoadingEducational = false }
            }
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
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(Color(white: 0.45))
                    .padding(.horizontal, 16)

                ForEach(memoryStore.entries, id: \.id) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.type.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.statusPurple)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.type.rawValue)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.statusPurple.opacity(0.7))
                            Text(entry.content)
                                .font(.appLabel)
                                .foregroundColor(Color(white: 0.82))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button {
                            withAnimation { CoachMemoryStore.shared.delete(id: entry.id) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.appCaption)
                                .foregroundColor(Color(white: 0.3))
                                .padding(6)
                        }
                    }
                    .padding(12)
                    .background(Color.appSurfaceInset)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }
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

    private func loadProactiveInsights() async {
        do {
            let cached = try? await APIService.shared.fetchReadiness()
            let result = try await APIService.shared.fetchProactiveInsights(
                readinessScore: cached.map { Double($0.score) }
            )
            await MainActor.run { proactiveInsights = result }
            if let push = result.pushInsight {
                NotificationService.scheduleProactiveAlert(
                    title: push.title,
                    body: push.message,
                    identifier: "proactive.\(push.dimension)"
                )
            }
        } catch {
            await MainActor.run { toast = ToastMessage(message: "Insights indisponibles", style: .error) }
        }
    }

    private func loadProactiveIntelligence() async {
        await MainActor.run { isLoadingIntelligence = true }
        do {
            let result = try await APIService.shared.fetchIntelligenceInsights()
            await MainActor.run { intelligenceInsights = result; isLoadingIntelligence = false }
        } catch {
            await MainActor.run { isLoadingIntelligence = false }
        }
    }

    private func computeStreak(from sessions: [String: SessionEntry]) -> Int {
        let formatter = DateFormatter.isoDate
        var streak = 0
        var checkTime = Date().timeIntervalSince1970
        for _ in 0..<60 {
            let check = formatter.string(from: Date(timeIntervalSince1970: checkTime))
            if sessions[check] != nil {
                streak += 1
                checkTime -= 86400
            } else { break }
        }
        return streak
    }

    private func loadPostSession() async {
        guard shouldShowPostSeanceCard else { return }
        do {
            let data = try await APIService.shared.fetchPostSession()
            await MainActor.run { postSessionData = data }
        } catch {
            await MainActor.run { toast = ToastMessage(message: "Données post-séance indisponibles", style: .error) }
        }
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

    private var currentWeekKey: String {
        // Weeks since first Monday after Unix epoch (Jan 5, 1970 = second 345600)
        // Avoids Calendar.current.component which recurses on iOS 26
        let weekIndex = Int((Date().timeIntervalSince1970 - 345_600) / 604_800)
        return "W\(weekIndex)"
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

// MARK: - Éducatif subviews

private struct EducationalCapsuleCard: View {
    let capsule: EducationalCapsule
    let onTap: () -> Void

    private var previewLine: String? {
        capsule.body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first {
                !$0.isEmpty
                && !$0.hasPrefix("#")
                && !$0.hasPrefix("-")
                && !$0.hasPrefix("*")
            }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(capsule.title)
                    .font(.appHeadline)
                    .foregroundColor(.appTextPrimary)
                    .multilineTextAlignment(.leading)
                if let preview = previewLine {
                    Text(preview)
                        .font(.appBody)
                        .foregroundColor(Color(white: 0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let tags = capsule.tags, !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.appCaption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.statusPurple.opacity(0.12))
                                .foregroundColor(.statusPurple)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard)
            .cornerRadius(14)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct EducationalCapsuleDetailSheet: View {
    let capsule: EducationalCapsule
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(capsule.title)
                        .font(.appTitle)
                        .foregroundColor(.appTextPrimary)
                    MarkdownText(markdown: capsule.body)
                    if let tags = capsule.tags, !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.appCaption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.statusPurple.opacity(0.12))
                                    .foregroundColor(.statusPurple)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(Color.appBg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", action: onDismiss).foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}
