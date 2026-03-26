import SwiftUI
import Combine

struct IntelligenceView: View {
    @State private var messages: [ChatMessage] = []
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
    @State private var recoveryData:    [RecoveryEntry]          = []
    @State private var weightsData:     [String: WeightData]     = [:]
    @State private var bodyWeightData:  [BodyWeightEntry]        = []
    @State private var muscleStatsData: [String: MuscleStatEntry] = [:]
    @State private var sessionsData:    [String: SessionEntry]   = [:]
    @State private var acwrData:        ACWRData?                = nil
    @State private var lssData:         LifeStressScore?         = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()

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

                    // Proposals sheet
                    if !proposals.isEmpty {
                        ProposalsCard(proposals: proposals, onDismiss: { proposals = [] })
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
                                                Button(action: { input = s }) {
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
            .task { await loadContextData() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !messages.isEmpty {
                        Button("Effacer") { messages = [] }.foregroundColor(.purple)
                    }
                }
            }
        }
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
    }

    private func buildContext() -> String {
        guard let dash = api.dashboard else { return "Données indisponibles." }
        var parts: [String] = []

        // Profile
        let p = dash.profile
        var profileParts: [String] = []
        if let name = p.name    { profileParts.append("Nom: \(name)") }
        if let w = p.weight     { profileParts.append("Poids: \(String(format: "%.0f", w)) lbs") }
        if let age = p.age      { profileParts.append("Âge: \(age) ans") }
        if let goal = p.goal    { profileParts.append("Objectif: \(goal)") }
        if let level = p.level  { profileParts.append("Niveau: \(level)") }
        if !profileParts.isEmpty { parts.append("PROFIL: \(profileParts.joined(separator: " | "))") }

        // Date / week
        parts.append("DATE: \(dash.todayDate) (\(dash.today)) — Semaine \(dash.week)")

        // LSS — état de récupération actuel
        if let lss = lssData {
            var lssParts = ["LSS: \(String(format: "%.0f", lss.score))/100 (\(lss.scoreColor))"]
            let c = lss.components
            if let v = c.sleepQuality    { lssParts.append("sommeil:\(String(format: "%.0f", v))") }
            if let v = c.hrvTrend        { lssParts.append("HRV:\(String(format: "%.0f", v))") }
            if let v = c.rhrTrend        { lssParts.append("RHR:\(String(format: "%.0f", v))") }
            if let v = c.subjectiveStress { lssParts.append("stress:\(String(format: "%.0f", v))") }
            if let v = c.trainingFatigue { lssParts.append("fatigue:\(String(format: "%.0f", v))") }
            var flags: [String] = []
            if lss.flags.hrvDrop          { flags.append("⚠️ HRV bas") }
            if lss.flags.sleepDeprivation { flags.append("⚠️ manque sommeil") }
            if lss.flags.trainingOverload { flags.append("⚠️ surcharge") }
            if !flags.isEmpty { lssParts.append(flags.joined(separator: " ")) }
            parts.append("RÉCUPÉRATION GLOBALE: \(lssParts.joined(separator: " | "))")
        }

        // ACWR — charge d'entraînement
        if let acwr = acwrData {
            let line = "ACWR: \(String(format: "%.2f", acwr.ratio)) — \(acwr.zone.label) | charge aiguë: \(String(format: "%.0f", acwr.acuteLoad)) / chronique: \(String(format: "%.0f", acwr.chronicLoad)) | conseil: \(acwr.zone.recommendation)"
            parts.append(line)
        }

        // Schedule
        let scheduleStr = dash.schedule.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }.joined(separator: " | ")
        if !scheduleStr.isEmpty { parts.append("HORAIRE: \(scheduleStr)") }

        // Recent sessions — use full history if available, else dashboard
        let allSessions = sessionsData.isEmpty ? dash.sessions : sessionsData
        let recentSessions = allSessions.sorted { $0.key > $1.key }.prefix(14)
        if !recentSessions.isEmpty {
            let lines = recentSessions.map { (date, s) -> String in
                var line = date
                if let exos = s.exos, !exos.isEmpty { line += " [\(exos.joined(separator: ", "))]" }
                if let rpe = s.rpe      { line += " RPE:\(String(format: "%.1f", rpe))" }
                if let sets = s.totalSets { line += " \(sets)sets" }
                if let dur = s.durationMin { line += " \(dur)min" }
                if let c = s.comment, !c.isEmpty { line += " \"\(c)\"" }
                return line
            }
            let count30 = allSessions.filter {
                $0.key >= DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 30 * 86400))
            }.count
            parts.append("SÉANCES RÉCENTES (\(count30) ce mois — 14 dernières):\n" + lines.joined(separator: "\n"))
        }

        // Recovery — last 10 entries
        let recentRecovery = Array(recoveryData.prefix(10))
        if !recentRecovery.isEmpty {
            let lines = recentRecovery.compactMap { r -> String? in
                guard let date = r.date else { return nil }
                var tokens: [String] = [date]
                if let v = r.sleepHours    { tokens.append("sommeil:\(String(format: "%.1f", v))h") }
                if let v = r.sleepQuality  { tokens.append("qualité:\(String(format: "%.0f", v))/10") }
                if let v = r.hrv           { tokens.append("HRV:\(String(format: "%.0f", v))ms") }
                if let v = r.restingHr     { tokens.append("RHR:\(String(format: "%.0f", v))bpm") }
                if let v = r.soreness      { tokens.append("courbatures:\(String(format: "%.0f", v))/10") }
                return tokens.joined(separator: " ")
            }
            if !lines.isEmpty { parts.append("RÉCUPÉRATION (10j):\n" + lines.joined(separator: "\n")) }
        }

        // Body weight trend
        let bwEntries = Array(bodyWeightData.prefix(5))
        if !bwEntries.isEmpty {
            let lines = bwEntries.map { e -> String in
                var s = "\(e.date): \(String(format: "%.1f", e.weight)) lbs"
                if let bf = e.bodyFat { s += " (\(String(format: "%.1f", bf))% BF)" }
                return s
            }
            if bwEntries.count >= 2 {
                let delta = bwEntries[0].weight - bwEntries[bwEntries.count - 1].weight
                let trend = delta > 0 ? "+\(String(format: "%.1f", delta)) lbs" : "\(String(format: "%.1f", delta)) lbs"
                parts.append("POIDS DE CORPS (tendance: \(trend)):\n" + lines.joined(separator: "\n"))
            } else {
                parts.append("POIDS DE CORPS:\n" + lines.joined(separator: "\n"))
            }
        }

        // Muscle volume breakdown (top 6)
        let topMuscles = muscleStatsData.sorted { $0.value.volume > $1.value.volume }.prefix(6)
        if !topMuscles.isEmpty {
            let lines = topMuscles.map { (m, s) in
                "\(m.capitalized): \(String(format: "%.0f", UnitSettings.shared.display(s.volume))) \(UnitSettings.shared.label) (\(s.sessions) séances)"
            }
            parts.append("VOLUME MUSCULAIRE:\n" + lines.joined(separator: "\n"))
        }

        // Nutrition today
        let nt = dash.nutritionTotals
        let ns = dash.nutritionSettings
        var nutriParts: [String] = []
        if let cal = nt.calories {
            var s = "Cal:\(String(format: "%.0f", cal))kcal"
            if let t = ns?.calories { s += "/\(String(format: "%.0f", t))" }
            nutriParts.append(s)
        }
        if let prot = nt.proteines {
            var s = "Prot:\(String(format: "%.0f", prot))g"
            if let t = ns?.proteines { s += "/\(String(format: "%.0f", t))g" }
            nutriParts.append(s)
        }
        if let carbs = nt.glucides { nutriParts.append("Carbs:\(String(format: "%.0f", carbs))g") }
        if let fat = nt.lipides    { nutriParts.append("Lipides:\(String(format: "%.0f", fat))g") }
        if !nutriParts.isEmpty { parts.append("NUTRITION AUJOURD'HUI: \(nutriParts.joined(separator: " | "))") }

        // Goals
        if !dash.goals.isEmpty {
            let goalStrs = dash.goals.sorted { $0.key < $1.key }.map { (k, v) in
                "\(k): \(String(format: "%.0f", v.current))/\(String(format: "%.0f", v.goal))lbs\(v.achieved ? " ✓" : "")"
            }
            parts.append("OBJECTIFS: " + goalStrs.joined(separator: " | "))
        }

        // Exercise weights (top 12 by current weight)
        let keyExos = weightsData.compactMap { (name, w) -> (String, WeightData)? in
            guard w.currentWeight != nil else { return nil }
            return (name, w)
        }.sorted { ($0.1.currentWeight ?? 0) > ($1.1.currentWeight ?? 0) }.prefix(12)

        if !keyExos.isEmpty {
            let lines = keyExos.map { (name, w) -> String in
                var line = "\(name): \(String(format: "%.0f", w.currentWeight ?? 0)) lbs"
                if let reps = w.lastReps   { line += " (\(reps))" }
                if let date = w.lastLogged { line += " — dernier: \(date)" }
                return line
            }
            parts.append("POIDS ACTUELS:\n" + lines.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n\n")
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let context = buildContext()
        messages.append(ChatMessage(role: .user, content: text))
        input = ""
        isLoading = true
        inputFocused = false

        // Build full conversation history (all messages incl. the one just appended)
        let history = messages.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }

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
                let (data, _) = try await URLSession.shared.data(for: req)
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

    private func loadProposals() {
        guard !isLoadingProposals else { return }
        let context = buildContext()
        isLoadingProposals = true
        proposals = []
        Task {
            do {
                let url = URL(string: "\(APIService.shared.baseURL)/api/ai/propose")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: ["context": context])
                let (data, _) = try await URLSession.shared.data(for: req)
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
                    await MainActor.run { proposals = parsed; isLoadingProposals = false }
                } else {
                    await MainActor.run { isLoadingProposals = false }
                }
            } catch {
                await MainActor.run { isLoadingProposals = false }
            }
        }
    }
}

// MARK: - Chat Models
struct ChatMessage: Identifiable {
    let id = UUID()
    enum Role { case user, assistant }
    let role: Role
    let content: String
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
