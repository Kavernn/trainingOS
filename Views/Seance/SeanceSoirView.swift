import SwiftUI

// MARK: - ViewModel

class SeanceSoirViewModel: SeanceViewModel {
    override init(draftSessionType: String = "evening") {
        super.init(draftSessionType: draftSessionType)
    }

    override func load() async {
        // Show cached data immediately
        if seanceData == nil,
           let cached = cacheService.load(for: "seance_soir_data"),
           let decoded = try? JSONDecoder().decode(SeanceSoirData.self, from: cached),
           let converted = decoded.asSeanceData() {
            seanceData = converted
            restoreLogResults(from: converted)
        }

        if seanceData == nil { isLoading = true }
        error = nil
        do {
            let fresh = try await APIService.shared.fetchSeanceSoirData()
            if let converted = fresh.asSeanceData() {
                seanceData = converted
                restoreLogResults(from: converted)
            } else {
                seanceData = nil
            }
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
                _ = try await APIService.shared.logExercise(
                    exercise: result.name, weight: result.weight, reps: result.reps, rpe: result.rpe,
                    sets: result.sets, force: true,
                    isSecond: true, isBonus: false,
                    equipmentType: result.equipmentType, painZone: result.painZone)
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
        showSuccess = true
    }
}

// MARK: - View

struct SeanceSoirView: View {
    @StateObject private var vm = SeanceSoirViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()

                if vm.isLoading {
                    ProgressView().tint(.indigo)
                } else if let data = vm.seanceData {
                    seanceContent(data: data)
                } else if let err = vm.error {
                    ErrorView(message: err) { Task { await vm.load() } }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 48)).foregroundColor(.indigo)
                        Text("Pas de séance du soir ce soir")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Séance du Soir")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private func seanceContent(data: SeanceData) -> some View {
        if data.alreadyLogged {
            AlreadyLoggedSeanceView(data: data, vm: vm)
        } else if data.today == "Yoga / Tai Chi" || data.today == "Recovery" {
            SpecialSeanceView(sessionType: data.today, vm: vm)
        } else {
            WorkoutSeanceView(data: data, vm: vm, isSecondSession: true)
        }
    }
}
