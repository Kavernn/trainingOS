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

                    // Proposals sheet
                    if !proposals.isEmpty {
                        ProposalsCard(proposals: proposals, onDismiss: { proposals = [] })
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
            }
            .onChange(of: messages) {
                if let data = try? JSONEncoder().encode(Array(messages.suffix(50))),
                   let str = String(data: data, encoding: .utf8) {
                    historyData = str
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !messages.isEmpty {
                        Button("Effacer") { messages = []; historyData = "[]" }.foregroundColor(.purple)
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
        guard let dash = api.dashboard else { return "no data" }
        var lines: [String] = []

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
