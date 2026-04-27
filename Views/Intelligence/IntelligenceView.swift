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
    @FocusState private var inputFocused: Bool
    @StateObject private var api = APIService.shared
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
    @State private var showMemory                                = false
    @StateObject private var memoryStore = CoachMemoryStore.shared
    @State private var nutritionHistory: [NutritionDayHistory]  = []
    @State private var showNutritionInsight                     = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810")
                    .ignoresSafeArea()
                    .onTapGesture { inputFocused = false }

                VStack(spacing: 0) {
                    // Propose button
                    Button(action: loadProposals) {
                        HStack {
                            if isLoadingProposals {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(isLoadingProposals ? "Analyse en cours..." : "Propositions de programme")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(10)
                    }
                    .disabled(isLoadingProposals)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // Narrative button
                    Button(action: loadNarrative) {
                        HStack {
                            if isLoadingNarrative {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: "text.quote")
                            }
                            Text(isLoadingNarrative ? "Rédaction en cours..." : "Récit de la semaine")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.teal.opacity(0.15))
                        .foregroundColor(.teal)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.teal.opacity(0.35), lineWidth: 1))
                        .cornerRadius(10)
                    }
                    .disabled(isLoadingNarrative)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    // Insights button
                    Button(action: loadInsights) {
                        HStack {
                            if isLoadingCorrelations {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: "chart.dots.scatter")
                            }
                            Text(isLoadingCorrelations ? "Analyse en cours..." : "Insights corrélations")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                        )
                        .cornerRadius(10)
                    }
                    .disabled(isLoadingCorrelations)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    // Generate program button
                    Button(action: generateProgram) {
                        HStack {
                            if isGeneratingProgram {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: "calendar.badge.plus")
                            }
                            Text(isGeneratingProgram ? "Génération en cours..." : "Générer un programme 4 semaines")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.indigo.opacity(0.18))
                        .foregroundColor(.indigo)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.indigo.opacity(0.4), lineWidth: 1))
                        .cornerRadius(10)
                    }
                    .disabled(isGeneratingProgram)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    // Program error
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
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
                        .cornerRadius(10)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                    }

                    // Re-open last generated program if exists
                    if generatedProgram != nil && !isGeneratingProgram {
                        Button {
                            showProgramPreview = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 11))
                                Text("Voir le dernier programme généré")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.indigo.opacity(0.8))
                        }
                        .padding(.top, 2)
                    }

                    // Nutrition × performance insight
                    if showNutritionInsight, let ni = nutritionPerfInsight {
                        NutritionPerfInsightCard(insight: ni, onDismiss: { showNutritionInsight = false })
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }

                    // Proposals sheet
                    if !proposals.isEmpty {
                        ProposalsCard(proposals: proposals, onDismiss: { proposals = []; proposalError = nil })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    } else if let err = proposalError {
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
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
                        .cornerRadius(10)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }

                    // Narrative card
                    if let text = narrative {
                        NarrativeCard(text: text, onDismiss: { narrative = nil })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }

                    // Insights sheet
                    if showInsights, let corr = correlations {
                        InsightsCard(data: corr, onDismiss: { showInsights = false })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }

                    Divider().background(Color.white.opacity(0.07))

                    // Chat history
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if messages.isEmpty {
                                    VStack(spacing: 16) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 48))
                                            .foregroundColor(.purple)
                                        Text("Coach IA")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("Pose une question sur ton entraînement, ta récupération, ou demande une analyse de tes progrès.")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                            .multilineTextAlignment(.center)

                                        VStack(spacing: 8) {
                                            ForEach(suggestions, id: \.self) { s in
                                                Button(action: { input = s; inputFocused = true }) {
                                                    Text(s)
                                                        .font(.system(size: 13))
                                                        .foregroundColor(.purple)
                                                        .padding(.horizontal, 14)
                                                        .padding(.vertical, 8)
                                                        .background(Color.purple.opacity(0.08))
                                                        .cornerRadius(20)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 32)
                                    .padding(.horizontal, 20)
                                }

                                ForEach(messages) { msg in
                                    ChatBubble(message: msg)
                                        .id(msg.id)
                                }

                                if isLoading {
                                    HStack {
                                        TypingIndicator()
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .id("loading")
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .onChange(of: messages.count) {
                            if let last = messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onChange(of: isLoading) {
                            if isLoading {
                                withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }

                    // Input bar
                    HStack(spacing: 10) {
                        TextField("Demande à ton coach...", text: $input, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(hex: "11111c"))
                            .cornerRadius(22)
                            .lineLimit(1...4)
                            .focused($inputFocused)
                            .submitLabel(.send)
                            .onSubmit { if !input.isEmpty && !isLoading { sendMessage() } }

                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(input.isEmpty || isLoading ? .gray : .purple)
                        }
                        .disabled(input.isEmpty || isLoading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "080810"))
                }
            }
            .navigationTitle("Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Restore persisted chat history
                if let data = historyData.data(using: .utf8),
                   let saved = try? JSONDecoder().decode([ChatMessage].self, from: data), !saved.isEmpty {
                    messages = saved
                }
                await loadContextData()
                generatedProgram = try? await APIService.shared.fetchLatestGeneratedProgram()
            }
            .onChange(of: messages) {
                if let data = try? JSONEncoder().encode(Array(messages.suffix(50))),
                   let str = String(data: data, encoding: .utf8) {
                    historyData = str
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showMemory = true
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
                    if !messages.isEmpty {
                        Button("Effacer") { messages = []; historyData = "[]" }.foregroundColor(.purple)
                    }
                }
            }
            .fullScreenCover(isPresented: $showProgramPreview) {
                if let gp = generatedProgram {
                    ProgramPreviewSheet(program: gp) { approvedId in
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
            .sheet(isPresented: $showMemory) {
                CoachMemoryView()
            }
        }
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

    private let suggestions = [
        "Analyse mes progrès récents",
        "Comment améliorer ma récupération ?",
        "Suis-je en surcharge progressive ?",
        "Quels muscles devrais-je prioriser ?"
    ]

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
            // Fallback: individual network calls
            async let r = try? APIService.shared.fetchRecoveryData()
            async let w = try? APIService.shared.fetchWeights()
            let (recovery, weights) = await (r, w)
            await MainActor.run {
                recoveryData = recovery ?? []
                weightsData  = weights ?? [:]
            }
        }

        // 2. ACWR + LSS in parallel (lightweight, separate endpoints)
        async let acwrTask = try? APIService.shared.fetchACWR()
        async let lssTask  = try? APIService.shared.fetchLifeStressScore()
        let (acwrResult, lssResult) = await (acwrTask, lssTask)
        await MainActor.run {
            acwrData = acwrResult
            lssData  = lssResult
        }

        // 3. Nutrition history for nutrition×perf insight
        if let hist = try? await APIService.shared.fetchNutritionHistory(), !hist.isEmpty {
            await MainActor.run { nutritionHistory = hist; showNutritionInsight = true }
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

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let context = buildContext()
        messages.append(ChatMessage(role: .user, content: text))
        input = ""
        isLoading = true
        inputFocused = false

        // Keep last 12 messages (6 exchanges) — server caps at 20 but less is cheaper
        let history = messages.suffix(12).map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }

        Task {
            do {
                let url = URL(string: "\(APIService.shared.baseURL)/api/ai/coach")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
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
        let y = Calendar.current.component(.yearForWeekOfYear, from: Date())
        let w = Calendar.current.component(.weekOfYear, from: Date())
        return String(format: "%04d-W%02d", y, w)
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
}

// MARK: - Chat Models
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    enum Role: String, Codable { case user, assistant }
    let role: Role
    let content: String
    init(role: Role, content: String) { self.id = UUID(); self.role = role; self.content = content }
}

struct AIProposal: Identifiable {
    let id = UUID()
    let jour: String
    let action: String
    let exercise: String
    let scheme: String
    let reason: String
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                ZStack {
                    Circle().fill(Color.purple.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "brain.head.profile").font(.system(size: 12)).foregroundColor(.purple)
                }
            }

            Text(message.content)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.purple : Color(hex: "11111c"))
                .cornerRadius(18, corners: isUser ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }
}

struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.purple.opacity(phase == i ? 1 : 0.3))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "11111c"))
        .cornerRadius(18)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                phase = (phase + 1) % 3
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
