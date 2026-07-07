import SwiftUI

// MARK: - ViewModel

class SeanceSoirViewModel: SeanceViewModel {
    override init(draftSessionType: String = "evening") {
        super.init(draftSessionType: draftSessionType)
    }

    override func load() async {
        // Séance 2 consomme le MÊME endpoint que la matin (/api/seance_data).
        // today_str hérité = nom du programme matin ("Upper A", etc.).
        // L'isolation matin/soir est gérée par draftSessionType="evening"
        // (brouillon UserDefaults séparé) et logExercise(isSecond: true) au finish().
        if seanceData == nil,
           let cached = cacheService.load(for: "seance_data"),
           let decoded = try? APIService.decoder.decode(SeanceData.self, from: cached) {
            seanceData = decoded
            restoreLogResults(from: decoded)
            SeanceSplitStore.reconcile(date: decoded.todayDate, loggedNames: decoded.loggedTodayNames)
        }

        if seanceData == nil { isLoading = true }
        error = nil
        do {
            let fresh = try await APIService.shared.fetchSeanceData()
            seanceData = fresh
            restoreLogResults(from: fresh)
            SeanceSplitStore.reconcile(date: fresh.todayDate, loggedNames: fresh.loggedTodayNames)
        } catch {
            if seanceData == nil { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    override func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil, bonusSession: Bool = false) async {
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
                // Décrémente le Set d'assignments si l'exo y était (résout compteur dash + séance complétée).
                if let dateStr = seanceData?.todayDate,
                   SeanceSplitStore.load(date: dateStr).contains(result.name) {
                    SeanceSplitStore.remove(date: dateStr, exercise: result.name)
                }
            } catch {
                failedExercises.append(result.name)
            }
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

struct SeanceSoirView: View {
    @StateObject private var vm = SeanceSoirViewModel()
    @State private var showPRCelebration = false

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
            .navigationTitle("Séance du Soir")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await vm.load() }
        .onChange(of: vm.showSuccess) { success in
            guard success, !vm.prCelebrations.isEmpty else { return }
            showPRCelebration = true
        }
        .fullScreenCover(isPresented: $showPRCelebration) {
            PRCelebrationView(prs: vm.prCelebrations) {
                vm.prCelebrations = []
                showPRCelebration = false
                Task { await vm.load() }
            }
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
            WorkoutSeanceView(data: data, vm: vm, isSecondSession: true)
        }
    }
}
