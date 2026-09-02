import SwiftUI

// MARK: - ViewModel
class BonusSeanceViewModel: SeanceViewModel {
    override init(draftSessionType: String = "bonus") {
        super.init(draftSessionType: draftSessionType)
    }

    override func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil, bonusSession: Bool = true, closeSession: Bool = true) async {
        let exos = logResults.values.map { "\($0.name) \($0.weight)lbs \($0.reps)" }
        let exerciseLogs: [[String: Any]] = logResults.values.map {
            ["exercise": $0.name, "weight": $0.weight, "reps": $0.reps]
        }
        var failedExercises: [String] = []

        for result in logResults.values {
            do {
                _ = try await APIService.shared.logExercise(
                    exercise: result.name, weight: result.weight, reps: result.reps, rpe: result.rpe,
                    sets: result.sets, force: true,
                    isSecond: false, isBonus: true,
                    equipmentType: result.equipmentType, painZone: result.painZone, notes: result.notes)
            } catch {
                failedExercises.append(result.name)
            }
        }

        do {
            try await APIService.shared.logSession(exos: exos, rpe: rpe, comment: comment,
                                                   durationMin: durationMin, energyPre: energyPre,
                                                   bonusSession: true,
                                                   exerciseLogs: exerciseLogs)
        } catch {
            submitError = "Erreur lors de l'enregistrement : \(error.localizedDescription)"
            await APIService.shared.fetchDashboard()
            return
        }

        await APIService.shared.fetchDashboard()
        if !failedExercises.isEmpty {
            commitWarning = "\(logResults.count - failedExercises.count) / \(logResults.count) exercices enregistrés. Non sauvegardés : \(failedExercises.joined(separator: ", "))"
        }
        await HealthKitService.shared.saveStrengthWorkout(startDate: sessionStart, endDate: Date())
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

    private var orderedExercises: [String] {
        exerciseOrder.filter { localExercises[$0] != nil }
    }

    @ViewBuilder private func exerciseCard(for name: String) -> some View {
        let idx = orderedExercises.firstIndex(of: name)
        let next = idx.flatMap { $0 + 1 < orderedExercises.count ? orderedExercises[$0 + 1] : nil }
        let isPushed = pushedNames.contains(name)
        ExerciseCard(
            name: name,
            scheme: localExercises[name] ?? "3x8-12",
            weightData: vm.seanceData?.weights[name],
            equipmentType: inventoryTypes[name] ?? "machine",
            trackingType: inventoryTracking[name] ?? "reps",
            isUnilateral: inventoryUnilateral[name] ?? false,
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
            sessionDate: vm.seanceData?.todayDate ?? todayDateStr
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
    // Comportement et rendu strictement identiques à la version inline précédente.
    @ViewBuilder
    private var finishSessionButton: some View {
        if !vm.logResults.isEmpty {
            Button {
                let unlogged = orderedExercises.filter { vm.logResults[$0] == nil }
                if unlogged.isEmpty {
                    showFinish = true
                } else {
                    showUnloggedWarning = true
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Terminer la séance")
                        .font(.appBody.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.forge)
                .foregroundColor(Color.onAccent)
                .cornerRadius(14)
            }
            .padding(.horizontal, 16)
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
            exercises: exerciseOrder,
            logResults: vm.logResults,
            elapsedMin: Date().timeIntervalSince(sessionStart) / 60,
            rpe: $rpe,
            comment: $comment,
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
        .onAppear { rpe = computedRPE }
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
                        if localExercises.isEmpty {
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
                                ForEach(orderedExercises, id: \.self) { name in
                                    exerciseCard(for: name)
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
        .alert("Séance enregistrée ✅", isPresented: $vm.showSuccess) {
            Button("OK") { Task { await vm.load() } }
        }
        .alert("Erreur", isPresented: Binding(
            get: { vm.submitError != nil },
            set: { if !$0 { vm.submitError = nil } }
        )) {
            Button("OK") { vm.submitError = nil }
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

    /// Étape 4b-iii — GET /api/seance_bonus_data → merge pushedToBonus dans
    /// localExercises/exerciseOrder. Les ajouts MANUELS (via AddExerciseSheet)
    /// sont préservés. Distingués via pushedNames Set (contextMenu retour dispo
    /// seulement sur les pushed).
    private func loadBonusPlan() async {
        guard let url = URL(string: "\(APIConfig.base)/api/seance_bonus_data"),
              let (data, _) = try? await URLSession.authed.data(from: url),
              let bonus = try? JSONDecoder().decode(SeanceBonusData.self, from: data)
        else { return }

        let newPushed = bonus.pushedToBonus
        // Scheme source : fullProgram["Bonus"] du payload (contient les exos poussés).
        let bonusPlan = bonus.fullProgram["Bonus"] ?? [:]

        await MainActor.run {
            let oldPushed = pushedNames
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
