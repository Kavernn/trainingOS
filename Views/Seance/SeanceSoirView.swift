import SwiftUI

// MARK: - ViewModel

class SeanceSoirViewModel: SeanceViewModel {

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

    override func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil) async {
        let exos = logResults.values.map { "\($0.name) \($0.weight)lbs \($0.reps)" }
        do {
            try await APIService.shared.logSession(exos: exos, rpe: rpe, comment: comment,
                                                   durationMin: durationMin, energyPre: energyPre,
                                                   secondSession: true)
            showSuccess = true
            await APIService.shared.fetchDashboard()
        } catch { submitError = error.localizedDescription }
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
            .keyboardOkButton()
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
