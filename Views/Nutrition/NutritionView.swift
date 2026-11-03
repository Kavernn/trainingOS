import SwiftUI
import Combine

struct NutritionView: View {
    @StateObject private var vm = NutritionViewModel()
    @State private var showAdd = false
    @State private var toast: ToastMessage? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: Color.forge)
                if vm.isLoading && !vm.hasLoaded {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            if let err = vm.networkError {
                                ErrorBannerView(error: err,
                                    onRetry: { Task { await reload() } },
                                    onDismiss: { vm.networkError = nil })
                                    .padding(.horizontal, 16)
                            }
                            KcalHeader(consumed: consumed, target: vm.energy?.targetCalories)
                                .padding(.horizontal, 16)
                            MacroRow(totals: vm.totals)
                                .padding(.horizontal, 16)
                            EntriesList(entries: vm.entries,
                                        onDelete: { entry in
                                            Task { await vm.deleteEntry(entry) }
                                        })
                                .padding(.horizontal, 16)
                            Spacer(minLength: fabBottomPadding + 72)
                        }
                        .padding(.vertical, 16)
                    }
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAdd) {
                SimpleAddNutritionSheet { name, p, l, g in
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let finalName = trimmed.isEmpty ? "Repas" : trimmed
                    try await APIService.shared.addNutritionEntry(
                        name: finalName, calories: 0,
                        proteines: p, glucides: g, lipides: l
                    )
                    await reload()
                    toast = ToastMessage(message: "\(finalName) ajouté ✓", style: .success)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showAdd = true }
                    .accessibilityLabel("Ajouter un repas")
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding)
            }
        }
        .task { await reload() }
        .toast($toast)
    }

    private var consumed: Int { Int(vm.totals?.calories ?? 0) }

    private func reload() async {
        await vm.loadData()
    }
}

// MARK: - Header (kcal + barre vs TDEE)
private struct KcalHeader: View {
    let consumed: Int
    let target: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(consumed)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Text("kcal")
                    .font(.appLabel)
                    .foregroundColor(.gray)
                Spacer()
                if let t = target {
                    Text("sur \(t)")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
            }
            if let t = target, t > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.appCard).frame(height: 10)
                        Capsule().fill(Color.forge)
                            .frame(width: min(geo.size.width,
                                              geo.size.width * CGFloat(consumed) / CGFloat(t)),
                                   height: 10)
                    }
                }
                .frame(height: 10)
                let diff = t - consumed
                Text(diff >= 0 ? "\(diff) kcal restantes" : "\(-diff) kcal au-dessus")
                    .font(.appCaption)
                    .foregroundColor(diff >= 0 ? .gray : Color.statusOrange)
            } else {
                Text("Objectif non calculé — voir Énergie")
                    .font(.appCaption)
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Macros (grammes accumulés, info seule)
private struct MacroRow: View {
    let totals: NutritionTotals?
    var body: some View {
        tile("Protéines", Int(totals?.proteines ?? 0))
    }
    private func tile(_ label: String, _ grams: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(grams) g")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.appTextPrimary)
            Text(label)
                .font(.appCaption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.appCard)
        .cornerRadius(12)
    }
}

// MARK: - Entrées du jour (delete direct, pas d'undo)
private struct EntriesList: View {
    let entries: [NutritionEntry]
    let onDelete: (NutritionEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entrées du jour")
                .font(.appLabel).fontWeight(.semibold)
                .foregroundColor(.gray)
            if entries.isEmpty {
                Text("Aucune entrée — tap + pour ajouter")
                    .font(.appCaption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name ?? "Repas")
                                .font(.appLabel)
                                .foregroundColor(.appTextPrimary)
                            Text("P\(Int(entry.proteines ?? 0))  L\(Int(entry.lipides ?? 0))  G\(Int(entry.glucides ?? 0))")
                                .font(.appCaption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Text("\(Int(entry.calories ?? 0)) kcal")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                        Button(role: .destructive) { onDelete(entry) } label: {
                            Image(systemName: "trash")
                                .foregroundColor(Color.appDanger)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Supprimer \(entry.name ?? "ce repas")")
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.appCard)
                    .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - Sheet simple : P/L/G + nom optionnel + aperçu kcal live
struct SimpleAddNutritionSheet: View {
    let onSave: (String, Double, Double, Double) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pStr = ""
    @State private var lStr = ""
    @State private var gStr = ""
    @State private var saving = false

    @State private var saveError: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var draft: NutritionMacroDraft? {
        NutritionMacroDraft(protein: pStr, fat: lStr, carbs: gStr)
    }
    private var canSave: Bool { draft?.canSave == true }

    var body: some View {
        NavigationStack {
            Form {
                Section("Macros (g)") {
                    macroField("Protéines", text: $pStr)
                    macroField("Lipides",   text: $lStr)
                    macroField("Glucides",  text: $gStr)
                }
                if draft == nil {
                    Section {
                        Text("Saisis des nombres positifs valides, avec une virgule ou un point décimal.")
                            .foregroundColor(.appDanger)
                    }
                }
                if let saveError {
                    Section { Text(saveError).foregroundColor(.appDanger) }
                }
                Section("Nom (optionnel)") {
                    TextField("Repas", text: $name)
                }
                Section {
                    HStack {
                        Text("Calories")
                        Spacer()
                        Text(draft.map { "\($0.calories) kcal" } ?? "Valeurs invalides")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.appTextPrimary)
                    }
                }
            }
            .interactiveDismissDisabled(saving)
            .navigationTitle("Ajouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "…" : "Ajouter") {
                        guard let draft, draft.canSave, !saving else { return }
                        saving = true
                        saveError = nil
                        Task {
                            defer { saving = false }
                            do {
                                try await onSave(name, draft.protein, draft.fat, draft.carbs)
                                dismiss()
                            } catch {
                                saveError = "Ajout impossible. Tes valeurs sont conservées ; réessaie."
                            }
                        }
                    }
                    .disabled(!canSave || saving)
                }
            }
        }
    }

    private func macroField(_ label: String, text: Binding<String>) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading))
            : AnyLayout(HStackLayout())
        return layout {
            Text(label)
            TextField("0", text: text)
                .accessibilityLabel("\(label), en grammes")
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NutritionView()
        .environmentObject(AppState.shared)
}
