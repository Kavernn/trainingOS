import SwiftUI
import Combine

// MARK: - ViewModel

class SeanceSoirViewModel: SeanceViewModel {
    @Published var saveStatusMessage: String?

    // Narrow test seams: no change to the shared exercise gate or offline queue.
    func sendEveningSession(exos: [String], rpe: Double, comment: String,
                            durationMin: Double?, energyPre: Int?, sessionName: String?,
                            exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
        try await APIService.shared.logEveningSessionOutcome(exos: exos, rpe: rpe, comment: comment,
            durationMin: durationMin, energyPre: energyPre, sessionName: sessionName, exerciseLogs: exerciseLogs)
    }

    func refreshEveningDashboard() async { await APIService.shared.fetchDashboard() }

    func observeEveningCompletion(date: String) async -> Bool {
        struct Status: Decodable {
            let today_date: String
            let second_session_completed: Bool
        }
        guard !date.isEmpty, var components = URLComponents(string: "\(APIConfig.base)/api/dashboard") else { return false }
        components.queryItems = [URLQueryItem(name: "date", value: date)]
        guard let url = components.url else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, response) = try? await URLSession.authed.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let status = try? JSONDecoder().decode(Status.self, from: data) else { return false }
        return status.today_date == date && status.second_session_completed
    }

    func recordEveningWorkout() async {
        await HealthKitService.shared.saveStrengthWorkout(startDate: sessionStart, endDate: Date())
    }
    /// Nom soir override manuel — passé par les call sites qui affichent
    /// eveningSessionName (Dashboard, hero SOIR ProgrammeView). nil = héritage
    /// matin (comportement historique : charge la séance matin, filtrée par
    /// SeanceSplitStore). Non-nil = vrai override, charge cette séance-là et
    /// bypass le filtre split côté WorkoutSeanceView.
    let overrideSessionName: String?

    init(sessionName: String? = nil) {
        self.overrideSessionName = sessionName
        super.init(draftSessionType: "evening")
    }

    override func load() async {
        // Cache "seance_data" (matin) ne s'applique QUE si override matin (chemin
        // fetchSeanceData conservé — backend soir n'accepte pas encore session_name,
        // report carnet voie A v2). Sans override : /api/seance_soir_data sert le vrai
        // plan evening (slot='evening' seedé), pas de cache soir dédié pour l'instant.
        if seanceData == nil, overrideSessionName != nil,
           let cached = cacheService.load(for: "seance_data"),
           let decoded = try? APIService.decoder.decode(SeanceData.self, from: cached) {
            seanceData = decoded
            restoreLogResults(from: decoded, serverSessionType: "morning", serverCompleted: decoded.alreadyLogged)
        }

        if seanceData == nil { isLoading = true }
        error = nil
        do {
            let fresh: SeanceData
            if let name = overrideSessionName {
                fresh = try await APIService.shared.fetchSeanceData(sessionName: name)
            } else {
                let soir = try await APIService.shared.fetchSeanceSoirData()
                guard let bridged = soir.asSeanceData() else {
                    isLoading = false
                    return  // seanceData reste nil → vue affiche "Pas de séance du soir"
                }
                fresh = bridged
            }
            seanceData = fresh
            // PM alreadyLogged means "session exists", including partial sessions.
            // Dashboard provides actual completion, scoped to the same date and slot.
            // With no matching snapshot, preserve the draft rather than infer completion.
            let dashboard = APIService.shared.dashboard
            let completed: Bool? = dashboard?.todayDate == fresh.todayDate
                ? dashboard?.secondSessionCompleted : nil
            restoreLogResults(from: fresh, serverSessionType: "evening", serverCompleted: completed)
        } catch {
            if seanceData == nil { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    override func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil, bonusSession: Bool = false, closeSession: Bool = true) async {
        precondition(!bonusSession, "SeanceSoirViewModel ne supporte pas bonus — path bonus via SeanceViewModel(draftSessionType: \"bonus\") + ExtraSessionSheet.")
        // Guard double-submit — symétrie avec SeanceViewModel.finish (L778-788, parent
        // matin). Sans ça, un tap répété sur "Terminer" pouvait lancer 2 tâches
        // parallèles qui postent chacune la même séance 2 (bouton .disabled sur
        // vm.isFinishing devenait inefficace car le flag restait toujours false).
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }
        prepareFinishRetry(rpe: rpe, comment: comment, durationMin: durationMin, energyPre: energyPre,
                           sessionName: sessionName, bonusSession: bonusSession, closeSession: closeSession)

        let exos = logResults.values.map { "\($0.name) \($0.weight)lbs \($0.reps)" }
        let exerciseLogs: [[String: Any]] = logResults.values.map {
            ["exercise": $0.name, "weight": $0.weight, "reps": $0.reps]
        }
        guard await saveExercisesForFinish(isSecond: true, isBonus: false) else { return }

        // Reprendre plus tard : persist les exos (loop ci-dessus déjà fait) et sort.
        // On SKIP logSession → workout_sessions.completed reste false → showEveningBlock
        // (SeanceView.swift:132) reste vrai → Vince peut rouvrir. On SKIP aussi le
        // clear du draft (safety net local si logExercise a échoué offline). Restitution
        // à la reprise = hide-done via loggedTodayNames (WorkoutActiveView L199-202).
        if !closeSession {
            await refreshEveningDashboard()
            acceptPartialSave()
            return
        }

        saveStatusMessage = nil
        do {
            let outcome = try await sendEveningSession(exos: exos, rpe: rpe, comment: comment,
                                                   durationMin: durationMin, energyPre: energyPre,
                                                   sessionName: sessionName,
                                                   exerciseLogs: exerciseLogs)
            if case .queuedOffline = outcome {
                saveStatusMessage = "Synchronisation en attente. Données conservées sur cet appareil. Tu peux fermer la séance et la reprendre plus tard."
                return
            }
        } catch {
            submitError = "Erreur lors de l'enregistrement : \(error.localizedDescription)"
            await refreshEveningDashboard()
            return
        }

        guard let date = seanceData?.todayDate, await observeEveningCompletion(date: date) else {
            saveStatusMessage = "Réponse serveur reçue. La clôture n’est pas confirmée. Les données locales sont conservées."
            return
        }
        await refreshEveningDashboard()
        await recordEveningWorkout()
        // completed is server status only. Never retire unacknowledged local content.
        if SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: draftSessionType) {
            SessionDraftStore.clear(date: date, sessionType: draftSessionType)
        }
        commitWarning = "Séance complétée côté serveur. Les données locales sont conservées ; leur synchronisation complète n’est pas confirmée."
        commitWarningStyle = .success
        showSuccess = true
    }
}

// MARK: - View

/// ⚠️ CONTRAINTE DE PRÉSENTATION : cette vue doit être présentée en `.sheet`
/// ou `.fullScreenCover`, JAMAIS en `NavigationLink` push. Ses `.alert` et
/// `.sheet` empilés (via WorkoutSeanceView) ne firent pas en contexte push
/// (bug prouvé 2026-07-13, volet G : bouton "Terminer" muet — le tap set le
/// @State mais l'alert de confirmation ne s'affiche pas). Call sites en règle :
/// WorkoutActiveView.swift:1315 (sheet), SeanceView.swift:502 (sheet),
/// DashboardTodayCards.swift (sheet), DashboardView.swift (sheet).
struct SeanceSoirView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: SeanceSoirViewModel
    private let hasOverride: Bool
    @State private var showCloseConfirm = false

    init(sessionName: String? = nil) {
        self.hasOverride = sessionName != nil
        _vm = StateObject(wrappedValue: SeanceSoirViewModel(sessionName: sessionName))
    }

    // Titre dynamique : override → nom seul ("Yoga") ; héritage matin →
    // "{nom} — suite" pour signaler la continuation.
    private var seanceTitle: String {
        guard let name = vm.seanceData?.today, !name.isEmpty, name != "Repos" else {
            return "Séance du Soir"
        }
        return hasOverride ? name : "\(name) — suite"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView().tint(.statusBlue)
                } else if let data = vm.seanceData {
                    seanceContent(data: data)
                } else if let err = vm.error {
                    ErrorView(message: err) { Task { await vm.load() } }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 48)).foregroundColor(.statusBlue)
                        Text("Pas de séance du soir ce soir")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle(seanceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // fullScreenCover n'a pas de swipe-dismiss : bouton = seule sortie non-terminale.
                        // Les résultats loggués sont déjà conservés dans SessionDraftStore →
                        // dismiss() suffit pour permettre une reprise ultérieure.
                        if vm.logResults.isEmpty {
                            dismiss()
                        } else {
                            showCloseConfirm = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Fermer la séance")
                }
            }
            .confirmationDialog(
                "Quitter la séance ?",
                isPresented: $showCloseConfirm,
                titleVisibility: .visible
            ) {
                Button("Quitter", role: .destructive) { dismiss() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les exercices déjà loggués restent enregistrés. Tu pourras reprendre plus tard.")
            }
        }
        .task { await vm.load() }
        .alert("Sauvegarde de la séance", isPresented: Binding(
            get: { vm.saveStatusMessage != nil },
            set: { if !$0 { vm.saveStatusMessage = nil } }
        )) {
            Button("OK") { vm.saveStatusMessage = nil }
        } message: {
            Text(vm.saveStatusMessage ?? "")
        }
    }

    @ViewBuilder
    private func seanceContent(data: SeanceData) -> some View {
        // Séance 2 : on n'affiche JAMAIS AlreadyLoggedSeanceView — ce récap appartient
        // à séance 1. data.alreadyLogged reflète le statut matin (backend ne distingue
        // pas séance 2). Les exos déjà loggués sont filtrés via loggedTodayNames.
        if data.today == "Yoga / Tai Chi" || data.today == "Recovery" {
            SpecialSeanceView(sessionType: data.today, vm: vm)
        } else {
            // isOverride bypass le filtre split (assignments) côté WorkoutSeanceView :
            // un override manuel (Yoga, séance dédiée) montre TOUS ses exos, pas
            // seulement ceux envoyés depuis le matin.
            WorkoutSeanceView(data: data, vm: vm, isSecondSession: true, isOverride: hasOverride, onDidFinish: { dismiss() })
        }
    }
}
