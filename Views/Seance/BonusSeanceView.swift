import SwiftUI

// MARK: - ViewModel
class BonusSeanceViewModel: SeanceViewModel {
    override init(draftSessionType: String = "bonus") {
        super.init(draftSessionType: draftSessionType)
    }

    override func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil, bonusSession: Bool = true) async {
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
                    equipmentType: result.equipmentType, painZone: result.painZone)
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
        showSuccess = true
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
    @State private var lastScrollY: CGFloat? = nil

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
        .navigationTitle("Séance Bonus")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if timer.isVisible {
                FloatingRestTimerCard()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.42, dampingFraction: 0.82), value: timer.isVisible)
            }
        }
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
