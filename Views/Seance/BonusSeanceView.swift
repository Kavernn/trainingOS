import SwiftUI
import Combine

// Presentation only. Results continue to live in SeanceViewModel.logResults.
struct BonusRecoveryConfiguration {
    let scheme: String
    let equipment: String
    let tracking: String
    let unilateral: Bool

    static func resolve(name: String, log: ExerciseLogResult, schemes: [String],
                        equipment: [String], tracking: [String], unilateral: [Bool]) -> Self? {
        let schemes = log.scheme.map { [$0] } ?? schemes
        let tracking = log.trackingType.map { [$0] } ?? tracking
        let unilateral = log.isUnilateral.map { [$0] } ?? unilateral
        // Equipment was already historical. Preserve the legacy conflict policy
        // unless the log explicitly carries the new reconstruction contract.
        let equipment = (log.scheme != nil || log.isUnilateral != nil) ? [log.equipmentType] : equipment
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name == log.name,
              let scheme = schemes.first, !scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(schemes).count == 1,
              let type = equipment.first, Set(equipment).count == 1, type == log.equipmentType,
              let mode = tracking.first, Set(tracking).count == 1,
              log.trackingType == nil || log.trackingType == mode,
              let side = unilateral.first, Set(unilateral).count == 1 else { return nil }
        return Self(scheme: scheme, equipment: type, tracking: mode, unilateral: side)
    }
}

struct BonusVisibleExercise: Identifiable {
    enum Content {
        case editable(BonusRecoveryConfiguration?, ExerciseRecoveryHydration?)
        case recoveredReadOnly
    }
    let id: String
    let content: Content
}

enum BonusRecoveryPresentation {
    static func reconcile(order: [String], snapshotOrder: [String], local: [String: String],
                          logs: [String: ExerciseLogResult],
                          resolve: (String, ExerciseLogResult) -> BonusRecoveryConfiguration?,
                          displayWeight: (Double) -> Double) -> [BonusVisibleExercise] {
        var seen: Set<String> = []
        // Snapshot order is preserved, not described as the original logging order.
        return (order + snapshotOrder).compactMap { name in
            guard seen.insert(name).inserted else { return nil }
            if let log = logs[name] {
                if let config = resolve(name, log),
                   let hydration = ExerciseRecoveryHydration.make(log, equipment: config.equipment,
                       tracking: config.tracking, unilateral: config.unilateral, displayWeight: displayWeight) {
                    return BonusVisibleExercise(id: name, content: .editable(config, hydration))
                }
                return BonusVisibleExercise(id: name, content: .recoveredReadOnly)
            }
            guard local[name] != nil else { return nil }
            return BonusVisibleExercise(id: name, content: .editable(nil, nil))
        }
    }

    static func summary(_ log: ExerciseLogResult) -> [String] {
        // Neutral wording: a reps field can encode duration/distance in old logs.
        var lines = ["Charge enregistrée : \(UnitSettings.shared.format(log.weight))",
                     "Valeur enregistrée : \(log.reps)"]
        if let rpe = log.rpe { lines.append("RPE : \(rpe)") }
        for (index, set) in log.sets.enumerated() {
            var fields: [String] = []
            for key in set.keys.sorted() {
                guard let value = set[key] else { continue }
                switch key {
                case "weight":
                    if let weight = value as? Double { fields.append("Charge : \(UnitSettings.shared.format(weight))") }
                    else { fields.append("Charge enregistrée : \(value)") }
                case "reps": fields.append("Valeur enregistrée : \(value)")
                case "rir": fields.append("RIR : \(value)")
                case "rpe": fields.append("RPE : \(value)")
                case "distance_m": fields.append("Distance : \(value) m")
                case "intensity": fields.append("Intensité : \(value)")
                case "left", "right":
                    if let side = value as? [String: Any], side.count == 1, let time = side["time"] {
                        fields.append("\(key == "left" ? "Gauche" : "Droite") : \(time) s")
                    } else { fields.append("\(key) : \(value)") }
                default: fields.append("\(key) : \(value)")
                }
            }
            lines.append("Série \(index + 1) — " + fields.joined(separator: " · "))
        }
        if !log.painZone.isEmpty { lines.append("Zone de douleur : \(log.painZone)") }
        if !log.notes.isEmpty { lines.append("Note : \(log.notes)") }
        return lines
    }
}

// MARK: - ViewModel
class BonusSeanceViewModel: SeanceViewModel {
    @Published private(set) var isSessionQueued = false

    // Narrow outcome/side-effect seams, matching the Evening pattern.
    func sendBonusSession(exos: [String], rpe: Double, comment: String,
                          durationMin: Double?, energyPre: Int?,
                          exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
        try await APIService.shared.logBonusSessionOutcome(exos: exos, rpe: rpe, comment: comment,
            durationMin: durationMin, energyPre: energyPre, exerciseLogs: exerciseLogs)
    }

    func refreshBonusDashboard() async { await APIService.shared.fetchDashboard() }

    func recordBonusWorkout() async {
        await HealthKitService.shared.saveStrengthWorkout(startDate: sessionStart, endDate: Date())
    }

    override func retryFinish(comment: String) async {
        guard !isSessionQueued else { return }
        await super.retryFinish(comment: comment)
    }

    override init(draftSessionType: String = "bonus") {
        super.init(draftSessionType: draftSessionType)
    }

    /// Server completion is not acknowledgment of the current local generation.
    func loadBonusState(
        fetch: (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.authed.data(for: $0)
        }
    ) async -> SeanceBonusData? {
        guard let url = URL(string: "\(APIConfig.base)/api/seance_bonus_data") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, response) = try? await fetch(request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let bonus = try? JSONDecoder().decode(SeanceBonusData.self, from: data)
        else { return nil }

        if draftSessionType == "bonus",
           bonus.hasBonusSession, bonus.alreadyLogged,
           let date = seanceData?.todayDate, !date.isEmpty,
           bonus.todayDate == date,
           SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "bonus") {
            // Emptying logs also resets sessionStarted and clears this scoped draft
            // through the existing didSet. Do not invoke finish/restart side effects.
            logResults.removeAll()
            isResuming = false
            _ = chrono.stop()
            chrono.elapsedSeconds = 0
            sessionStart = Date()
            SessionDraftStore.clear(date: date, sessionType: "bonus")
        }
        return bonus
    }

    override func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil, bonusSession: Bool = true, closeSession: Bool = true) async {
        guard !isFinishing, !isSessionQueued else { return }
        showSuccess = false
        isFinishing = true
        defer { isFinishing = false }
        prepareFinishRetry(rpe: rpe, comment: comment, durationMin: durationMin, energyPre: energyPre,
                           sessionName: sessionName, bonusSession: bonusSession, closeSession: closeSession)
        let exos = logResults.values.map { "\($0.name) \($0.weight)lbs \($0.reps)" }
        let exerciseLogs: [[String: Any]] = logResults.values.map {
            ["exercise": $0.name, "weight": $0.weight, "reps": $0.reps]
        }
        guard await saveExercisesForFinish(isSecond: false, isBonus: true, collectPRs: false) else { return }

        do {
            let outcome = try await sendBonusSession(exos: exos, rpe: rpe, comment: comment,
                durationMin: durationMin, energyPre: energyPre, exerciseLogs: exerciseLogs)
            if case .queuedOffline = outcome {
                isSessionQueued = true
                return
            }
        } catch {
            submitError = "Erreur lors de l'enregistrement : \(error.localizedDescription)"
            await refreshBonusDashboard()
            return
        }

        await refreshBonusDashboard()
        await recordBonusWorkout()
        showSuccess = true
    }
}

// MARK: - View
struct BonusSeanceView: View {
    var isRestDay: Bool = false
    @StateObject private var vm = BonusSeanceViewModel()
    @State private var localExercises: [String: String] = [:]
    @State private var exerciseOrder: [String] = []
    @State private var inventoryTypes: [String: String] = [:]
    @State private var inventoryTracking: [String: String] = [:]
    @State private var inventoryUnilateral: [String: Bool] = [:]
    @State private var inventorySchemes: [String: String] = [:]
    @State private var inventoryMuscleGroups: [String: String] = [:]
    @State private var inventory: [String] = []
    @State private var showAddExercise = false
    @State private var showFinish = false
    @State private var showUnloggedWarning = false
    @State private var confirmedFromWarning = false
    // W-B3 — quit without saving, with confirmation
    @State private var showQuitConfirm = false
    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Double = 7
    @State private var comment = ""
    private var commentBinding: Binding<String> {
        Binding(get: { comment }, set: { value in
            comment = value
            guard let date = vm.seanceData?.todayDate else { return }
            SessionDraftStore.saveComment(value, date: date, sessionType: vm.draftSessionType)
        })
    }

    private func restoreComment() {
        comment = vm.seanceData.flatMap {
            SessionDraftStore.loadComment(date: $0.todayDate, sessionType: vm.draftSessionType)
        } ?? ""
    }
    @State private var isLoading = true
    @ObservedObject private var timer = RestTimerManager.shared
    @State private var sessionStart = Date()
    @State private var sessionStarted = false
    @State private var expandedExercises: Set<String> = []
    @State private var lastScrollY: CGFloat? = nil
    // Étape 4b-iii — exos poussés depuis matin/soir (SOURCE UNIQUE
    // /api/seance_bonus_data.pushedToBonus). Distincts des exos ajoutés
    // manuellement via AddExerciseSheet → contextMenu retour dispo seulement
    // sur ce sous-ensemble.
    @State private var pushedNames: Set<String> = []
    @State private var exerciseIdsMap: [String: String] = [:]
    @State private var todayDateStr: String = ""
    @State private var pushedSchemes: [String: String] = [:]
    @State private var pushedEquipment: [String: String] = [:]
    @State private var pushedTracking: [String: String] = [:]
    @State private var pushedUnilateral: [String: Bool] = [:]

    private var visibleExercises: [BonusVisibleExercise] {
        let snapshot = vm.seanceData.map {
            SessionDraftStore.load(date: $0.todayDate, sessionType: vm.draftSessionType).map(\.name)
        } ?? []
        return BonusRecoveryPresentation.reconcile(order: exerciseOrder, snapshotOrder: snapshot,
            local: localExercises, logs: vm.logResults, resolve: recoveryConfiguration,
            displayWeight: UnitSettings.shared.display)
    }

    private func recoveryConfiguration(name: String, log: ExerciseLogResult) -> BonusRecoveryConfiguration? {
        // Catalogue default schemes are not evidence of the recovered prescription.
        let planSchemes = vm.seanceData?.fullProgram.values.compactMap { $0[name]?.value } ?? []
        // localExercises may contain the old pushed-plan display fallback. It is
        // not evidence for recovery; only a real manual selection may contribute.
        let manualScheme = pushedNames.contains(name) ? nil : localExercises[name]
        return BonusRecoveryConfiguration.resolve(name: name, log: log,
            schemes: planSchemes + [manualScheme, pushedSchemes[name]].compactMap { $0 },
            equipment: [inventoryTypes[name], vm.seanceData?.inventoryTypes[name], pushedEquipment[name]].compactMap { $0 },
            tracking: [inventoryTracking[name], vm.seanceData?.inventoryTracking[name], pushedTracking[name]].compactMap { $0 },
            unilateral: [inventoryUnilateral[name], vm.seanceData?.inventoryUnilateral[name], pushedUnilateral[name]].compactMap { $0 })
    }

    private var orderedExercises: [String] {
        visibleExercises.map(\.id)
    }

    private func trustedScheme(for name: String, configuration: BonusRecoveryConfiguration?) -> String? {
        if let historical = vm.logResults[name]?.scheme { return historical }
        if pushedNames.contains(name) { return pushedSchemes[name] }
        // AddExerciseSheet also supplies "3x8-12" when the catalogue is absent.
        // Its returned local value alone is therefore not provenance.
        if let catalogue = inventorySchemes[name], catalogue == localExercises[name] { return catalogue }
        if let configuration,
           vm.seanceData?.fullProgram.values.contains(where: { $0[name]?.value == configuration.scheme }) == true {
            return configuration.scheme
        }
        return nil
    }

    @ViewBuilder private func exerciseCard(for name: String, configuration: BonusRecoveryConfiguration? = nil,
                                         hydration: ExerciseRecoveryHydration? = nil) -> some View {
        let idx = orderedExercises.firstIndex(of: name)
        let next = idx.flatMap { $0 + 1 < orderedExercises.count ? orderedExercises[$0 + 1] : nil }
        let isPushed = pushedNames.contains(name)
        ExerciseCard(
            name: name,
            scheme: configuration?.scheme ?? localExercises[name] ?? "3x8-12",
            weightData: vm.seanceData?.weights[name],
            equipmentType: configuration?.equipment ?? inventoryTypes[name] ?? "machine",
            trackingType: configuration?.tracking ?? inventoryTracking[name] ?? "reps",
            isUnilateral: configuration?.unilateral ?? inventoryUnilateral[name] ?? false,
            bodyWeight: APIService.shared.dashboard?.profile.weight ?? 0,
            isSecondSession: false,
            isBonusSession: true,
            logResult: $vm.logResults[name],
            isExpanded: expandedExercises.contains(name),
            onToggle: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    if expandedExercises.contains(name) {
                        expandedExercises.remove(name)
                    } else {
                        expandedExercises.insert(name)
                    }
                }
            },
            nextExerciseName: next,
            sessionDate: vm.seanceData?.todayDate ?? todayDateStr,
            recoveredInitialState: hydration,
            reconstructionMetadata: ExerciseReconstructionMetadata(
                scheme: trustedScheme(for: name, configuration: configuration),
                trackingType: configuration?.tracking ?? inventoryTracking[name],
                isUnilateral: configuration?.unilateral ?? inventoryUnilateral[name])
        )
        .padding(.horizontal, 16)
        // Étape 4b-iii — retour bonus→matin/soir (bidir, décidé à froid).
        // Uniquement sur les exos POUSSÉS (les manuels n'ont pas d'origine).
        // Long-press natif SwiftUI, symétrique au geste 4b-ii sens aller.
        .contextMenu {
            if isPushed {
                Button {
                    performMove(name: name, to: .morning)
                } label: {
                    Label("Renvoyer au matin", systemImage: "arrow.left")
                }
                Button {
                    performMove(name: name, to: .evening)
                } label: {
                    Label("Renvoyer au soir", systemImage: "arrow.left")
                }
            }
        }
    }

    /// Étape 4b-iii — retour bonus→matin/soir. Lookup id AVANT le POST
    /// (fail fast — doctrine). Notif planOverridesDidChange → refetch auto.
    private func performMove(name: String, to slot: SessionKind) {
        let date = vm.seanceData?.todayDate ?? todayDateStr
        // Étape 5 — race guard : entre l'ouverture du contextMenu et le tap,
        // l'exo peut être devenu loggé/draft dans la séance bonus active.
        // Abort silencieux si périmé (ceinture ET bretelles côté iOS).
        let nowLogged = vm.logResults[name] != nil
        let nowDraft  = SessionDraftStore.load(date: date, sessionType: vm.draftSessionType)
            .contains(where: { $0.name == name })
        guard !nowLogged && !nowDraft else { return }

        guard let exoId = exerciseIdsMap[name] else {
            vm.submitError = "Impossible de résoudre '\(name)' — recharge la séance."
            return
        }
        Task {
            do {
                try await APIService.shared.movePlannedExercise(
                    date: date, exerciseId: exoId, to: slot
                )
                NotificationCenter.default.post(name: .planOverridesDidChange, object: nil)
                await loadInventory()  // refetch propre sur la vue bonus
            } catch let APIError.serverError(code, _) where code == 409 {
                await MainActor.run {
                    vm.submitError = "Exo déjà loggé aujourd'hui — non déplaçable."
                }
            } catch {
                await MainActor.run {
                    vm.submitError = "Déplacement échoué : \(error.localizedDescription)"
                }
            }
        }
    }

    @ViewBuilder private var addExerciseButton: some View {
        let label = HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundColor(Color.forge)
            Text("Ajouter un exercice")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.forge)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.forge.opacity(0.08))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.forge.opacity(0.25), lineWidth: 1))
        Button { showAddExercise = true } label: { label }
            .buttonStyle(SpringButtonStyle())
            .padding(.horizontal, 16)
    }

    private var computedRPE: Double {
        let vals = vm.logResults.values.compactMap(\.rpe)
        guard !vals.isEmpty else { return 7.0 }
        return (vals.reduce(0, +) / Double(vals.count) * 2).rounded() / 2
    }

    // Extraction pour désengorger le type-checker sur le VStack englobant du body.
    // Reuse the finish state for initial saves and retries.
    @ViewBuilder
    private var finishSessionButton: some View {
        if vm.isSessionQueued {
            VStack(spacing: 8) {
                Text("Synchronisation en attente. Les données sont conservées sur cet appareil.")
                    .font(.appCaption)
                    .foregroundColor(Color.appTextPrimary)
                Button("Fermer et reprendre plus tard") { dismiss() }
                    .frame(minHeight: 44)
                    .foregroundColor(Color.forge)
            }
            .padding(.horizontal, 16)
        } else if !vm.logResults.isEmpty {
            Button {
                let unlogged = orderedExercises.filter { vm.logResults[$0] == nil }
                if unlogged.isEmpty {
                    showFinish = true
                } else {
                    showUnloggedWarning = true
                }
            } label: {
                HStack {
                    if vm.isFinishing { ProgressView().tint(Color.onAccent) }
                    else { Image(systemName: "checkmark.circle.fill") }
                    Text(vm.isFinishing ? "Enregistrement…" : "Terminer la séance")
                        .font(.appBody.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.forge)
                .foregroundColor(Color.onAccent)
                .cornerRadius(14)
            }
            .padding(.horizontal, 16)
            .disabled(vm.isFinishing)
        }
    }

    private var unloggedWarningSheet: some View {
        WorkoutSummarySheet(
            exercises: orderedExercises,
            logResults: vm.logResults
        ) {
            confirmedFromWarning = true
        }
        .presentationDetents([.medium, .large])
    }

    private var addExerciseSheet: some View {
        AddExerciseSheet(
            seance: "Bonus",
            inventory: inventory,
            inventorySchemes: inventorySchemes,
            inventoryMuscleGroups: inventoryMuscleGroups
        ) { list in
            for (name, scheme) in list {
                if localExercises[name] == nil {
                    exerciseOrder.append(name)
                }
                localExercises[name] = scheme
            }
        }
    }

    private var finishSheet: some View {
        FinishSessionSheet(
            exercises: orderedExercises,
            logResults: vm.logResults,
            elapsedMin: Date().timeIntervalSince(sessionStart) / 60,
            rpe: $rpe,
            comment: commentBinding,
            onSubmit: { energy in
                let dur = Date().timeIntervalSince(sessionStart) / 60
                Task {
                    await vm.finish(
                        rpe: rpe,
                        comment: comment,
                        durationMin: dur,
                        energyPre: energy
                    )
                }
            }
        )
        .presentationDetents([.medium, .large])
        .onAppear {
            restoreComment()
            rpe = computedRPE
        }
    }

    private var quitButton: some View {
        Button {
            showQuitConfirm = true
        } label: {
            Text("Quitter sans sauvegarder")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.statusRed.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.statusRed.opacity(0.07))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.statusRed.opacity(0.2), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            if isLoading {
                ProgressView().tint(Color.forge)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Header
                        HStack {
                            Text(isRestDay ? "SÉANCE LIBRE" : "SÉANCE 2")
                                .font(.appLabel.weight(.black))
                                .tracking(3)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Start banner
                        if !sessionStarted {
                            StartSessionBanner {
                                sessionStart = Date()
                                sessionStarted = true
                            }
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Exercise cards
                        if visibleExercises.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "dumbbell")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray.opacity(0.4))
                                Text("Ajoute des exercices pour commencer")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(visibleExercises) { item in
                                    switch item.content {
                                    case .editable(let configuration, let hydration):
                                        exerciseCard(for: item.id, configuration: configuration, hydration: hydration)
                                    case .recoveredReadOnly:
                                        if let log = vm.logResults[item.id] {
                                            recoveredCard(log)
                                        }
                                    }
                                }
                            }
                        }

                        // Add exercise button
                        addExerciseButton

                        // Terminer — visible dès qu'au moins 1 exercice est loggé
                        finishSessionButton

                        // W-B3 — always-visible quit button (no data loss if tapped)
                        quitButton
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("bonusScroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "bonusScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { offset in
                    guard let last = lastScrollY else { lastScrollY = offset; return }
                    if abs(offset - last) > 4, timer.isVisible {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            timer.isVisible = false
                        }
                    }
                    lastScrollY = offset
                }
                .padding(.bottom, timer.isVisible ? 90 : 0)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle(isRestDay ? "Séance libre" : "Séance 2")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if timer.isVisible {
                FloatingRestTimerCard()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.42, dampingFraction: 0.82), value: timer.isVisible)
            }
        }
        .task { await loadInventory() }
        // Étape 4b-iii — un move depuis matin/soir (ou vice-versa) doit rafraîchir
        // la liste des pushed. Notif émise par WorkoutActiveView.performMove.
        .onReceive(NotificationCenter.default.publisher(for: .planOverridesDidChange)) { _ in
            Task { await loadBonusPlan() }
        }
        .sheet(isPresented: $showUnloggedWarning) { unloggedWarningSheet }
        .onChange(of: showUnloggedWarning) { _, isShowing in
            guard !isShowing, confirmedFromWarning else { return }
            confirmedFromWarning = false
            showFinish = true
        }
        .sheet(isPresented: $showAddExercise) { addExerciseSheet }
        .sheet(isPresented: $showFinish) { finishSheet }
        .alert("Fin de séance", isPresented: $vm.showSuccess) {
            Button("OK") { Task { await loadInventory() } }
        } message: {
            Text("Le serveur a accepté la requête. Les données locales sont conservées ; leur synchronisation complète n’est pas confirmée.")
        }
        .alert(vm.failedExerciseNames.isEmpty ? "Erreur" : "Certains exercices n’ont pas été sauvegardés", isPresented: Binding(
            get: { vm.submitError != nil },
            set: { if !$0 { vm.submitError = nil } }
        )) {
            if vm.canRetryFinish && !vm.isSessionQueued {
                Button("Réessayer") { Task { await vm.retryFinish(comment: comment) } }
                    .disabled(vm.isFinishing)
            }
            Button("Annuler", role: .cancel) { vm.submitError = nil }
        } message: {
            Text(vm.submitError ?? "")
        }
        // W-B3 — quit confirmation
        .confirmationDialog("Quitter ?", isPresented: $showQuitConfirm, titleVisibility: .visible) {
            Button("Quitter", role: .destructive) {
                vm.logResults.removeAll()
                if let date = vm.seanceData?.todayDate {
                    SessionDraftStore.clear(date: date, sessionType: vm.draftSessionType)
                }
                dismiss()
            }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Les données non soumises seront perdues.")
        }
    }

    private func loadInventory() async {
        await vm.load()
        restoreComment()

        // Étape 4b-iii — charger le plan bonus (exos poussés depuis matin/soir).
        // Séquentiel (pas async let — cf. feedback iOS 26 async let crash).
        await loadBonusPlan()

        guard let url = URL(string: "\(APIConfig.base)/api/programme_data"),
              let (data, _) = try? await URLSession.authed.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { isLoading = false; return }

        let inv      = (json["inventory"] as? [String]) ?? []
        let types    = (json["inventory_types"] as? [String: String]) ?? [:]
        let tracking = (json["inventory_tracking"] as? [String: String]) ?? [:]
        let unilateral = (json["inventory_unilateral"] as? [String: Bool]) ?? [:]
        let schemes  = (json["inventory_schemes"] as? [String: String]) ?? [:]
        let muscleGroups = (json["inventory_muscle_groups"] as? [String: String]) ?? [:]
        await MainActor.run {
            inventory         = inv
            inventoryTypes    = types
            inventoryTracking = tracking
            inventoryUnilateral = unilateral
            inventorySchemes  = schemes
            inventoryMuscleGroups = muscleGroups
            isLoading         = false
        }
    }

    private func recoveredCard(_ log: ExerciseLogResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(log.name).font(.appHeadline).foregroundColor(Color.appTextPrimary)
            Text("Données récupérées").font(.appLabel).foregroundColor(Color.forge)
            Text("Configuration indisponible — consultation uniquement")
                .font(.appCaption).foregroundColor(Color.appTextSecondary)
            ForEach(Array(BonusRecoveryPresentation.summary(log).enumerated()), id: \.offset) { _, line in
                Text(line).font(.appCaption).foregroundColor(Color.appTextPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    /// Étape 4b-iii — GET /api/seance_bonus_data → merge pushedToBonus dans
    /// localExercises/exerciseOrder. Les ajouts MANUELS (via AddExerciseSheet)
    /// sont préservés. Distingués via pushedNames Set (contextMenu retour dispo
    /// seulement sur les pushed).
    private func loadBonusPlan() async {
        let bonusState = await vm.loadBonusState()
        restoreComment()
        guard let bonus = bonusState else { return }

        let newPushed = bonus.pushedToBonus
        // Scheme source : fullProgram["Bonus"] du payload (contient les exos poussés).
        let bonusPlan = bonus.fullProgram["Bonus"] ?? [:]

        await MainActor.run {
            let oldPushed = pushedNames
            pushedSchemes = bonusPlan.mapValues(\.value)
            pushedEquipment = bonus.inventoryTypes
            pushedTracking = bonus.inventoryTracking
            pushedUnilateral = bonus.inventoryUnilateral
            // Retire les anciens pushed qui ne le sont plus (mais garde les manuels).
            for name in oldPushed.subtracting(newPushed) {
                localExercises.removeValue(forKey: name)
                exerciseOrder.removeAll { $0 == name }
            }
            // Ajoute les nouveaux pushed (scheme depuis bonus payload, fallback 3x8-12).
            for name in newPushed.subtracting(oldPushed) {
                let scheme = bonusPlan[name]?.value ?? "3x8-12"
                localExercises[name] = scheme
                if !exerciseOrder.contains(name) {
                    exerciseOrder.insert(name, at: 0)  // pushed en tête, manuels après
                }
            }
            pushedNames = newPushed
            exerciseIdsMap = bonus.exerciseIds
            if !bonus.todayDate.isEmpty { todayDateStr = bonus.todayDate }
        }
    }
}
