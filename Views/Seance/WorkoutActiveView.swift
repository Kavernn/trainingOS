import SwiftUI

// MARK: - Workout Seance (Upper/Lower)
struct GhostData {
    let date: String
    let volume: Double
    let rpe: Double?
    let sets: Int?
}

struct SessionRecapSnapshot {
    let sessionName: String
    let durationMin: Double
    let logResults: [String: ExerciseLogResult]
    let exercises: [String]
    let rpe: Double
    let comment: String
    let energyPre: Int
}

struct WorkoutSeanceView: View {
    let data: SeanceData
    @ObservedObject var vm: SeanceViewModel
    var isSecondSession: Bool = false
    var isBonusSession: Bool = false
    @State private var rpe: Double = 7
    @State private var comment = ""
    @State private var showFinish = false
    @State private var showFinishConfirm = false
    @State private var showUnloggedWarning = false
    @State private var confirmedFromWarning = false
    @State private var showSummary = false
    @State private var ghostData: GhostData? = nil
    // W-C3 — showGhost persists per session so the dismissed banner doesn't reappear
    @State private var showGhost: Bool = {
        // Default: show. Will be corrected in onAppear with session-specific key.
        return true
    }()
    @State private var ghostBeaten = false

    // Programme edit
    @State private var localProgram: [String: String] = [:]
    @State private var exerciseOrder: [String] = []
    @State private var inventoryTypes: [String: String] = [:]
    @State private var inventoryTracking: [String: String] = [:]
    @State private var inventoryRest: [String: Int] = [:]
    @State private var inventoryHints: [String: String] = [:]
    @State private var sessionSupersets: [String: SupersetEntry] = [:]
    @State private var draggingName: String?
    @State private var dragOffset: CGFloat = 0
    @State private var cardHeights: [String: CGFloat] = [:]
    @State private var inventory: [String] = []
    @State private var inventoryMuscles: [String: [String]] = [:]
    @State private var inventoryPatterns: [String: String] = [:]

    // Swap d'exercice à la volée
    @State private var swappedExercises: [String: String] = [:]   // replacementName → originalName
    @State private var swapWeightData: [String: WeightData] = [:]
    @State private var swapConversions: [String: EquipmentConversion] = [:]
    @State private var swapPending: String? = nil                  // original name awaiting swap
    @State private var showSwapSheet = false
    @State private var showCreateVariant = false

    @State private var addTarget: SeanceName?
    @State private var showAddLocal = false   // session-only add (doesn't touch programme)
    @State private var editTarget: ExerciseTarget?
    @State private var isEditMode = false
    @State private var orderSaveError = false
    @State private var expandedExercises: Set<String> = []
    @State private var lastOpenedExercise: String? = nil
    @State private var scrollProxy: ScrollViewProxy? = nil
    @ObservedObject private var timer = RestTimerManager.shared
    @Environment(\.scenePhase) private var scenePhase

    // Progression
    @State private var showProgressionSheet = false
    @State private var progressionSuggestions: [ProgressionSuggestion] = []

    // Session recap
    @State private var showRecap = false
    @State private var recapSnapshot: SessionRecapSnapshot? = nil
    @State private var didLoadPreCoaching = false
    @State private var showPRCelebration = false

    // Energy pre-session
    @AppStorage("energy_pre_value") private var energyPre: Int = 3
    @State private var showEnergyPreSheet = false
    @AppStorage("energy_pre_date") private var energyPreDate = ""
    @State private var energyConfirmed = false

    // Mid-workout intelligence
    @State private var dismissedAdviceId: String? = nil

    // Session override (calendrier)
    @State private var showSessionPicker = false

    // Optional add-ons
    @State private var showAddCardio = false
    @State private var showAddHIIT   = false
    @State private var cardioCount   = 0
    @State private var hiitCount     = 0
    @State private var lastScrollY: CGFloat? = nil

    // AI analysis pre-load
    @State private var preloadedAIAnalysis: String? = nil
    @State private var isPreloadingAI = false

    // Toast
    @State private var toast: ToastMessage? = nil

    // Swap inline banner (Fix #11)
    @State private var lastSwap: (old: String, new: String)? = nil

    // Readiness score
    @State private var readiness: ReadinessScore? = nil
    @ObservedObject private var appState = AppState.shared

    // W-D11 — abandon session
    @State private var showAbandonAlert = false
    @State private var allLoggedPulse = false

    // Warmup guidance banner — shown pre-session, dismissable
    @State private var showWarmupBanner = true

    /// Moyenne des RPE par exercice loggés — fallback 7 si aucun
    private var computedSessionRPE: Double {
        let vals = vm.logResults.values.compactMap(\.rpe)
        guard !vals.isEmpty else { return 7.0 }
        return (vals.reduce(0, +) / Double(vals.count) * 2).rounded() / 2  // arrondi au 0.5
    }

    private func preloadAIAnalysis() {
        guard !isPreloadingAI, preloadedAIAnalysis == nil, !vm.logResults.isEmpty else { return }
        isPreloadingAI = true
        let logRes = vm.logResults
        let elapsed = Date().timeIntervalSince(vm.sessionStart) / 60
        let rpeVal = computedSessionRPE
        let summary = logRes.map { k, v in
            "\(k): \(v.reps) @ \(String(format: "%.0f", v.weight))lbs RPE\(String(format: "%.1f", v.rpe ?? rpeVal))"
        }.joined(separator: ", ")
        let prompt = "Séance terminée en \(Int(elapsed)) min. Exercices: \(summary). RPE global: \(String(format: "%.1f", rpeVal)). Donne une analyse courte (3-4 phrases) : points positifs, point à améliorer, conseil pour la prochaine séance."

        // W-B4 — apply 10-second timeout; set analysis to nil and stop spinner if exceeded
        let apiTask = Task {
            do {
                let url = URL(string: "\(APIService.shared.baseURL)/api/ai/coach")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: [
                    "context": "Post-session analysis",
                    "messages": [["role": "user", "content": prompt]]
                ])
                let (data, _) = try await URLSession.authed.data(for: req)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let reply = json["response"] as? String {
                    await MainActor.run { preloadedAIAnalysis = reply; isPreloadingAI = false }
                } else { await MainActor.run { isPreloadingAI = false } }
            } catch {
                await MainActor.run {
                    isPreloadingAI = false
                    toast = ToastMessage(message: "Analyse IA indisponible", style: .error)
                }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if !apiTask.isCancelled {
                apiTask.cancel()
                await MainActor.run {
                    if isPreloadingAI {
                        isPreloadingAI = false
                        preloadedAIAnalysis = nil
                    }
                }
            }
        }
    }

    private var warmupGuidance: String? {
        let warmupMap: [String: String] = [
            "squat":           "Barre vide × 10 → 50% × 5 → 70% × 3, puis working sets",
            "hinge":           "Barre vide × 10 → 50% × 5 → 70% × 3, puis working sets",
            "horizontal_push": "Band pull-aparts × 15, barre vide × 10 → 50% × 5, puis working sets",
            "vertical_push":   "Rotations d'épaules × 15, 50% × 8 → 70% × 5, puis working sets",
            "horizontal_pull": "Band pull-aparts × 15, 50% × 8 → 70% × 5, puis working sets",
            "vertical_pull":   "Mobilité épaules × 10, 50% × 8 → 70% × 5, puis working sets",
            "carry":           "Mobilité hanches × 10, 50% × 5, puis working sets",
            "core":            "Activation : dead bug × 10, planche 20s, puis working sets"
        ]
        for name in exerciseOrder {
            if let pattern = inventoryPatterns[name], let guidance = warmupMap[pattern] {
                return guidance
            }
        }
        return nil
    }

    private var exercises: [(String, String)] {
        let ordered = exerciseOrder.filter { localProgram[$0] != nil }
        let extra   = localProgram.keys.filter { !exerciseOrder.contains($0) }.sorted()
        return (ordered + extra).compactMap { name -> (String, String)? in
            guard let scheme = localProgram[name] else { return nil }
            return (name, scheme)
        }
    }
    private var currentVolume: Double {
        vm.logResults.values.reduce(0.0) { acc, r in
            let s = r.reps.trimmingCharacters(in: .whitespaces).lowercased()
            let reps: Double
            if s.contains(",") {
                reps = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
            } else if let rx = s.range(of: "x"),
                      let sets = Double(s[s.startIndex..<rx.lowerBound]),
                      let rep  = Double(s[rx.upperBound...]) {
                reps = sets * rep
            } else {
                reps = Double(s) ?? 0
            }
            return acc + r.weight * reps
        }
    }

    private var midWorkoutAdvice: MidWorkoutAdvice? {
        let logged    = vm.logResults.count
        let total     = exercises.count
        let remaining = total - logged
        let durationMin = Date().timeIntervalSince(vm.sessionStart) / 60
        guard logged >= 2 else { return nil }

        if computedSessionRPE >= 9.0 && remaining > 0 {
            return MidWorkoutAdvice(
                id: "high_rpe",
                icon: "exclamationmark.triangle.fill", color: .red,
                title: "Fatigue critique",
                message: "Effort très élevé (RIR \(RPEHelper.rirFromRPE(computedSessionRPE)) / RPE \(String(format: "%.0f", computedSessionRPE))) — réduis les charges de 5-10% sur les \(remaining) exercice(s) restant(s), ou supprime une série."
            )
        }
        if computedSessionRPE <= 6.0 && remaining > 1 {
            return MidWorkoutAdvice(
                id: "low_rpe",
                icon: "bolt.fill", color: .green,
                title: "Tu as de la réserve",
                message: "Effort faible (RIR 4+ / RPE \(String(format: "%.0f", computedSessionRPE))) — tu peux monter les charges de 2.5–5% sur les prochains exercices."
            )
        }
        if durationMin > 90 && remaining > 0 {
            return MidWorkoutAdvice(
                id: "too_long",
                icon: "clock.badge.exclamationmark.fill", color: .orange,
                title: "Séance longue — \(Int(durationMin)) min",
                message: "Les \(remaining) exercice(s) restant(s) sont optionnels. La qualité prime sur la quantité après 90 min."
            )
        }
        if ghostBeaten && remaining > 0 {
            return MidWorkoutAdvice(
                id: "ghost_beaten",
                icon: "figure.run", color: .purple,
                title: "Fantôme battu !",
                message: "Volume déjà supérieur à ta dernière séance — reste prudent sur l'intensité jusqu'à la fin."
            )
        }
        return nil
    }

    private struct GhostSnapshot: Codable {
        let sessions: [String: SessionEntry]
    }

    private func computeGhost() {
        if CacheService.shared.load(for: "stats_data") == nil {
            Task { try? await APIService.shared.fetchStatsData(); computeGhost() }
            return
        }
        guard let cached  = CacheService.shared.load(for: "stats_data"),
              let snap    = try? JSONDecoder().decode(GhostSnapshot.self, from: cached)
        else { return }
        let currentExos = Set(localProgram.keys.map { $0.lowercased() })
        guard !currentExos.isEmpty else { return }

        let best = snap.sessions
            .filter { $0.key != data.todayDate && ($0.value.sessionVolume ?? 0) > 0 }
            .compactMap { date, s -> (String, SessionEntry)? in
                guard let exos = s.exos else { return nil }
                let overlap = currentExos.intersection(Set(exos.map { $0.lowercased() })).count
                guard Double(overlap) / Double(min(currentExos.count, exos.count)) >= 0.5 else { return nil }
                return (date, s)
            }
            .max { ($0.1.sessionVolume ?? 0) < ($1.1.sessionVolume ?? 0) }

        if let (date, s) = best, let vol = s.sessionVolume {
            ghostData = GhostData(date: date, volume: vol, rpe: s.rpe, sets: s.totalSets)
        }
    }

    @ViewBuilder private var sessionSummaryTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VUE RÉSUMÉ")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("\(vm.logResults.count)/\(exercises.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(vm.logResults.count == exercises.count ? .green : .orange)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            ForEach(exercises, id: \.0) { name, scheme in
                let r = vm.logResults[name]
                HStack(spacing: 10) {
                    Image(systemName: r != nil ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(r != nil ? .green : .gray.opacity(0.3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 13, weight: r != nil ? .semibold : .regular))
                            .foregroundColor(r != nil ? .white : .gray)
                        Text(scheme).font(.system(size: 10)).foregroundColor(.gray)
                    }
                    Spacer()
                    if let r = r {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(UnitSettings.shared.format(r.weight))
                                .font(.system(size: 12, weight: .bold)).foregroundColor(.orange)
                            Text(r.reps).font(.system(size: 10)).foregroundColor(.gray)
                        }
                    } else {
                        Text("—").font(.system(size: 12)).foregroundColor(.gray.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
            }
        }
        .background(Color.appCard).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var exerciseSection: some View {
        if showSummary {
            sessionSummaryTable
        } else if isEditMode {
            VStack(spacing: 0) {
                ForEach(exercises, id: \.0) { name, scheme in
                    editModeRow(name: name, scheme: scheme)
                }
                Button { addTarget = SeanceName(id: data.today) } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundColor(.orange)
                        Text("Ajouter un exercice")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Color.appCard)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 16)
        } else {
            let sepIdx = firstUnloggedItemIndex
            VStack(spacing: 8) {
                ForEach(Array(exerciseRenderItems.enumerated()), id: \.element.id) { idx, item in
                    if let s = sepIdx, idx == s {
                        remainingSectionHeader
                    }
                    renderExerciseItem(item)
                }
            }
            .onPreferenceChange(CardHeightKey.self) { cardHeights.merge($0) { $1 } }

            if orderSaveError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    Text("Ordre non sauvegardé").font(.system(size: 12)).foregroundColor(.red)
                    Spacer()
                    Button("Réessayer") {
                        orderSaveError = false
                        Task { await saveOrder(exerciseOrder) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                    Button { orderSaveError = false } label: {
                        Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 16)
            }

            // Add exercise — session-local only, doesn't modify the programme
            Button { showAddLocal = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundColor(.orange.opacity(0.7))
                    Text("Ajouter un exercice")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.06))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(SpringButtonStyle())
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func editModeRow(name: String, scheme: String) -> some View {
        HStack(spacing: 12) {
            Button { Task { await deleteExercise(name) } } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22)).foregroundColor(.red)
            }
            Button {
                editTarget = ExerciseTarget(seance: data.today, exercise: name, scheme: scheme)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 14)).foregroundColor(.white)
                        Text(scheme).font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 13)).foregroundColor(.orange.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.appCard)
        Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 16)
    }

    // MARK: - Section separator helpers (PROB-11)

    private func isItemLogged(_ item: ExerciseRenderItem) -> Bool {
        switch item {
        case .superset(_, _, let entry, _, _, _):
            return vm.logResults[entry.a] != nil || vm.logResults[entry.b] != nil
        case .solo(let name, _, _):
            return vm.logResults[name] != nil
        }
    }

    private var firstUnloggedItemIndex: Int? {
        let logged = vm.logResults.count
        guard logged > 0, logged < exercises.count else { return nil }
        return exerciseRenderItems.firstIndex(where: { !isItemLogged($0) })
    }

    @ViewBuilder private var remainingSectionHeader: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            Text("À FAIRE")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray.opacity(0.4))
                .fixedSize()
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .transition(.opacity)
    }

    // MARK: - Superset render model

    private enum ExerciseRenderItem: Identifiable {
        case superset(id: String, group: String, entry: SupersetEntry, schemeA: String, schemeB: String, nextName: String?)
        case solo(name: String, scheme: String, next: String?)
        var id: String {
            switch self {
            case .superset(let id, _, _, _, _, _): return id
            case .solo(let name, _, _): return name
            }
        }
    }

    private var exerciseRenderItems: [ExerciseRenderItem] {
        guard !sessionSupersets.isEmpty else {
            let exs = exercises
            return exs.enumerated().map { idx, pair in
                .solo(name: pair.0, scheme: pair.1, next: idx + 1 < exs.count ? exs[idx + 1].0 : nil)
            }
        }
        var ssLookup: [String: (group: String, entry: SupersetEntry)] = [:]
        for (group, entry) in sessionSupersets {
            ssLookup[entry.a] = (group, entry)
            ssLookup[entry.b] = (group, entry)
        }
        var rendered = Set<String>()
        var items: [ExerciseRenderItem] = []
        let exs = exercises
        for (idx, pair) in exs.enumerated() {
            let name = pair.0
            guard !rendered.contains(name) else { continue }
            if let ss = ssLookup[name], ss.entry.a == name {
                let bName = ss.entry.b
                let schemeB = exs.first(where: { $0.0 == bName })?.1 ?? ""
                let bIdx = exs.firstIndex(where: { $0.0 == bName }) ?? idx
                let nextAfterB = bIdx + 1 < exs.count ? exs[bIdx + 1].0 : nil
                items.append(.superset(id: "ss_\(ss.group)", group: ss.group, entry: ss.entry,
                                       schemeA: pair.1, schemeB: schemeB, nextName: nextAfterB))
                rendered.insert(name)
                rendered.insert(bName)
            } else {
                let next = idx + 1 < exs.count ? exs[idx + 1].0 : nil
                items.append(.solo(name: name, scheme: pair.1, next: next))
                rendered.insert(name)
            }
        }
        return items
    }

    @ViewBuilder
    private func renderExerciseItem(_ item: ExerciseRenderItem) -> some View {
        switch item {
        case .superset(_, let group, let entry, let schemeA, let schemeB, let nextName):
            supersetBlock(group: group, entry: entry, schemeA: schemeA, schemeB: schemeB, nextName: nextName)
        case .solo(let name, let scheme, let next):
            draggableCard(name: name, scheme: scheme, nextExerciseName: next)
        }
    }

    @ViewBuilder
    private func supersetBlock(group: String, entry: SupersetEntry, schemeA: String, schemeB: String, nextName: String?) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(group)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                Text("Superset")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                    Text("120 s repos")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.gray)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        _ = sessionSupersets.removeValue(forKey: entry.a)
                    }
                } label: {
                    Text("Dissocier")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)

            draggableCard(name: entry.a, scheme: schemeA, nextExerciseName: nil, forceNoRest: true)

            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10))
                Text("enchaîner")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.orange.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .center)

            draggableCard(name: entry.b, scheme: schemeB, nextExerciseName: nextName,
                          restOverride: 120)
        }
    }

    @ViewBuilder
    private func draggableCard(name: String, scheme: String, nextExerciseName: String? = nil,
                               forceNoRest: Bool = false, restOverride: Int? = nil) -> some View {
        let isDragging = draggingName == name
        let shift = shiftY(for: name)
        let originalName = swappedExercises[name]
        let effectiveWeightData = swapWeightData[name] ?? data.weights[name]
        let card = ExerciseCard(
            name: name,
            scheme: scheme,
            weightData: effectiveWeightData,
            equipmentType: equipmentType(for: name),
            trackingType: trackingType(for: name),
            bodyWeight: APIService.shared.dashboard?.profile.weight ?? 0,
            isSecondSession: isSecondSession,
            isBonusSession: isBonusSession,
            restSeconds: forceNoRest ? nil : (restOverride ?? restSeconds(for: name)),
            prescription: data.prescriptions?[name],
            suggestion: data.exerciseSuggestions?[name],
            hint: inventoryHints[name],
            logResult: $vm.logResults[name],
            onLogged: {
                let loggedNames = Set(vm.logResults.keys)
                if let next = exercises.first(where: { !loggedNames.contains($0.0) && $0.0 != name }) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        expandedExercises.insert(next.0)
                        lastOpenedExercise = next.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            scrollProxy?.scrollTo(next.0, anchor: .top)
                        }
                    }
                }
            },
            isExpanded: expandedExercises.contains(name),
            isFocused: name == lastOpenedExercise,
            onToggle: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    if expandedExercises.contains(name) {
                        expandedExercises.remove(name)
                        if lastOpenedExercise == name { lastOpenedExercise = expandedExercises.first }
                    } else {
                        expandedExercises.insert(name)
                        lastOpenedExercise = name
                    }
                }
            },
            nextExerciseName: nextExerciseName,
            isReplaced: originalName != nil,
            originalName: originalName,
            onSwap: {
                swapPending = name
                showSwapSheet = true
            },
            movementPattern: inventoryPatterns[name] ?? ""
        )
        card
            .id(name)
            .padding(.horizontal, 16)
            .background(GeometryReader { geo in
                Color.clear.preference(key: CardHeightKey.self, value: [name: geo.size.height])
            })
            .overlay(alignment: .topLeading) {
                // Gesture is restricted to the drag handle area so ScrollView can scroll freely
                Color.clear
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(.leading, 16)
                    .gesture(dragGesture(for: name))
            }
            .scaleEffect(isDragging ? 1.03 : 1.0, anchor: .center)
            .shadow(color: isDragging ? .black.opacity(0.45) : .clear, radius: isDragging ? 18 : 0)
            .offset(y: isDragging ? dragOffset : shift)
            .zIndex(isDragging ? 1 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: shift)
            .animation(.spring(response: 0.2, dampingFraction: 0.9), value: isDragging)
    }

    private func dragGesture(for name: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if draggingName == nil {
                        draggingName = name
                        triggerImpact(style: .medium)
                    }
                    dragOffset = drag.translation.height
                default:
                    break
                }
            }
            .onEnded { _ in
                if let dragging = draggingName {
                    let to = proposedDropIndex
                    if let from = exerciseOrder.firstIndex(of: dragging), from != to {
                        withAnimation(.spring(response: 0.28)) {
                            exerciseOrder.move(fromOffsets: IndexSet(integer: from),
                                               toOffset: to > from ? to + 1 : to)
                        }
                        let newOrder = exerciseOrder
                        Task { await saveOrder(newOrder) }
                    }
                }
                withAnimation(.spring(response: 0.28)) {
                    draggingName = nil
                    dragOffset   = 0
                }
            }
    }

    // MARK: - Drag helpers

    private var proposedDropIndex: Int {
        guard let name = draggingName,
              let fromIdx = exerciseOrder.firstIndex(of: name) else { return 0 }
        let slotH = (cardHeights[name] ?? 200) + 12
        let steps = Int((dragOffset / slotH).rounded())
        return max(0, min(exerciseOrder.count - 1, fromIdx + steps))
    }

    private func shiftY(for cardName: String) -> CGFloat {
        guard let dragging = draggingName, dragging != cardName,
              let from = exerciseOrder.firstIndex(of: dragging),
              let idx  = exerciseOrder.firstIndex(of: cardName) else { return 0 }
        let to = proposedDropIndex
        let h  = (cardHeights[dragging] ?? 200) + 12
        if from < to, idx > from, idx <= to { return -h }
        if from > to, idx >= to,  idx < from { return  h }
        return 0
    }

    @ViewBuilder private var optionalAddonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPTIONNEL")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 10) {
                Button(action: { showAddCardio = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: cardioCount > 0 ? "plus.circle.fill" : "figure.run")
                            .font(.system(size: 14))
                        Text(cardioCount > 0 ? "Cardio ×\(cardioCount) — Ajouter +" : "Ajouter Cardio")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(cardioCount > 0 ? Color.green.opacity(0.12) : Color.appCard)
                    .foregroundColor(cardioCount > 0 ? .green : .blue)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                        cardioCount > 0 ? Color.green.opacity(0.3) : Color.blue.opacity(0.2), lineWidth: 1))
                }

                Button(action: { showAddHIIT = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: hiitCount > 0 ? "plus.circle.fill" : "bolt.fill")
                            .font(.system(size: 14))
                        Text(hiitCount > 0 ? "HIIT ×\(hiitCount) — Ajouter +" : "Ajouter HIIT")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(hiitCount > 0 ? Color.green.opacity(0.12) : Color.appCard)
                    .foregroundColor(hiitCount > 0 ? .green : .red)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                        hiitCount > 0 ? Color.green.opacity(0.3) : Color.red.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var exerciseNavigator: some View {
        if exercises.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { _, ex in
                        let isLogged = vm.logResults[ex.0] != nil
                        Button {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                scrollProxy?.scrollTo(ex.0, anchor: .top)
                            }
                        } label: {
                            Circle()
                                .fill(isLogged ? Color.green : Color.white.opacity(0.22))
                                .frame(width: 8, height: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 22)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                showSessionPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(data.today.uppercased())
                                        .font(.system(size: 13, weight: .black))
                                        .tracking(3)
                                        .foregroundColor(.orange)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.orange.opacity(0.6))
                                }
                            }
                            .buttonStyle(.plain)
                            if let meso = data.mesocycle {
                                MesocycleChip(info: meso)
                            } else {
                                Text("Semaine \(data.week)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        if vm.sessionStarted {
                            TimelineView(.periodic(from: vm.sessionStart, by: 1)) { ctx in
                                let elapsed = max(0, ctx.date.timeIntervalSince(vm.sessionStart))
                                let mm = Int(elapsed) / 60
                                let ss = Int(elapsed) % 60
                                HStack(spacing: 3) {
                                    Image(systemName: "clock").font(.system(size: 10))
                                    Text(String(format: "%d:%02d", mm, ss))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.cyan.opacity(0.75))
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(Color.cyan.opacity(0.08))
                                .cornerRadius(6)
                            }
                            .transition(.opacity)
                        }
                        Button {
                            withAnimation { showSummary.toggle() }
                        } label: {
                            Image(systemName: showSummary ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                                .font(.system(size: 20))
                                .foregroundColor(showSummary ? .cyan : .cyan.opacity(0.5))
                        }
                        .padding(.leading, 8)
                        Button {
                            withAnimation { isEditMode.toggle() }
                        } label: {
                            Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil.circle")
                                .font(.system(size: 20))
                                .foregroundColor(isEditMode ? .green : .orange)
                        }
                        .padding(.leading, 8)
                        // W-D11 — abandon session button
                        if vm.sessionStarted {
                            Button {
                                showAbandonAlert = true
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(.red.opacity(0.6))
                            }
                            .padding(.leading, 8)
                        }
                    }
                    // Progress
                    let done = vm.logResults.count
                    let total = exercises.count
                    HStack {
                        Text(done == total && total > 0 ? "Tous les exercices loggés ✓" : "\(done) / \(total) exercices")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(done == total && total > 0 ? .green : .gray)
                            .scaleEffect(allLoggedPulse ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: allLoggedPulse)
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 4)
                        .overlay(
                            GeometryReader { g in
                                let fraction: CGFloat = total > 0 ? CGFloat(done) / CGFloat(total) : 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(done == total && total > 0 ? Color.green : Color.orange)
                                    .frame(width: g.size.width * fraction)
                                    .animation(.spring(response: 0.5), value: done)
                            },
                            alignment: .leading
                        )

                    // Readiness chip
                    if let r = readiness, let score = r.score {
                        ReadinessChip(score: score, label: r.label, color: r.color)
                    }

                    // Macro nutrition hint — lecture seule, calculé depuis DashboardViewModel
                    if let hint = appState.macroSessionHint {
                        HStack(spacing: 6) {
                            Image(systemName: hint.isAbove ? "fork.knife" : "exclamationmark.circle")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(hint.isAbove ? .green : .orange)
                            Text(hint.isAbove
                                 ? "Bonne nutrition hier — conditions optimales"
                                 : "Nutrition de la veille sous ton seuil optimal (\(hint.macro))")
                                .font(.system(size: 11))
                                .foregroundColor(hint.isAbove ? .green.opacity(0.85) : .orange.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                        }
                    }

                    // Énergie inline — remplace la modal bloquante
                    HStack(spacing: 6) {
                        Text("ÉNERGIE")
                            .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        ForEach(1...5, id: \.self) { val in
                            Button {
                                withAnimation { energyPre = val }
                                energyPreDate = data.todayDate
                                // Fix #15 — transient confirmation checkmark
                                energyConfirmed = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { energyConfirmed = false }
                                }
                            } label: {
                                Image(systemName: val <= energyPre ? "bolt.fill" : "bolt")
                                    .font(.system(size: 15))
                                    .foregroundColor(val <= energyPre ? .yellow : .gray.opacity(0.25))
                            }
                            .buttonStyle(.plain)
                        }
                        // W-D8 — on resume, indicate that energy can be updated
                        if vm.isResuming && energyPreDate == data.todayDate && !energyConfirmed {
                            Text("Mise à jour ?")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.yellow.opacity(0.6))
                        }
                        Spacer()
                        if energyConfirmed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.green)
                                .transition(.scale.combined(with: .opacity))
                        } else if energyPreDate == data.todayDate {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10)).foregroundColor(.green.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.yellow.opacity(0.04))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Resume banner — shown when exercises were already logged (partial prior session)
                if vm.isResuming {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Continuer la séance")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.cyan)
                            // W-D2 — show how many exercises are already logged
                            Text("\(vm.logResults.count) exercice(s) déjà sauvegardé(s). Continue ou recommence depuis le début.")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Recommencer") {
                            withAnimation {
                                vm.logResults.removeAll()
                                vm.isResuming = false
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.cyan.opacity(0.08))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                    .onAppear {
                        // W-D2 — scroll to first unlogged exercise on resume
                        let logged = Set(vm.logResults.keys)
                        if let firstUnlogged = exercises.first(where: { !logged.contains($0.0) })?.0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    scrollProxy?.scrollTo(firstUnlogged, anchor: .top)
                                }
                            }
                        }
                    }
                }

                // Start banner — shown on fresh session before first log
                if !vm.sessionStarted && !vm.isResuming {
                    StartSessionBanner { vm.startSession() }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Ghost mode banner — suppressed while resume banner is active to avoid header clutter
                if showGhost, let ghost = ghostData, !vm.isResuming {
                    GhostBanner(
                        ghost: ghost,
                        currentVolume: currentVolume,
                        beaten: ghostBeaten,
                        onDismiss: {
                            withAnimation { showGhost = false }
                            // W-C3 — persist dismissal so banner doesn't reappear on resume
                            UserDefaults.standard.set(true, forKey: "ghostDismissed_\(data.today)")
                        }
                    )
                    .padding(.horizontal, 16)
                    .onChange(of: currentVolume) {
                        if !ghostBeaten && currentVolume >= ghost.volume {
                            ghostBeaten = true
                        }
                    }
                }

                // Warmup guidance — shown pre-session, dismissable
                if showWarmupBanner && vm.logResults.isEmpty {
                    let guidance = warmupGuidance
                    if guidance != nil {
                        WarmupGuidanceBanner(guidance: guidance!) {
                            withAnimation(.easeOut(duration: 0.2)) { showWarmupBanner = false }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Volume cumulé temps réel
                HStack(spacing: 8) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 12))
                        .foregroundColor(currentVolume > 0 ? .orange : .gray.opacity(0.4))
                    Text("Volume total")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
                    Spacer()
                    Text("\(Int(currentVolume)) \(UnitSettings.shared.label)")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(currentVolume > 0 ? .orange : .gray.opacity(0.4))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.orange.opacity(currentVolume > 0 ? 0.07 : 0.03))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .animation(.spring(response: 0.4), value: currentVolume)

                exerciseNavigator

                // Swap confirmation banner (Fix #11)
                if let swap = lastSwap {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("\(swap.old) → \(swap.new)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Annuler") {
                            Task {
                                await performSwap(original: swap.new, replacement: swap.old)
                                lastSwap = nil
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                        Button { withAnimation { lastSwap = nil } } label: {
                            Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                exerciseSection

                optionalAddonsSection

                // Effort live — visible dès qu'un exercice est loggé
                if !vm.logResults.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 14))
                            .foregroundColor(RPEHelper.color(for: computedSessionRPE))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Effort séance")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                            Text(RPEHelper.option(for: RPEHelper.rirFromRPE(computedSessionRPE)).label)
                                .font(.system(size: 11))
                                .foregroundColor(RPEHelper.color(for: computedSessionRPE))
                        }
                        Spacer()
                        Text("RPE \(String(format: "%.0f", computedSessionRPE))")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(RPEHelper.color(for: computedSessionRPE))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RPEHelper.color(for: computedSessionRPE).opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }

                // Mid-workout intelligence card
                if let advice = midWorkoutAdvice, dismissedAdviceId != advice.id {
                    MidWorkoutAdvisorCard(advice: advice) {
                        withAnimation(.easeOut(duration: 0.25)) { dismissedAdviceId = advice.id }
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: advice.id)
                }

            }
            .padding(.bottom, 4)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("workoutScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "workoutScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            guard let last = lastScrollY else { lastScrollY = offset; return }
            if abs(offset - last) > 4, timer.isVisible {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    timer.isVisible = false
                }
            }
            lastScrollY = offset
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let canFinish = !vm.logResults.isEmpty
            VStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.08))
                if !canFinish {
                    Text("Loggue au moins 1 exercice pour terminer")
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
                Button(action: {
                    let unlogged = exercises.filter { vm.logResults[$0.0] == nil }
                    if unlogged.isEmpty {
                        showFinishConfirm = true
                    } else {
                        showUnloggedWarning = true
                    }
                }) {
                    HStack(spacing: 8) {
                        if vm.isFinishing {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(vm.isFinishing ? "Enregistrement…" : "Terminer la séance")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(canFinish && !vm.isFinishing ? Color.orange : Color(hex: "1a1a2e"))
                    .foregroundColor(canFinish && !vm.isFinishing ? .white : .gray)
                    .cornerRadius(14)
                    .overlay(
                        canFinish && !vm.isFinishing ? nil :
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .disabled(!canFinish || vm.isFinishing)
                .animation(.easeInOut(duration: 0.2), value: canFinish)
                .padding(.horizontal, 16)
                .padding(.top, canFinish ? 10 : 6)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial)
            .ignoresSafeArea(.keyboard)
        }
        .onAppear { scrollProxy = proxy }
        .sheet(isPresented: $showUnloggedWarning) {
            WorkoutSummarySheet(
                exercises: exercises.map(\.0),
                logResults: vm.logResults
            ) {
                confirmedFromWarning = true
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: showUnloggedWarning) { _, isShowing in
            guard !isShowing, confirmedFromWarning else { return }
            confirmedFromWarning = false
            preloadAIAnalysis()
            showFinish = true
        }
        .sheet(isPresented: $showFinish) {
            FinishSessionSheet(
                exercises: exercises.map(\.0),
                logResults: vm.logResults,
                elapsedMin: Date().timeIntervalSince(vm.sessionStart) / 60,
                rpe: $rpe,
                comment: $comment,
                preEnergy: energyPre,
                preloadedAnalysis: preloadedAIAnalysis,
                onSubmit: { _ in
                    let dur = Date().timeIntervalSince(vm.sessionStart) / 60
                    recapSnapshot = SessionRecapSnapshot(
                        sessionName: data.today,
                        durationMin: dur,
                        logResults: vm.logResults,
                        exercises: exercises.map(\.0),
                        rpe: rpe,
                        comment: comment,
                        energyPre: energyPre
                    )
                    Task { await vm.finish(rpe: rpe, comment: comment, durationMin: dur, energyPre: energyPre, sessionName: data.today, bonusSession: isBonusSession) }
                }
            )
            .presentationDetents([.medium, .large])
            .onAppear { rpe = computedSessionRPE }
        }
        .onChange(of: vm.logResults.count) { count in
            guard count == exercises.count else { return }
            preloadAIAnalysis()
            allLoggedPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { allLoggedPulse = false }
        }
        .onChange(of: vm.showSuccess) { success in
            guard success else { return }
            triggerNotificationFeedback(.success)
            vm.showSuccess = false
            // W-D1 — clear resume banner on session completion
            vm.isResuming = false
            // Wait for commitWarning alert to be dismissed before opening recap
            guard vm.commitWarning == nil else { return }
            if !vm.prCelebrations.isEmpty {
                showPRCelebration = true
            } else {
                showRecap = true
            }
        }
        .fullScreenCover(isPresented: $showPRCelebration) {
            PRCelebrationView(prs: vm.prCelebrations) {
                vm.prCelebrations = []
                showPRCelebration = false
                showRecap = true
            }
        }
        .sheet(isPresented: $showRecap, onDismiss: {
            Task {
                let sType = isSecondSession ? "evening" : "morning"
                let todayStr = data.todayDate
                if let suggestions = try? await APIService.shared.fetchProgressionSuggestions(
                    date: todayStr, sessionType: sType, sessionName: data.today
                ), !suggestions.filter({ $0.suggestionType != "maintain" }).isEmpty {
                    progressionSuggestions = suggestions
                    showProgressionSheet = true
                } else {
                    await vm.load()
                }
            }
        }) {
            if let snap = recapSnapshot {
                SessionRecapSheet(snapshot: snap)
            }
        }
        .sheet(isPresented: $showProgressionSheet) {
            ProgressionSuggestionsSheet(
                suggestions: progressionSuggestions,
                sessionName: data.today
            ) {
                showProgressionSheet = false
                Task { await vm.load() }
            }
        }
        .alert("Erreur", isPresented: Binding(
            get: { vm.submitError != nil },
            set: { if !$0 { vm.submitError = nil } }
        )) {
            Button("OK") { vm.submitError = nil }
        } message: {
            Text(vm.submitError ?? "")
        }
        .alert("Séance enregistrée ⚠️", isPresented: Binding(
            get: { vm.commitWarning != nil },
            set: { if !$0 { vm.commitWarning = nil } }
        )) {
            Button("OK") {
                vm.commitWarning = nil
                if !vm.prCelebrations.isEmpty { showPRCelebration = true } else { showRecap = true }
            }
        } message: {
            Text(vm.commitWarning ?? "")
        }
        .alert("Terminer la séance ?", isPresented: $showFinishConfirm) {
            Button("Terminer") { preloadAIAnalysis(); showFinish = true }
            Button("Annuler", role: .cancel) {}
        } message: {
            let logged = vm.logResults.count
            let total = exercises.count
            if logged < total {
                Text("\(logged) / \(total) exercices loggués. Les exercices non loggués ne seront pas enregistrés.")
            } else {
                Text("Tous les exercices sont loggués.")
            }
        }
        // W-D11 — abandon session alert
        .alert("Abandonner la séance ?", isPresented: $showAbandonAlert) {
            Button("Abandonner", role: .destructive) {
                vm.logResults.removeAll()
                vm.isResuming = false
                if let date = vm.seanceData?.todayDate {
                    SessionDraftStore.clear(date: date, sessionType: vm.draftSessionType)
                }
            }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Toutes les données non soumises seront perdues.")
        }
        .sheet(item: $addTarget) { (sn: SeanceName) in
            AddExerciseSheet(seance: sn.id, inventory: inventory, inventorySchemes: [:]) { ex, scheme in
                Task { await addExercise(ex, scheme: scheme) }
            }
        }
        .sheet(isPresented: $showAddLocal) {
            AddExerciseSheet(seance: data.today, inventory: inventory, inventorySchemes: [:]) { ex, scheme in
                // Local-only: adds to this session without modifying the programme
                localProgram[ex] = scheme
            }
        }
        .sheet(item: $editTarget) { target in
            EditSchemeSheet(target: target) { newName, newScheme in
                Task { await editExercise(oldName: target.exercise, newName: newName, scheme: newScheme) }
            }
        }
        .sheet(isPresented: $showSessionPicker) {
            SessionPickerSheet(
                currentSession: data.today,
                availableSessions: Array(data.fullProgram.keys).sorted()
            ) { selected in
                Task {
                    await setSessionOverride(selected)
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddCardio) {
            AddCardioSheet { cardioCount += 1 }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAddHIIT) {
            AddHIITSheet { hiitCount += 1 }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSwapSheet) {
            if let pending = swapPending {
                ExerciseSwapSheet(
                    originalName: pending,
                    originalType: inventoryTypes[pending] ?? "machine",
                    originalMuscles: inventoryMuscles[pending] ?? [],
                    originalPattern: inventoryPatterns[pending] ?? "",
                    inventory: inventory,
                    inventoryTypes: inventoryTypes,
                    inventoryMuscles: inventoryMuscles,
                    inventoryPatterns: inventoryPatterns,
                    onSwap: { replacement in
                        Task { await performSwap(original: pending, replacement: replacement) }
                    },
                    onCreateVariant: {
                        showCreateVariant = true
                    }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showCreateVariant) {
            if let pending = swapPending {
                CreateVariantSheet(
                    originalName: pending,
                    originalMuscles: inventoryMuscles[pending] ?? [],
                    originalPattern: inventoryPatterns[pending] ?? "",
                    originalScheme: localProgram[pending] ?? "3x8-12",
                    originalCategory: "",
                    onCreated: { newName in
                        // Refresh inventory then perform swap
                        Task {
                            await loadInventory()
                            await performSwap(original: pending, replacement: newName)
                        }
                    }
                )
                .presentationDetents([.large])
            }
        }
        .onAppear {
            // W-C3 — restore ghost dismissal state for this session
            if UserDefaults.standard.bool(forKey: "ghostDismissed_\(data.today)") {
                showGhost = false
            }
            Task {
                await loadInventory()
                await loadReadiness()
                await MainActor.run {
                    guard expandedExercises.isEmpty else { return }
                    let logged = Set(vm.logResults.keys)
                    if let first = exercises.first(where: { !logged.contains($0.0) })?.0 {
                        expandedExercises.insert(first)
                        lastOpenedExercise = first
                    }
                }
            }
            computeGhost()
            guard !didLoadPreCoaching else { return }
            didLoadPreCoaching = true
            Task {
                let sType = isSecondSession ? "evening" : "morning"
                if let sug = try? await APIService.shared.fetchProgressionSuggestions(
                    date: data.todayDate, sessionType: sType, sessionName: data.today
                ), !sug.filter({ $0.suggestionType != "maintain" }).isEmpty {
                    progressionSuggestions = sug
                    showProgressionSheet = true
                }
            }
        }
        .onChange(of: data.inventoryTypes) { fresh in
            if !fresh.isEmpty { inventoryTypes = fresh }
        }
        .onChange(of: data.inventoryTracking) { fresh in
            if !fresh.isEmpty { inventoryTracking = fresh }
        }
        .onChange(of: data.inventoryRest) { fresh in
            inventoryRest = fresh
        }
        .onChange(of: data.inventoryHints) { fresh in
            if !fresh.isEmpty { inventoryHints = fresh }
        }
        .onChange(of: data.exerciseSupersets) { fresh in
            let updated = fresh[data.today] ?? [:]
            if !updated.isEmpty { sessionSupersets = updated }
        }
        .toast($toast)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if timer.isVisible {
                FloatingRestTimerCard()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.42, dampingFraction: 0.82), value: timer.isVisible)
            }
        }
        } // end ScrollViewReader
    }

    private func rpeColor(_ v: Double) -> Color { RPEHelper.color(for: v) }

    // Lookup equipment type with fuzzy name matching.
    // Handles e.g. program "Deadlift" matching inventory "Barbell Deadlift".
    private func equipmentType(for name: String) -> String {
        let types = inventoryTypes.isEmpty ? data.inventoryTypes : inventoryTypes
        return types[name] ?? "machine"
    }

    private func trackingType(for name: String) -> String {
        let tracking = inventoryTracking.isEmpty ? data.inventoryTracking : inventoryTracking
        return tracking[name] ?? "reps"
    }

    private func restSeconds(for name: String) -> Int? {
        let rest = inventoryRest.isEmpty ? data.inventoryRest : inventoryRest
        return rest[name]
    }

    // MARK: - Readiness

    private func loadReadiness() async {
        guard let url = URL(string: "\(APIService.shared.baseURL)/api/readiness") else { return }
        guard let (data, _) = try? await URLSession.authed.data(from: url),
              let r = try? JSONDecoder().decode(ReadinessScore.self, from: data) else { return }
        await MainActor.run { readiness = r }
    }

    // MARK: - Programme mutations

    private func loadInventory() async {
        // Seed immediately from already-loaded seanceData
        let fromCache  = data.fullProgram[data.today]?.mapValues { $0.value } ?? [:]
        let orderCache = data.exerciseOrder[data.today] ?? fromCache.keys.sorted()
        await MainActor.run {
            self.localProgram   = fromCache
            self.exerciseOrder  = orderCache
            self.inventoryTypes    = data.inventoryTypes
            self.inventoryTracking = data.inventoryTracking
            self.inventoryRest     = data.inventoryRest
            self.inventoryHints    = data.inventoryHints
            self.sessionSupersets  = data.exerciseSupersets[data.today] ?? [:]
        }

        // Fetch fresh programme + inventory types from network
        guard let url = URL(string: "\(APIService.shared.baseURL)/api/programme_data"),
              let (networkData, _) = try? await URLSession.authed.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: networkData) as? [String: Any]
        else { return }

        let inv         = (json["inventory"] as? [String]) ?? []
        let fromNetwork = (json["full_program"] as? [String: [String: String]])?[data.today]
        let orderNet    = (json["exercise_order"] as? [String: [String]])?[data.today]
        let types    = (json["inventory_types"] as? [String: String]) ?? [:]
        let tracking = (json["inventory_tracking"] as? [String: String]) ?? [:]
        let rest     = (json["inventory_rest"] as? [String: Int]) ?? [:]
        let muscles  = (json["inventory_muscles"] as? [String: [String]]) ?? [:]
        let patterns = (json["inventory_patterns"] as? [String: String]) ?? [:]

        await MainActor.run {
            self.inventory = inv
            if !types.isEmpty    { self.inventoryTypes    = types }
            if !tracking.isEmpty { self.inventoryTracking = tracking }
            self.inventoryRest = rest
            if !muscles.isEmpty  { self.inventoryMuscles  = muscles }
            if !patterns.isEmpty { self.inventoryPatterns = patterns }
            if let fresh = fromNetwork {
                self.localProgram  = fresh
                self.exerciseOrder = orderNet ?? self.exerciseOrder
            }
        }
    }

    @discardableResult
    private func postProgramme(_ body: [String: Any]) async -> Bool {
        guard let url = URL(string: "\(APIService.shared.baseURL)/api/programme") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, resp) = try await URLSession.authed.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func saveOrder(_ order: [String]) async {
        guard order.count >= localProgram.count else { return }
        let ok = await postProgramme(["action": "reorder", "jour": data.today, "ordre": order])
        if !ok {
            await MainActor.run { orderSaveError = true }
        }
    }

    func performSwap(original: String, replacement: String) async {
        let scheme = localProgram[original] ?? "3x8-12"
        let originalType = inventoryTypes[original] ?? "machine"
        let replacementType = inventoryTypes[replacement] ?? "machine"
        let originalWeight = data.weights[original]?.currentWeight ?? 0

        // Fetch weight history for the replacement exercise
        let fetchedData = try? await APIService.shared.fetchExerciseWeightData(name: replacement)

        let conversion = EquipmentConversion(from: originalType, to: replacementType)
        let effectiveWeightData: WeightData
        if let fetched = fetchedData, (fetched.currentWeight ?? 0) > 0 {
            effectiveWeightData = fetched
        } else if let converted = conversion.convert(originalWeight), converted > 0 {
            effectiveWeightData = WeightData(currentWeight: converted,
                                             lastReps: nil, lastLogged: nil, history: nil)
        } else {
            effectiveWeightData = fetchedData ?? WeightData(currentWeight: nil,
                                                            lastReps: nil, lastLogged: nil, history: nil)
        }

        await MainActor.run {
            // Update local program (session only — programme original intact)
            localProgram.removeValue(forKey: original)
            localProgram[replacement] = scheme
            if let idx = exerciseOrder.firstIndex(of: original) {
                exerciseOrder[idx] = replacement
            } else {
                exerciseOrder.append(replacement)
            }
            // Record swap
            swappedExercises[replacement] = original
            swapWeightData[replacement]   = effectiveWeightData
            swapConversions[replacement]  = conversion
            // Clear any in-progress log for the original
            vm.logResults.removeValue(forKey: original)
            // Show toast + undo banner (Fix #11)
            // W-D4 — if a weight conversion was applied, show conversion details in toast
            if let conv = conversion.convert(originalWeight), conv > 0 && (fetchedData?.currentWeight ?? 0) == 0 {
                let u = UnitSettings.shared
                toast = ToastMessage(
                    message: "Charge convertie : \(u.format(originalWeight)) → \(u.format(conv))",
                    style: .info
                )
            } else {
                toast = ToastMessage(message: "Remplacé : \(original) → \(replacement)", style: .info)
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                lastSwap = (old: original, new: replacement)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { lastSwap = nil }
            }
        }
    }

    private func addExercise(_ name: String, scheme: String) async {
        await postProgramme(["action": "add", "jour": data.today, "exercise": name, "scheme": scheme, "block_type": "strength"])
        await MainActor.run { localProgram[name] = scheme }
    }

    private func deleteExercise(_ name: String) async {
        // Local-only: remove from this session view without touching the database
        await MainActor.run { localProgram.removeValue(forKey: name) }
    }

    private func editExercise(oldName: String, newName: String, scheme: String) async {
        if oldName != newName {
            // rename synce tous les jours du programme + inventaire
            await postProgramme(["action": "rename", "jour": data.today, "old_exercise": oldName, "new_exercise": newName])
            await postProgramme(["action": "scheme", "jour": data.today, "exercise": newName, "scheme": scheme])
            await MainActor.run {
                localProgram.removeValue(forKey: oldName)
                localProgram[newName] = scheme
            }
        } else {
            await postProgramme(["action": "scheme", "jour": data.today, "exercise": oldName, "scheme": scheme])
            await MainActor.run { localProgram[oldName] = scheme }
        }
    }

    private func setSessionOverride(_ session: String) async {
        guard let url = URL(string: "\(APIService.shared.baseURL)/api/session_override") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["session": session])
        _ = try? await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "seance_data")
        await vm.load()
    }
}

// MARK: - Mesocycle Chip
struct MesocycleChip: View {
    let info: MesocycleInfo

    private var color: Color {
        switch info.phaseLabel {
        case "S1–S2": return .blue
        case "S3–S4": return .orange
        case "S5–S6": return .red
        case "S7":    return .green
        default:      return .purple
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(info.phaseLabel)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(color)
            Text("·")
                .font(.system(size: 10))
                .foregroundColor(.gray.opacity(0.5))
            Text(info.phase)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
            Text("·")
                .font(.system(size: 10))
                .foregroundColor(.gray.opacity(0.5))
            Text("RPE \(info.rpeTarget)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.25), lineWidth: 1))
        .cornerRadius(6)
    }
}

// MARK: - Readiness Chip

struct ReadinessChip: View {
    let score: Double
    let label: String
    let color: String

    private var swiftColor: Color {
        switch color {
        case "green":  return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red":    return .red
        default:       return .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 10))
                .foregroundColor(swiftColor)
            Text("READINESS")
                .font(.system(size: 9, weight: .bold)).tracking(1)
                .foregroundColor(.gray)
            Text(String(format: "%.1f", score))
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(swiftColor)
            Text("· \(label)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(swiftColor.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(swiftColor.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(swiftColor.opacity(0.2), lineWidth: 1))
        .cornerRadius(8)
    }
}

// MARK: - Start Session Banner

struct StartSessionBanner: View {
    let onStart: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            triggerNotificationFeedback(.success)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { onStart() }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Commencer la séance")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Le chrono démarre maintenant")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.07))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(SpringButtonStyle(scale: 0.97))
    }
}

// MARK: - Ghost Banner
struct GhostBanner: View {
    let ghost: GhostData
    let currentVolume: Double
    let beaten: Bool
    var onDismiss: () -> Void

    private var progress: Double {
        guard ghost.volume > 0 else { return 0 }
        return min(currentVolume / ghost.volume, 1.0)
    }

    private func shortDate(_ s: String) -> String {
        String(s.suffix(5))  // MM-DD
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("👻")
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text("GHOST · \(shortDate(ghost.date))")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    HStack(spacing: 6) {
                        Text(beaten ? "Battu ! 🔥" : "\(UnitSettings.shared.display(ghost.volume), specifier: "%.0f") \(UnitSettings.shared.label)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(beaten ? .orange : .white)
                        if let rpe = ghost.rpe {
                            Text("RPE \(String(format: "%.1f", rpe))")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                        if let sets = ghost.sets {
                            Text("\(sets) sets")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.gray)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                    Capsule()
                        .fill(beaten
                            ? LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * progress, height: 5)
                        .animation(.spring(response: 0.5), value: progress)
                }
            }
            .frame(height: 5)

            HStack {
                Text(currentVolume > 0
                    ? "\(UnitSettings.shared.display(currentVolume), specifier: "%.0f") / \(UnitSettings.shared.display(ghost.volume), specifier: "%.0f") \(UnitSettings.shared.label)"
                    : "Commence à logger pour suivre ta progression")
                    .font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(beaten ? .orange : .purple)
            }
        }
        .padding(12)
        .background(Color(hex: "0e0e1c"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            beaten ? Color.orange.opacity(0.5) : Color.purple.opacity(0.25), lineWidth: 1
        ))
    }
}

// MARK: - Add Cardio Sheet
struct AddCardioSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cardioType  = "Course"
    @State private var durationMin = ""
    @State private var distanceKm  = ""
    @State private var rpe: Double = 7
    @State private var notes       = ""
    @State private var isLogging      = false
    @State private var confirmDiscard = false
    @State private var logError: String? = nil

    private var hasUnsavedData: Bool { !durationMin.isEmpty || !notes.isEmpty || rpe != 7 }

    private let types = ["Course", "Vélo", "Natation", "Elliptique", "Rameur", "Marche", "Autre"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Type
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TYPE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(types, id: \.self) { t in
                                        Button(t) { cardioType = t }
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(cardioType == t ? Color.blue.opacity(0.2) : Color(hex: "191926"))
                                            .foregroundColor(cardioType == t ? .blue : .gray)
                                            .cornerRadius(8)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                }
                            }
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // Durée + Distance
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DURÉE (MIN)").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                TextField("30", text: $durationMin).keyboardType(.decimalPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DISTANCE (\(UnitSettings.shared.distanceUnit))").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $distanceKm).keyboardType(.decimalPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                            }
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // RPE
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(rpe, specifier: "%.1f")").font(.system(size: 18, weight: .black)).foregroundColor(rpeColor(rpe))
                            }
                            Slider(value: $rpe, in: 1...10, step: 0.5).tint(rpeColor(rpe))
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Notes...", text: $notes, axis: .vertical)
                                .font(.system(size: 14)).foregroundColor(.white).tint(.blue)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        Button(action: submit) {
                            HStack {
                                if isLogging { ProgressView().tint(.white) }
                                else { Image(systemName: "checkmark.circle.fill") }
                                Text("Enregistrer Cardio").font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(durationMin.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(isLogging || durationMin.isEmpty)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16).padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Cardio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        if hasUnsavedData { confirmDiscard = true } else { dismiss() }
                    }
                    .foregroundColor(.orange)
                }
            }
            .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Toutes tes notes et configurations seront perdues.")
            }
            .alert("Erreur", isPresented: Binding(get: { logError != nil }, set: { if !$0 { logError = nil } })) {
                Button("OK", role: .cancel) { logError = nil }
            } message: { Text(logError ?? "") }
        }
    }

    private func rpeColor(_ v: Double) -> Color { RPEHelper.color(for: v) }

    private func submit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isLogging = true
        Task {
            do {
                try await APIService.shared.logCardio(
                    type: cardioType,
                    durationMin: Double(durationMin.replacingOccurrences(of: ",", with: ".")),
                    distanceKm: Double(distanceKm.replacingOccurrences(of: ",", with: ".")),
                    avgPace: nil, avgHr: nil, cadence: nil, calories: nil,
                    rpe: rpe, notes: notes
                )
                await MainActor.run { isLogging = false; onDone(); dismiss() }
            } catch {
                await MainActor.run { isLogging = false; logError = error.localizedDescription }
            }
        }
    }
}

// MARK: - HIIT Template
struct HIITTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var sessionType: String
    var rounds: Int
    var workTime: Int
    var restTime: Int
}

// MARK: - Add HIIT Sheet
struct AddHIITSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sessionType = "HIIT"
    @State private var rounds      = "10"
    @State private var workTime    = "20"
    @State private var restTime    = "10"
    @State private var rpe: Double = 8
    @State private var notes       = ""
    @State private var isLogging   = false
    @State private var showSavePrompt = false
    @State private var templateName   = ""
    @State private var logError: String? = nil

    @AppStorage("hiit_templates") private var templatesData: String = "[]"

    private var templates: [HIITTemplate] {
        (try? JSONDecoder().decode([HIITTemplate].self, from: Data(templatesData.utf8))) ?? []
    }

    private var isHIITValid: Bool {
        let r = Int(rounds) ?? 0
        let w = Int(workTime) ?? 0
        let rest = Int(restTime) ?? -1
        return (1...30).contains(r) && (5...300).contains(w) && (0...300).contains(rest)
    }

    private func saveTemplates(_ list: [HIITTemplate]) {
        if let d = try? JSONEncoder().encode(list) {
            templatesData = String(data: d, encoding: .utf8) ?? "[]"
        }
    }

    private func applyTemplate(_ t: HIITTemplate) {
        sessionType = t.sessionType
        rounds      = "\(t.rounds)"
        workTime    = "\(t.workTime)"
        restTime    = "\(t.restTime)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Saved templates
                        if !templates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("TEMPLATES SAUVEGARDÉS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(templates) { t in
                                            HStack(spacing: 4) {
                                                Button(t.name) { applyTemplate(t) }
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.red)
                                                Button {
                                                    saveTemplates(templates.filter { $0.id != t.id })
                                                } label: {
                                                    Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(.gray)
                                                }
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color(hex: "1c1c2e")).cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(14)
                        }

                        // Session type
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TYPE DE SESSION").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("HIIT", text: $sessionType)
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // Rounds / Work / Rest
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("RONDES").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $rounds).keyboardType(.numberPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                                Text("Entre 1 et 30 rounds")
                                    .font(.system(size: 11)).foregroundColor(.gray.opacity(0.6))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TRAVAIL (s)").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $workTime).keyboardType(.numberPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                                Text("Entre 5 et 300s")
                                    .font(.system(size: 11)).foregroundColor(.gray.opacity(0.6))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("REPOS (s)").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $restTime).keyboardType(.numberPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                                Text("Entre 0 et 300s")
                                    .font(.system(size: 11)).foregroundColor(.gray.opacity(0.6))
                            }
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // RPE
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(rpe, specifier: "%.1f")").font(.system(size: 18, weight: .black)).foregroundColor(rpeColor(rpe))
                            }
                            Slider(value: $rpe, in: 1...10, step: 0.5).tint(rpeColor(rpe))
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Notes...", text: $notes, axis: .vertical)
                                .font(.system(size: 14)).foregroundColor(.white).tint(.red)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(14).background(Color.appCard).cornerRadius(14)

                        // Save template button
                        Button {
                            templateName = sessionType.isEmpty ? "HIIT" : sessionType
                            showSavePrompt = true
                        } label: {
                            Label("Sauvegarder comme template", systemImage: "bookmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color(hex: "1c1c2e")).cornerRadius(10)
                        }

                        Button(action: submit) {
                            HStack {
                                if isLogging { ProgressView().tint(.white) }
                                else { Image(systemName: "bolt.fill") }
                                Text("Enregistrer HIIT").font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(isLogging || !isHIITValid ? Color.red.opacity(0.4) : Color.red)
                            .foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(isLogging || !isHIITValid)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16).padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("HIIT").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
            .alert("Nom du template", isPresented: $showSavePrompt) {
                TextField("Ex: Tabata 20/10", text: $templateName)
                Button("Sauvegarder") {
                    guard !templateName.isEmpty else { return }
                    let t = HIITTemplate(
                        name: templateName,
                        sessionType: sessionType.isEmpty ? "HIIT" : sessionType,
                        rounds:   Int(rounds)   ?? 10,
                        workTime: Int(workTime) ?? 20,
                        restTime: Int(restTime) ?? 10
                    )
                    saveTemplates(templates + [t])
                }
                Button("Annuler", role: .cancel) {}
            }
            .alert("Erreur", isPresented: Binding(get: { logError != nil }, set: { if !$0 { logError = nil } })) {
                Button("OK", role: .cancel) { logError = nil }
            } message: { Text(logError ?? "") }
        }
    }

    private func rpeColor(_ v: Double) -> Color { RPEHelper.color(for: v) }

    private func submit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isLogging = true
        Task {
            do {
                try await APIService.shared.logHIIT(
                    sessionType: sessionType.isEmpty ? "HIIT" : sessionType,
                    rounds:     Int(rounds)   ?? 10,
                    workTime:   Int(workTime) ?? 20,
                    restTime:   Int(restTime) ?? 10,
                    rpe:        rpe,
                    notes:      notes,
                    secondSession: true
                )
                await MainActor.run { isLogging = false; onDone(); dismiss() }
            } catch {
                await MainActor.run { isLogging = false; logError = error.localizedDescription }
            }
        }
    }
}

/// MARK: - Card Height Preference Key
struct CardHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Mid-Workout Intelligence

struct MidWorkoutAdvice {
    let id: String
    let icon: String
    let color: Color
    let title: String
    let message: String
}

struct MidWorkoutAdvisorCard: View {
    let advice: MidWorkoutAdvice
    let onDismiss: () -> Void
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: advice.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(advice.color)

                Text(advice.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(advice.color)

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
            .padding(.horizontal, 12).padding(.vertical, 10)

            if expanded {
                Divider().background(advice.color.opacity(0.2)).padding(.horizontal, 12)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundColor(advice.color.opacity(0.7))
                    Text(advice.message)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(advice.color.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(advice.color.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Warmup Guidance Banner
struct WarmupGuidanceBanner: View {
    let guidance: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13))
                .foregroundColor(.yellow.opacity(0.8))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Échauffement recommandé")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.yellow.opacity(0.9))
                Text(guidance)
                    .font(.system(size: 11))
                    .foregroundColor(.gray.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.05))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.15), lineWidth: 1))
    }
}
