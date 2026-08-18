import SwiftUI

// MARK: - ViewModel

class SeanceSoirViewModel: SeanceViewModel {
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
            restoreLogResults(from: decoded)
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
            restoreLogResults(from: fresh)
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

        let exos = logResults.values.map { "\($0.name) \($0.weight)lbs \($0.reps)" }
        let exerciseLogs: [[String: Any]] = logResults.values.map {
            ["exercise": $0.name, "weight": $0.weight, "reps": $0.reps]
        }
        var failedExercises: [String] = []

        for result in logResults.values {
            do {
                let response = try await APIService.shared.logExercise(
                    exercise: result.name, weight: result.weight, reps: result.reps, rpe: result.rpe,
                    sets: result.sets, force: true,
                    isSecond: true, isBonus: false,
                    equipmentType: result.equipmentType, painZone: result.painZone, notes: result.notes)
                if response.isPR == true {
                    prCelebrations.append((name: result.name, oneRM: response.oneRM ?? 0))
                }
                // Étape 3b — remove-on-log moot : le backend override survit au log
                // (garde-fou exercise_has_log_on empêche déjà toute mutation ultérieure),
                // pas besoin de cleanup côté client.
            } catch {
                failedExercises.append(result.name)
            }
        }

        // Reprendre plus tard : persist les exos (loop ci-dessus déjà fait) et sort.
        // On SKIP logSession → workout_sessions.completed reste false → showEveningBlock
        // (SeanceView.swift:132) reste vrai → Vince peut rouvrir. On SKIP aussi le
        // clear du draft (safety net local si logExercise a échoué offline). Restitution
        // à la reprise = hide-done via loggedTodayNames (WorkoutActiveView L199-202).
        if !closeSession {
            await APIService.shared.fetchDashboard()
            return
        }

        do {
            try await APIService.shared.logSession(exos: exos, rpe: rpe, comment: comment,
                                                   durationMin: durationMin, energyPre: energyPre,
                                                   secondSession: true, sessionName: sessionName,
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
        if let date = seanceData?.todayDate {
            SessionDraftStore.clear(date: date, sessionType: draftSessionType)
        }
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
    @StateObject private var vm: SeanceSoirViewModel
    private let hasOverride: Bool

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
        }
        .task { await vm.load() }
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
            WorkoutSeanceView(data: data, vm: vm, isSecondSession: true, isOverride: hasOverride)
        }
    }
}
