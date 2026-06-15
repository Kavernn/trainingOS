import SwiftUI

// MARK: - Edit Nutrition Sheet
struct EditNutritionSheet: View {
    let entry: NutritionEntry
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var calories: String
    @State private var proteines: String
    @State private var glucides: String
    @State private var lipides: String
    // N-D10: editable mealType
    @State private var mealType: String
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var confirmDiscard = false

    private var isDirty: Bool {
        name      != (entry.name ?? "") ||
        calories  != (entry.calories.map  { String(Int($0)) }             ?? "") ||
        proteines != (entry.proteines.map { String(format: "%.1f", $0) } ?? "") ||
        glucides  != (entry.glucides.map  { String(format: "%.1f", $0) } ?? "") ||
        lipides   != (entry.lipides.map   { String(format: "%.1f", $0) } ?? "") ||
        mealType  != (entry.mealType ?? "matin")
    }

    init(entry: NutritionEntry, onSaved: @escaping () async -> Void) {
        self.entry = entry
        self.onSaved = onSaved
        _name      = State(initialValue: entry.name ?? "")
        _calories  = State(initialValue: entry.calories.map { String(Int($0)) } ?? "")
        _proteines = State(initialValue: entry.proteines.map { String(format: "%.1f", $0) } ?? "")
        _glucides  = State(initialValue: entry.glucides.map { String(format: "%.1f", $0) } ?? "")
        _lipides   = State(initialValue: entry.lipides.map { String(format: "%.1f", $0) } ?? "")
        _mealType  = State(initialValue: entry.mealType ?? "matin")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                Form {
                    // N-D10: editable mealType
                    Section("Repas") {
                        Picker("Repas", selection: $mealType) {
                            Text("Matin").tag("matin")
                            Text("Midi").tag("midi")
                            Text("Soir").tag("soir")
                            Text("Collation").tag("collation")
                            Text("Pré-workout").tag("pre_workout")
                            Text("Post-workout").tag("post_workout")
                        }
                        .pickerStyle(.menu)
                        .foregroundColor(.appTextPrimary)
                        .tint(Color.forge)
                    }.listRowBackground(Color.appCard)
                    Section("Aliment") {
                        TextField("Nom", text: $name).foregroundColor(.appTextPrimary)
                        TextField("Calories (kcal)", text: $calories).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                    }.listRowBackground(Color.appCard)
                    Section("Macros (g)") {
                        TextField("Protéines", text: $proteines).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                        TextField("Glucides",  text: $glucides).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                        TextField("Lipides",   text: $lipides).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                    }.listRowBackground(Color.appCard)
                    if let err = saveError {
                        Section {
                            Text(err)
                                .font(.appLabel.weight(.regular))
                                .foregroundColor(.red)
                        }.listRowBackground(Color.appCard)
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }.foregroundColor(Color.forge)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") { Task { await save() } }
                        .foregroundColor(Color.forge).fontWeight(.semibold)
                        .disabled(name.isEmpty || calories.isEmpty || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("Abandonner les modifications ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { dismiss() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Les valeurs modifiées seront perdues.")
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        guard let eid = entry.entryId,
              let cal = Double(calories.replacingOccurrences(of: ",", with: ".")) else { return }
        isSaving = true
        saveError = nil
        // N-D10: include mealType in update payload
        var body: [String: Any] = ["id": eid, "nom": name, "calories": cal, "meal_type": mealType]
        if let v = Double(proteines.replacingOccurrences(of: ",", with: ".")) { body["proteines"] = v }
        if let v = Double(glucides.replacingOccurrences(of: ",", with: "."))  { body["glucides"]  = v }
        if let v = Double(lipides.replacingOccurrences(of: ",", with: "."))   { body["lipides"]   = v }
        do {
            _ = try await APIService.shared.offlinePost(endpoint: "/api/nutrition/edit", payload: body)
            await onSaved()
            isSaving = false
            dismiss()
        } catch {
            saveError = "Erreur réseau — réessaie"
            isSaving = false
        }
    }
}
