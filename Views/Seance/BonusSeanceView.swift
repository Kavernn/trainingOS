import SwiftUI

// MARK: - ViewModel
class BonusSeanceViewModel: SeanceViewModel {
    override init(draftSessionType: String = "bonus") {
        super.init(draftSessionType: draftSessionType)
    }

    override func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil, bonusSession: Bool = true) async {
        let exos = logResults.values.map { "\($0.name) \($0.weight)lbs \($0.reps)" }
        do {
            try await APIService.shared.logSession(exos: exos, rpe: rpe, comment: comment,
                                                   durationMin: durationMin, energyPre: energyPre,
                                                   bonusSession: true)
            showSuccess = true
            await APIService.shared.fetchDashboard()
        } catch { submitError = error.localizedDescription }
    }
}

// MARK: - View
struct BonusSeanceView: View {
    @StateObject private var vm = BonusSeanceViewModel()
    @State private var localExercises: [String: String] = [:]
    @State private var exerciseOrder: [String] = []
    @State private var inventoryTypes: [String: String] = [:]
    @State private var inventoryTracking: [String: String] = [:]
    @State private var inventory: [String] = []
    @State private var showAddExercise = false
    @State private var showFinish = false
    @State private var rpe: Double = 7
    @State private var comment = ""
    @State private var isLoading = true
    @ObservedObject private var timer = RestTimerManager.shared
    @State private var sessionStart = Date()
    @State private var expandedExercise: String? = nil

    private var orderedExercises: [String] {
        exerciseOrder.filter { localExercises[$0] != nil }
    }

    @ViewBuilder private func exerciseCard(for name: String) -> some View {
        let idx = orderedExercises.firstIndex(of: name)
        let next = idx.flatMap { $0 + 1 < orderedExercises.count ? orderedExercises[$0 + 1] : nil }
        ExerciseCard(
            name: name,
            scheme: localExercises[name] ?? "3x8-12",
            weightData: vm.seanceData?.weights[name],
            equipmentType: inventoryTypes[name] ?? "machine",
            trackingType: inventoryTracking[name] ?? "reps",
            bodyWeight: APIService.shared.dashboard?.profile.weight ?? 0,
            isSecondSession: false,
            isBonusSession: true,
            logResult: $vm.logResults[name],
            isExpanded: expandedExercise == name,
            onToggle: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    expandedExercise = expandedExercise == name ? nil : name
                }
            },
            nextExerciseName: next
        )
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var addExerciseButton: some View {
        let label = HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundColor(.orange)
            Text("Ajouter un exercice")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
        Button { showAddExercise = true } label: { label }
            .buttonStyle(SpringButtonStyle())
            .padding(.horizontal, 16)
    }

    private var computedRPE: Double {
        let vals = vm.logResults.values.compactMap(\.rpe)
        guard !vals.isEmpty else { return 7.0 }
        return (vals.reduce(0, +) / Double(vals.count) * 2).rounded() / 2
    }

    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()
            if isLoading {
                ProgressView().tint(.orange)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SÉANCE BONUS")
                                    .font(.system(size: 13, weight: .black))
                                    .tracking(3)
                                    .foregroundColor(.gray)
                                Text("Séance libre")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

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
                        if !vm.logResults.isEmpty {
                            Button { showFinish = true } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Terminer la séance")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if timer.currentExerciseName != nil {
                        FloatingRestTimerBar()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: timer.currentExerciseName != nil)
            }
        }
        .navigationTitle("Séance Bonus")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadInventory() }
        .sheet(isPresented: $showAddExercise) {
            AddExerciseSheet(
                seance: "Bonus",
                inventory: inventory,
                inventorySchemes: [:]
            ) { name, scheme in
                if localExercises[name] == nil {
                    exerciseOrder.append(name)
                }
                localExercises[name] = scheme
            }
        }
        .sheet(isPresented: $showFinish) {
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
    }

    private func loadInventory() async {
        await vm.load()

        guard let url = URL(string: "https://training-os-rho.vercel.app/api/programme_data"),
              let (data, _) = try? await URLSession.authed.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { isLoading = false; return }

        let inv      = (json["inventory"] as? [String]) ?? []
        let types    = (json["inventory_types"] as? [String: String]) ?? [:]
        let tracking = (json["inventory_tracking"] as? [String: String]) ?? [:]
        await MainActor.run {
            inventory         = inv
            inventoryTypes    = types
            inventoryTracking = tracking
            isLoading         = false
        }
    }
}
