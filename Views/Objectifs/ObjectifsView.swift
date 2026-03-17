import SwiftUI

struct ObjectifsView: View {
    @State private var objectifs: [ObjectifEntry] = []
    @State private var isLoading = true
    @State private var showAddGoal = false

    @State private var selectedObjectif: ObjectifEntry? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)

                if isLoading {
                    ProgressView().tint(.orange).scaleEffect(1.3)
                } else if objectifs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "target").font(.system(size: 48)).foregroundColor(.gray)
                        Text("Aucun objectif").foregroundColor(.gray)
                        Button("Ajouter un objectif") { showAddGoal = true }.foregroundColor(.orange)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(Array(objectifs.enumerated()), id: \.1.id) { i, obj in
                                ObjectifCard(obj: obj)
                                    .onTapGesture { selectedObjectif = obj }
                                    .appearAnimation(delay: Double(i) * 0.06)
                            }
                            Spacer(minLength: 80)
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Objectifs")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddGoal) {
                AddGoalSheet { await loadData() }
            }
            .sheet(item: $selectedObjectif) { obj in
                EditGoalSheet(obj: obj) { await loadData() }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showAddGoal = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        objectifs = (try? await APIService.shared.fetchObjectifsData()) ?? []
        isLoading = false
    }
}

struct ObjectifCard: View {
    let obj: ObjectifEntry
    @ObservedObject private var units = UnitSettings.shared

    var pct: Double {
        guard obj.goal > 0 else { return 0 }
        return min(obj.current / obj.goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(obj.exercise)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    if !obj.deadline.isEmpty {
                        Text("Deadline: \(obj.deadline)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                if obj.achieved {
                    Label("Atteint", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTUEL")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    Text(units.format(obj.current))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(obj.achieved ? .green : .orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("OBJECTIF")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    Text(units.format(obj.goal))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "191926"))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(obj.achieved ? Color.green : Color.orange)
                        .frame(width: geo.size.width * pct, height: 8)
                        .animation(.easeOut(duration: 0.5), value: pct)
                }
            }
            .frame(height: 8)

            Text("\(Int(pct * 100))% complété")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(16)
        .glassCardAccent(obj.achieved ? .green : .orange)
        .cornerRadius(16)
    }
}

struct AddGoalSheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared

    @State private var exercise = ""
    @State private var goalWeight = ""
    @State private var deadline = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Form {
                    Section {
                        TextField("Nom de l'exercice", text: $exercise)
                            .foregroundColor(.white)
                        TextField("Poids objectif (\(units.label))", text: $goalWeight)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.white)
                        TextField("Deadline (YYYY-MM-DD)", text: $deadline)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color(hex: "11111c"))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Nouvel objectif")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") {
                        guard !exercise.isEmpty, let gw = Double(goalWeight).map({ units.toStorage($0) }) else { return }
                        Task {
                            try? await APIService.shared.setGoal(exercise: exercise, goalWeight: gw, deadline: deadline)
                            await onSaved()
                            dismiss()
                        }
                    }
                    .foregroundColor(.orange)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct EditGoalSheet: View {
    let obj: ObjectifEntry
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared

    @State private var goalWeight: String
    @State private var deadline: String

    init(obj: ObjectifEntry, onSaved: @escaping () async -> Void) {
        self.obj = obj
        self.onSaved = onSaved
        _goalWeight = State(initialValue: UnitSettings.shared.inputStr(obj.goal))
        _deadline = State(initialValue: obj.deadline)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 20) {
                    Text(obj.exercise)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("POIDS OBJECTIF (\(units.label.uppercased()))")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            TextField("0.0", text: $goalWeight)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("DEADLINE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            TextField("YYYY-MM-DD", text: $deadline)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)

                    Button(action: save) {
                        Text("Sauvegarder")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let gw = Double(goalWeight).map({ units.toStorage($0) }) else { return }
        Task {
            try? await APIService.shared.setGoal(exercise: obj.exercise, goalWeight: gw, deadline: deadline)
            await onSaved()
            dismiss()
        }
    }
}
