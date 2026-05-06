import SwiftUI
import Combine

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
    @ObservedObject private var api = APIService.shared
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
    @AppStorage("coach_brief_date") private var briefDate: String = ""
    @AppStorage("coach_brief_text") private var briefText: String = ""
    @State private var isBriefLoading = false
    @State private var cardioData: [CardioEntry] = []
    @State private var mesocycleInfo: MesocycleInfo? = nil
    @State private var mentalData: MentalHealthSummary? = nil
    @State private var userHasInteracted = false  // gates auto-scroll; set only when user sends a message

    // Tab-switch callback injected from ContentView
    var onOpenSession: (() -> Void)? = nil

    private var todayRecovery: RecoveryEntry? { recoveryData.first }

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
                Color(hex: "080810").ignoresSafeArea()

                VStack(spacing: 0) {
                    // Hero: mission card only
                    if let dash = api.dashboard {
                        CoachMissionCard(
                            dash: dash,
                            briefText: briefText,
                            isBriefLoading: isBriefLoading,
                            onOpenSession: onOpenSession,
                            onRefreshBrief: { Task { await regenerateBrief() } },
                            onAskMore: { q in
                                withAnimation(.easeInOut(duration: 0.2)) { selectedSection = .chat }
                                sendQuery(q)
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    } else {
                        SkeletonBar(height: 160, radius: 20)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                    }

                    // Section pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CoachSection.allCases, id: \.self) { section in
                                Button {
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

                    // Section content
                    if selectedSection == .chat {
                        chatSectionView
                    } else if selectedSection == .patterns {
                        ScrollView(showsIndicators: false) { patternsSectionView }
                    } else if selectedSection == .programme {
                        ScrollView(showsIndicators: false) { programmeSectionView }
                    } else if selectedSection == .bilan {
                        ScrollView(showsIndicators: false) { bilanSectionView }
                    } else {
                        ScrollView(showsIndicators: false) { memoireSectionView }
                    }
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
                await loadMorningBrief()
            }
            .onChange(of: messages) {
                let toSave = messages.filter { !$0.content.hasPrefix("Erreur:") }
                if let data = try? JSONEncoder().encode(Array(toSave.suffix(50))),
                   let str = String(data: data, encoding: .utf8) {
                    historyData = str
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await regenerateBrief() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(isBriefLoading ? .purple.opacity(0.5) : .purple)
                    }
                    .disabled(isBriefLoading)
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

    // MARK: - Section Views

    @ViewBuilder
    private var chatSectionView: some View {
        ChatPanel(
            messages: $messages,
            input: $input,
            isLoading: $isLoading,
            userHasInteracted: $userHasInteracted,
            sendMessage: sendMessage
        ) {
            TopicExplorer { q in sendQuery(q) }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var patternsSectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoadingCorrelations {
                SkeletonBar(height: 120, radius: 16).padding(.horizontal, 16)
            } else if let corr = correlations {
                InsightsCard(data: corr, onDismiss: { correlations = nil; showInsights = false })
                    .padding(.horizontal, 16)
            } else {
                Button { loadInsights() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.dots.scatter").font(.system(size: 14))
                        Text("Analyser les corrélations").font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.purple.opacity(0.12))
                    .foregroundColor(.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
            }

            if !memoryStore.entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PATTERNS DÉTECTÉS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                        .padding(.horizontal, 16)

                    ForEach(memoryStore.entries.prefix(8), id: \.id) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: entry.type.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.purple)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.type.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.purple.opacity(0.7))
                                Text(entry.content)
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(white: 0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                    }
                }
            } else {
                Text("Aucun pattern détecté — reviens après quelques semaines.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.45))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
        .onAppear {
            if correlations == nil && !isLoadingCorrelations { loadInsights() }
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
                    .background(Color.indigo.opacity(0.1))
                    .foregroundColor(.indigo)
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
                            ProgressView().tint(.indigo).scaleEffect(0.75)
                        } else {
                            Image(systemName: "calendar.badge.plus").font(.system(size: 13))
                        }
                        Text("Générer").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.indigo.opacity(0.15))
                    .foregroundColor(.indigo)
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
        VStack(alignment: .leading, spacing: 16) {
            if isLoadingNarrative {
                SkeletonBar(height: 100, radius: 12).padding(.horizontal, 16)
            } else if let text = narrative {
                NarrativeCard(text: text, onDismiss: { narrative = nil })
                    .padding(.horizontal, 16)
            } else {
                Button { loadNarrative() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.quote").font(.system(size: 14))
                        Text("Récit de la semaine").font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.teal.opacity(0.12))
                    .foregroundColor(.teal)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
            }

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

            if let dash = api.dashboard {
                SmartInsightsSection(
                    dash: dash,
                    weightsData: weightsData,
                    sessionsData: sessionsData,
                    recovery: todayRecovery,
                    recoveryLog: recoveryData,
                    nutritionHistory: nutritionHistory
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
        .onAppear {
            if narrative == nil && !isLoadingNarrative { loadNarrative() }
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

    private func loadContextData() async {
        // 1. Prefer stats_data cache (already warm if StatsView was visited)
        if let cached  = CacheService.shared.load(for: "stats_data"),
           let decoded = try? JSONDecoder().decode(StatsSnapshot.self, from: cached) {
            await MainActor.run {
                recoveryData    = decoded.recoveryLog
                weightsData     = decoded.weights
                bodyWeightData  = decoded.bodyWeight
                muscleStatsData = decoded.muscleStats
                sessionsData    = decoded.sessions
            }
        } else {
            // Fallback: individual network calls (sequential — async let in parallel
            // triggers asyncLet_finish_after_task_completion LIFO crash on iOS 26 beta)
            let recovery = try? await APIService.shared.fetchRecoveryData()
            let weights  = try? await APIService.shared.fetchWeights()
            await MainActor.run {
                recoveryData = recovery ?? []
                weightsData  = weights ?? [:]
            }
        }

        // 2. ACWR + LSS
        let acwrResult = try? await APIService.shared.fetchACWR()
        let lssResult  = try? await APIService.shared.fetchLifeStressScore()
        await MainActor.run {
            acwrData = acwrResult
            lssData  = lssResult
        }

        // 3. Nutrition history + cardio data + mesocycle + mental health
        let hist       = try? await APIService.shared.fetchNutritionHistory()
        let cardio     = try? await APIService.shared.fetchCardioData()
        let seanceData = try? await APIService.shared.fetchSeanceData()
        let mental     = try? await APIService.shared.fetchMentalHealthSummary(days: 7)
        await MainActor.run {
            if let h = hist,       !h.isEmpty { nutritionHistory = h; showNutritionInsight = true }
            if let c = cardio                 { cardioData = c }
            if let m = seanceData?.mesocycle  { mesocycleInfo = m }
            if let m = mental                 { mentalData = m }
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
            if let v = c.subjectiveStress { t += " str:\(String(format: "%.0f", v))" }
            if let v = c.trainingFatigue { t += " fat:\(String(format: "%.0f", v))" }
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
                if let sets = s.totalSets { row += " \(sets)s" }
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
            if let v = r.soreness     { t += " cor:\(String(format: "%.0f", v))" }
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
        if let cal = nt.calories   { nutr.append("cal:\(String(format: "%.0f", cal))\(ns?.calories.map { "/\(String(format: "%.0f", $0))" } ?? "")") }
        if let prot = nt.proteines { nutr.append("prot:\(String(format: "%.0f", prot))g\(ns?.proteines.map { "/\(String(format: "%.0f", $0))g" } ?? "")") }
        if let carbs = nt.glucides { nutr.append("carbs:\(String(format: "%.0f", carbs))g") }
        if let fat = nt.lipides    { nutr.append("lip:\(String(format: "%.0f", fat))g") }
        if !nutr.isEmpty { lines.append("nutri: \(nutr.joined(separator: " "))") }

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

    private func loadMorningBrief() async {
        let today = DateFormatter.isoDate.string(from: Date())
        guard !(briefDate == today && !briefText.isEmpty) else { return }

        let context = buildContext()
        guard context != "no data" else { return }

        await MainActor.run { isBriefLoading = true }
        do {
            let url = URL(string: "\(APIService.shared.baseURL)/api/ai/coach")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 60
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "context": context,
                "messages": [[
                    "role": "user",
                    "content": "Brief du matin. 3 phrases max. Dis-moi : (1) ce que je fais aujourd'hui et pourquoi compte tenu de ma récup, (2) un point clé sur ma progression récente, (3) une chose concrète à surveiller aujourd'hui. Sois direct, personnalisé, pas de formule de politesse."
                ]]
            ])
            let (data, _) = try await URLSession.authed.data(for: req)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reply = json["response"] as? String {
                await MainActor.run {
                    briefText = reply
                    briefDate = today
                    isBriefLoading = false
                }
            } else {
                await MainActor.run { isBriefLoading = false }
            }
        } catch {
            await MainActor.run { isBriefLoading = false }
        }
    }

    private func regenerateBrief() async {
        briefDate = ""
        briefText = ""
        await loadMorningBrief()
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
                let url = URL(string: "\(APIService.shared.baseURL)/api/ai/coach")!
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
                let url = URL(string: "\(APIService.shared.baseURL)/api/ai/propose")!
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

    private func openWeeklyReport() {
        guard !isLoadingWeeklyReport else { return }
        let cacheKey = "weekly_report_\(currentWeekKey)"
        if let cached = CacheService.shared.load(for: cacheKey),
           let r = try? JSONDecoder().decode(WeeklyReport.self, from: cached) {
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

// MARK: - Proposals Card
struct ProposalsCard: View {
    let proposals: [AIProposal]
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Propositions IA", systemImage: "wand.and.stars")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.purple)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }

            ForEach(proposals) { p in
                HStack(alignment: .top, spacing: 10) {
                    Text(actionIcon(p.action))
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(p.jour).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                            if !p.exercise.isEmpty {
                                Text("·").foregroundColor(.gray)
                                Text(p.exercise).font(.system(size: 11)).foregroundColor(.purple)
                            }
                            if !p.scheme.isEmpty {
                                Text(p.scheme).font(.system(size: 11)).foregroundColor(.orange)
                            }
                        }
                        Text(p.reason).font(.system(size: 12)).foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "0d0d1a"))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.3), lineWidth: 1))
        .cornerRadius(12)
    }

    private func actionIcon(_ action: String) -> String {
        switch action {
        case "add":     return "➕"
        case "remove":  return "➖"
        case "replace": return "🔄"
        case "scheme":  return "📐"
        default:        return "💡"
        }
    }
}

// MARK: - Insights Card

struct InsightsCard: View {
    let data: CorrelationsData
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Corrélations · \(data.periodDays)j", systemImage: "chart.dots.scatter")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
                Spacer()
                Text("\(data.dataPoints) pts")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }

            if data.insights.isEmpty {
                Text("Pas assez de données pour détecter des corrélations (min. 5 points par paire).")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            } else {
                ForEach(data.insights) { insight in
                    CorrelationRow(insight: insight)
                    if insight.id != data.insights.last?.id {
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "080d1a"))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.25), lineWidth: 1))
        .cornerRadius(12)
    }
}

struct CorrelationRow: View {
    let insight: CorrelationInsight

    var accentColor: Color {
        switch insight.color {
        case "blue":   return .blue
        case "indigo": return .indigo
        case "green":  return .green
        case "teal":   return .teal
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        default:       return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: insight.icon)
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(insight.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Text(insight.strength)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accentColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                    Text(insight.insightDesc)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }

            // Barre de corrélation centrée sur 0, plage [-1, +1]
            GeometryReader { geo in
                let mid  = geo.size.width / 2
                let barW = abs(insight.correlation) * mid
                let offX = insight.correlation >= 0 ? mid : mid - barW

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: barW, height: 4)
                        .offset(x: offX)

                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1, height: 8)
                        .offset(x: mid - 0.5, y: -2)
                }
            }
            .frame(height: 8)
            .padding(.leading, 28)

            HStack {
                Spacer()
                Text("n=\(insight.nPoints)")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.25))
            }
            .padding(.leading, 28)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Narrative Card
struct NarrativeCard: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Récit de la semaine", systemImage: "text.quote")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.teal)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(hex: "0a1018"))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.teal.opacity(0.3), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - Nutrition × Performance Insight Model

struct NutritionPerfInsight {
    enum Kind {
        case deficitStagnation
        case deficitFatigue
        case proteinVolume
    }
    let kind: Kind
    let title: String
    let detail: String
    let actionHint: String

    var icon: String {
        switch kind {
        case .deficitStagnation: return "chart.line.flattrend.xyaxis"
        case .deficitFatigue:    return "heart.slash.fill"
        case .proteinVolume:     return "fork.knife"
        }
    }

    var accentColor: Color {
        switch kind {
        case .deficitStagnation: return .orange
        case .deficitFatigue:    return .red
        case .proteinVolume:     return .yellow
        }
    }
}

// MARK: - Nutrition × Performance Card

struct NutritionPerfInsightCard: View {
    let insight: NutritionPerfInsight
    let onDismiss: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: insight.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(insight.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(insight.accentColor)
                    Text(insight.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(expanded ? nil : 1)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if expanded {
                Divider().background(insight.accentColor.opacity(0.2)).padding(.horizontal, 12)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundColor(insight.accentColor.opacity(0.7))
                    Text(insight.actionHint)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(insight.accentColor.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(insight.accentColor.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Coach Greeting Header

private struct CoachGreetingHeader: View {
    let dash: DashboardData

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var firstName: String {
        dash.profile.name?.components(separatedBy: " ").first ?? "Athlète"
    }

    private var greeting: String {
        // Timestamp arithmetic to avoid Calendar.current.component on iOS 26
        let h = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
        if h < 12 { return "Bonjour" }
        if h < 18 { return "Bon après-midi" }
        return "Bonsoir"
    }

    private var formattedDate: String {
        guard let d = Self.isoFmt.date(from: dash.todayDate) else { return dash.todayDate }
        return Self.dateFmt.string(from: d).capitalized
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting), \(firstName)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                Text(formattedDate + " · Sem. \(dash.week)")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.38))
            }
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(Color.purple.opacity(0.5))
        }
    }
}

// MARK: - Coach Mission Card (Hero)

private struct CoachMissionCard: View {
    let dash: DashboardData
    let briefText: String
    let isBriefLoading: Bool
    let onOpenSession: (() -> Void)?
    let onRefreshBrief: () -> Void
    let onAskMore: (String) -> Void

    private var sessionColor: Color {
        switch dash.today {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .blue
        }
    }

    private var sessionDone: Bool {
        dash.alreadyLoggedToday || dash.sessions[dash.todayDate] != nil
    }

    private var hasDraft: Bool {
        SessionDraftStore.hasDraft(date: dash.todayDate, sessionType: "morning")
    }

    private var ctaLabel: String {
        if sessionDone { return "Voir ma séance" }
        if hasDraft    { return "Reprendre la séance" }
        return "Commencer →"
    }

    private var ctaIcon: String {
        if sessionDone { return "checkmark.circle.fill" }
        if hasDraft    { return "play.fill" }
        return "bolt.fill"
    }

    private var statusLabel: String {
        if sessionDone { return "Terminé ✓" }
        if hasDraft    { return "En cours" }
        return "À faire"
    }

    private var statusColor: Color {
        if sessionDone { return .green }
        if hasDraft    { return .orange }
        return sessionColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MISSION DU JOUR")
                        .font(.system(size: 10, weight: .black))
                        .tracking(2)
                        .foregroundColor(sessionColor)
                    Text(dash.today)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.white)
                }
                Spacer()
                Text(statusLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.07))

            // ── Brief text ────────────────────────────────────────────
            if isBriefLoading && briefText.isEmpty {
                MissionShimmer()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else if !briefText.isEmpty {
                Text(briefText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.82))
                    .lineSpacing(5)
                    .lineLimit(5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                Color.clear.frame(height: 8)
            }

            // ── CTA row ───────────────────────────────────────────────
            HStack(spacing: 10) {
                Button(action: { onOpenSession?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: ctaIcon)
                            .font(.system(size: 14, weight: .bold))
                        Text(ctaLabel)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(sessionDone ? Color.green : sessionColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(ScaleButtonStyle())

                if isBriefLoading {
                    ProgressView()
                        .tint(Color.white.opacity(0.35))
                        .scaleEffect(0.8)
                        .frame(width: 38, height: 38)
                } else {
                    Button(action: onRefreshBrief) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.3))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            ZStack {
                Color(hex: "0c0c18")
                LinearGradient(
                    colors: [sessionColor.opacity(0.12), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(sessionColor.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Mission Shimmer

private struct MissionShimmer: View {
    @State private var opacity: Double = 0.06

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(opacity))
                    .frame(maxWidth: i == 3 ? 140 : .infinity)
                    .frame(height: 12)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                opacity = 0.16
            }
        }
    }
}

// MARK: - Week Momentum Strip

private struct WeekMomentumStrip: View {
    let dash: DashboardData

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private struct DayDot {
        let letter: String
        let hasSession: Bool
        let isToday: Bool
    }

    private var dots: [DayDot] {
        guard let todayMidnight = Self.isoFmt.date(from: dash.todayDate) else { return [] }
        let base = todayMidnight.timeIntervalSince1970
        return (0..<7).reversed().map { i in
            let d = Date(timeIntervalSince1970: base - Double(i) * 86400)
            let str = Self.isoFmt.string(from: d)
            let letter = Self.dayFmt.string(from: d).uppercased()
            return DayDot(
                letter: letter,
                hasSession: dash.sessions[str] != nil,
                isToday: str == dash.todayDate
            )
        }
    }

    private var streak: Int {
        guard let todayMidnight = Self.isoFmt.date(from: dash.todayDate) else { return 0 }
        let base = todayMidnight.timeIntervalSince1970
        var count = 0
        for i in 0..<365 {
            let d = Date(timeIntervalSince1970: base - Double(i) * 86400)
            let str = Self.isoFmt.string(from: d)
            if dash.sessions[str] != nil { count += 1 } else { break }
        }
        return count
    }

    private var weekCount: Int { dots.filter { $0.hasSession }.count }

    private var streakMessage: String {
        if streak >= 30 { return "🏆 \(streak)j — légende en cours" }
        if streak >= 14 { return "🔥 \(streak)j — 2 semaines non-stop !" }
        if streak >= 7  { return "🔥 \(streak)j de suite — semaine parfaite !" }
        if streak >= 5  { return "🔥 \(streak)j d'affilée — momentum solide" }
        return ""
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(dot.hasSession ? Color.orange : Color.white.opacity(0.07))
                                    .frame(width: 30, height: 30)
                                if dot.isToday {
                                    Circle()
                                        .stroke(Color.orange.opacity(0.65), lineWidth: 1.5)
                                        .frame(width: 30, height: 30)
                                }
                                if dot.hasSession {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.black)
                                }
                            }
                            Text(dot.letter)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(dot.isToday ? .orange : Color.white.opacity(0.3))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("\(streak)j streak")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(streak >= 5 ? .orange : .white)
                    }
                    Text("\(weekCount)/7 jours")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.38))
                }
            }

            if !streakMessage.isEmpty {
                Text(streakMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            streak >= 5
                ? Color.orange.opacity(0.06)
                : Color(white: 0.07).opacity(0.7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(streak >= 5 ? Color.orange.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Today Metrics Row

private struct TodayMetricsRow: View {
    let dash: DashboardData
    let recovery: RecoveryEntry?
    let cardioData: [CardioEntry]

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var calories: Double { dash.nutritionTotals.calories ?? 0 }
    private var calGoal: Double { dash.nutritionSettings?.calories ?? 2000 }
    private var protein: Double { dash.nutritionTotals.proteines ?? 0 }
    private var protGoal: Double { dash.nutritionSettings?.proteines ?? 150 }

    private var weeklyCardioKm: Double {
        guard !cardioData.isEmpty else { return 0 }
        guard let todayMid = Self.isoFmt.date(from: dash.todayDate) else { return 0 }
        let cutoff = Self.isoFmt.string(from: Date(timeIntervalSince1970: todayMid.timeIntervalSince1970 - 6 * 86400))
        return cardioData.filter { ($0.date ?? "") >= cutoff }.compactMap { $0.distanceKm }.reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 8) {
            MetricMiniCard(
                icon: "flame.fill",
                iconColor: .orange,
                value: "\(Int(calories))",
                label: "/ \(Int(calGoal)) kcal",
                fill: calGoal > 0 ? min(calories / calGoal, 1.0) : 0,
                fillColor: .orange,
                compact: weeklyCardioKm > 0
            )

            MetricMiniCard(
                icon: "circle.hexagongrid.fill",
                iconColor: .cyan,
                value: "\(Int(protein))g",
                label: "/ \(Int(protGoal))g prot.",
                fill: protGoal > 0 ? min(protein / protGoal, 1.0) : 0,
                fillColor: .cyan,
                compact: weeklyCardioKm > 0
            )

            if weeklyCardioKm > 0 {
                MetricMiniCard(
                    icon: "figure.run",
                    iconColor: .green,
                    value: String(format: "%.1f", weeklyCardioKm),
                    label: "km · 7 jours",
                    fill: min(weeklyCardioKm / 20.0, 1.0),
                    fillColor: .green,
                    compact: true
                )
            } else if let sleep = recovery?.sleepHours {
                MetricMiniCard(
                    icon: "moon.zzz.fill",
                    iconColor: .indigo,
                    value: String(format: "%.1fh", sleep),
                    label: "sommeil",
                    fill: min(sleep / 8.0, 1.0),
                    fillColor: .indigo,
                    compact: false
                )
            }
        }
    }
}

private struct MetricMiniCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    let fill: Double
    let fillColor: Color
    var compact: Bool = false

    private var valueSize: CGFloat { compact ? 16 : 20 }
    private var labelSize: CGFloat { compact ? 10 : 11 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(value)
                    .font(.system(size: valueSize, weight: .black))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Text(label)
                .font(.system(size: labelSize))
                .foregroundColor(Color.white.opacity(0.4))
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(fill), height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Smart Insights Section

private struct SmartInsight {
    let icon: String
    let color: Color
    let title: String
    let detail: String
}

private struct SmartInsightsSection: View {
    let dash: DashboardData
    let weightsData: [String: WeightData]
    let sessionsData: [String: SessionEntry]
    let recovery: RecoveryEntry?
    let recoveryLog: [RecoveryEntry]
    let nutritionHistory: [NutritionDayHistory]

    private var ago14: String {
        let base = Date().timeIntervalSince1970
        return DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: base - 14 * 86400))
    }

    private var insights: [SmartInsight] {
        var result: [SmartInsight] = []
        let ns = dash.nutritionSettings

        // 1. Protein deficit + high training volume (high signal)
        if result.count < 2, let protTarget = ns?.proteines, protTarget > 0, nutritionHistory.count >= 3 {
            let recent = Array(nutritionHistory.prefix(3))
            let avgProt = recent.map { $0.proteines }.reduce(0, +) / Double(recent.count)
            if avgProt < protTarget * 0.80 {
                let sessions14d = sessionsData.filter { $0.key >= ago14 }.count
                if sessions14d >= 4 {
                    result.append(SmartInsight(
                        icon: "fork.knife",
                        color: .yellow,
                        title: "Protéines insuffisantes",
                        detail: "Moy. \(Int(avgProt))g/j vs \(Int(protTarget))g · \(sessions14d) séances en 14j"
                    ))
                } else {
                    result.append(SmartInsight(
                        icon: "circle.hexagongrid.fill",
                        color: .cyan,
                        title: "Protéines en dessous",
                        detail: "Moy. \(Int(avgProt))g/j vs \(Int(protTarget))g objectif sur 3j"
                    ))
                }
            }
        }

        // 2. Caloric deficit + HRV drop (high signal)
        if result.count < 2, let calTarget = ns?.calories, calTarget > 0, nutritionHistory.count >= 5 {
            let avgCal = Array(nutritionHistory.prefix(7)).map { $0.calories }.reduce(0, +) / Double(min(nutritionHistory.count, 7))
            let calRatio = avgCal / calTarget
            if calRatio < 0.87 {
                let hrvVals = recoveryLog.compactMap { $0.hrv }
                if hrvVals.count >= 10 {
                    let recent7 = hrvVals.prefix(7).reduce(0, +) / 7.0
                    let prev7   = Array(hrvVals.dropFirst(7).prefix(7)).reduce(0, +) / 7.0
                    if prev7 > 0 && recent7 < prev7 * 0.88 {
                        let drop = Int((1 - recent7 / prev7) * 100)
                        result.append(SmartInsight(
                            icon: "heart.slash.fill",
                            color: .red,
                            title: "Déficit + HRV en baisse",
                            detail: "\(Int(avgCal)) kcal/j (\(Int(calRatio * 100))%) · HRV −\(drop)% sur 7j"
                        ))
                    }
                }
            }
        }

        // 3. Sleep below threshold
        if result.count < 2 {
            if let sleep = recovery?.sleepHours, sleep < 6.5 {
                result.append(SmartInsight(
                    icon: "moon.zzz.fill",
                    color: .indigo,
                    title: "Récupération limitée",
                    detail: "\(String(format: "%.1f", sleep))h cette nuit — adapte l'intensité"
                ))
            }
        }

        // 4. Missed sessions this week
        if result.count < 2 {
            let scheduled = dash.schedule.count
            let logged = dash.sessions.count
            if scheduled >= 3 && logged < scheduled - 1 {
                result.append(SmartInsight(
                    icon: "calendar.badge.exclamationmark",
                    color: .yellow,
                    title: "Séances manquées",
                    detail: "\(logged)/\(scheduled) complétées cette semaine"
                ))
            }
        }

        return Array(result.prefix(2))
    }

    @ViewBuilder var body: some View {
        if !insights.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    HStack(spacing: 12) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(insight.color)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Text(insight.detail)
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(insight.color.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(insight.color.opacity(0.22), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

// MARK: - Topic Explorer

private struct CoachTopic {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let query: String
}

private let coachTopics: [CoachTopic] = [
    CoachTopic(
        icon: "chart.line.uptrend.xyaxis",
        color: .blue,
        title: "Progression",
        subtitle: "Forces & blocages",
        query: "Analyse ma progression sur les 30 derniers jours. Quels exercices progressent le plus ? Où est-ce que je stagne ?"
    ),
    CoachTopic(
        icon: "moon.zzz.fill",
        color: .indigo,
        title: "Récupération",
        subtitle: "HRV, sommeil, fatigue",
        query: "Évalue ma récupération actuelle à partir de mes données HRV et sommeil. Dois-je réduire mon volume ou puis-je pousser ?"
    ),
    CoachTopic(
        icon: "fork.knife",
        color: .orange,
        title: "Nutrition",
        subtitle: "Macros & performance",
        query: "Analyse le lien entre ma nutrition et mes performances. Quels ajustements me feraient progresser plus vite ?"
    ),
    CoachTopic(
        icon: "list.bullet.clipboard",
        color: .green,
        title: "Programme",
        subtitle: "Structure & phases",
        query: "Analyse mon programme d'entraînement actuel. Est-il bien structuré pour mon objectif ? Que changerais-tu ?"
    ),
    CoachTopic(
        icon: "bolt.fill",
        color: .red,
        title: "Intensité",
        subtitle: "RPE & surcharge",
        query: "Mes RPE récents sont-ils cohérents avec mes objectifs ? Est-ce que je m'entraîne avec la bonne intensité ?"
    ),
    CoachTopic(
        icon: "scalemass.fill",
        color: .teal,
        title: "Corps",
        subtitle: "Poids & composition",
        query: "Analyse la tendance de mon poids corporel et de ma composition. Suis-je sur la bonne trajectoire pour mon objectif ?"
    ),
]

private struct TopicExplorer: View {
    let onSelect: (String) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXPLORER")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundColor(Color.white.opacity(0.22))

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(coachTopics, id: \.title) { topic in
                    TopicCard(topic: topic, onTap: onSelect)
                }
            }
        }
    }
}

private struct TopicCard: View {
    let topic: CoachTopic
    let onTap: (String) -> Void

    var body: some View {
        Button { onTap(topic.query) } label: {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(topic.color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: topic.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(topic.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(topic.subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.32))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "0d0d1a"))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(topic.color.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Corner radius helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Program Preview Sheet

struct ProgramPreviewSheet: View {
    let program: GeneratedProgram
    var onApprove: (String) -> Void
    var onReject:  () -> Void

    @State private var selectedWeek   = 0
    @State private var expandedDays:  Set<Int> = [1]
    @State private var isApproving    = false
    @State private var approveError:  String?  = nil
    @State private var approveSuccess = false

    private var content: ProgramContent { program.programJson }

    private let phaseColors: [String: Color] = [
        "accumulation":   .blue,
        "intensification": .orange,
        "peak":           .red,
        "deload":         .green
    ]
    private let phaseLabels: [String: String] = [
        "accumulation":    "Accumulation",
        "intensification": "Intensification",
        "peak":            "Peak",
        "deload":          "Deload"
    ]

    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Text("4 semaines · 5 jours/semaine · Hypertrophie")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: onReject) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // Week picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(content.weeks) { week in
                            let phase = week.phase
                            let color = phaseColors[phase] ?? .purple
                            let label = phaseLabels[phase] ?? phase.capitalized
                            Button {
                                withAnimation(.spring(response: 0.3)) { selectedWeek = week.week - 1 }
                            } label: {
                                VStack(spacing: 3) {
                                    Text("S\(week.week)")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(label)
                                        .font(.system(size: 9, weight: .medium))
                                        .tracking(0.5)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedWeek == week.week - 1 ? color.opacity(0.25) : Color.white.opacity(0.05))
                                .foregroundColor(selectedWeek == week.week - 1 ? color : .gray)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                    selectedWeek == week.week - 1 ? color.opacity(0.6) : Color.clear, lineWidth: 1))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 10)

                // Muscle volume bar (current week)
                if !content.muscleVolume.isEmpty {
                    muscleVolumeRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }

                Divider().background(Color.white.opacity(0.07))

                // Days list
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        if selectedWeek < content.weeks.count {
                            let week = content.weeks[selectedWeek]
                            ForEach(week.days) { day in
                                DayCard(
                                    day: day,
                                    isExpanded: expandedDays.contains(day.day),
                                    weekPhase: week.phase
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        if expandedDays.contains(day.day) {
                                            expandedDays.remove(day.day)
                                        } else {
                                            expandedDays.insert(day.day)
                                        }
                                    }
                                }
                            }

                            // Global rationale
                            if !content.globalRationale.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Justification", systemImage: "lightbulb.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.indigo)
                                    Text(content.globalRationale)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.indigo.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.2), lineWidth: 1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 100)
                }

                Spacer(minLength: 0)
            }

            // Bottom approval bar
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    if let err = approveError {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                    }
                    if approveSuccess {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Programme ajouté dans Programme !")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 10)
                    } else {
                        HStack(spacing: 12) {
                            Button(action: onReject) {
                                Text("Rejeter")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.07))
                                    .foregroundColor(.gray)
                                    .cornerRadius(14)
                            }
                            Button {
                                approve()
                            } label: {
                                HStack(spacing: 8) {
                                    if isApproving {
                                        ProgressView().tint(.white).scaleEffect(0.85)
                                    } else {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(isApproving ? "Activation..." : "Approuver")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(colors: [.indigo, .purple],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(14)
                            }
                            .disabled(isApproving)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    Color(hex: "080810")
                        .shadow(color: .black.opacity(0.5), radius: 20, y: -8)
                )
            }
        }
    }

    private var muscleVolumeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VOLUME PAR MUSCLE")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.gray)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(content.muscleVolume.sorted(by: { $0.value.setsPerWeek > $1.value.setsPerWeek }), id: \.key) { muscle, vol in
                        let inRange = vol.setsPerWeek >= 10 && vol.setsPerWeek <= 20
                        VStack(spacing: 2) {
                            Text("\(vol.setsPerWeek)")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(inRange ? .green : .orange)
                            Text(muscle.prefix(6))
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                            Text("\(vol.frequency)×/sem")
                                .font(.system(size: 8))
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(inRange ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                            inRange ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private func approve() {
        isApproving  = true
        approveError = nil
        Task {
            do {
                let pid = try await APIService.shared.approveGeneratedProgram(program)
                await MainActor.run {
                    isApproving    = false
                    approveSuccess = true
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { onApprove(pid) }
            } catch {
                await MainActor.run {
                    isApproving  = false
                    approveError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Day Card

private struct DayCard: View {
    let day:       ProgramDay
    let isExpanded: Bool
    let weekPhase:  String
    let onTap:     () -> Void

    private let categoryIcons: [String: String] = [
        "compound_heavy":       "bolt.fill",
        "compound_hypertrophy": "flame.fill",
        "isolation":            "circle.fill"
    ]
    private let categoryColors: [String: Color] = [
        "compound_heavy":       .red,
        "compound_hypertrophy": .orange,
        "isolation":            .blue
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button(action: onTap) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.indigo.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Text("\(day.day)")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.indigo)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(day.muscleFocus.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(day.exercises.count) exo")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(Color.white.opacity(0.06))
                VStack(spacing: 0) {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { idx, ex in
                        ProgramExerciseRow(exercise: ex,
                                       categoryIcons: categoryIcons,
                                       categoryColors: categoryColors)
                        if idx < day.exercises.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.04))
                                .padding(.leading, 44)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(hex: "0d0d1a"))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.indigo.opacity(0.15), lineWidth: 1))
        .cornerRadius(14)
    }
}

private struct ProgramExerciseRow: View {
    let exercise:       ProgramExercise
    let categoryIcons:  [String: String]
    let categoryColors: [String: Color]

    @State private var showRationale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: categoryIcons[exercise.category] ?? "dumbbell.fill")
                    .font(.system(size: 10))
                    .foregroundColor(categoryColors[exercise.category] ?? .purple)
                    .frame(width: 24, height: 24)
                    .background((categoryColors[exercise.category] ?? .purple).opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(exercise.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(exercise.muscleGroup)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(exercise.sets)×\(exercise.reps)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white)
                    if let rest = exercise.restSec {
                        Text("\(rest / 60)'\(rest % 60 == 0 ? "" : "\(rest % 60)\"")")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.25)) { showRationale.toggle() }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(showRationale ? .indigo : .gray.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showRationale {
                Text(exercise.rationale)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 8)
            }
        }
    }
}
