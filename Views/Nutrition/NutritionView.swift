import SwiftUI
import Combine

struct NutritionView: View {
    @StateObject private var vm = NutritionViewModel()
    @State private var energy: EnergyDaily? = nil
    @State private var showAdd = false
    @State private var toast: ToastMessage? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: Color.forge)
                if vm.isLoading && vm.entries.isEmpty {
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
                            KcalHeader(consumed: consumed, target: energy?.tdee)
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
                    do {
                        try await APIService.shared.addNutritionEntry(
                            name: finalName, calories: 0,
                            proteines: p, glucides: g, lipides: l
                        )
                        await reload()
                        toast = ToastMessage(message: "\(finalName) ajouté ✓", style: .success)
                    } catch {
                        toast = ToastMessage(message: "Échec ajout — réessaie", style: .error)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showAdd = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding)
            }
        }
        .task { await reload() }
        .toast($toast)
    }

    private var consumed: Int { Int(vm.totals?.calories ?? 0) }

    private func reload() async {
        await vm.loadData(silent: false)
        energy = try? await APIService.shared.fetchEnergyDaily()
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
        HStack(spacing: 10) {
            tile("Protéines", Int(totals?.proteines ?? 0))
            tile("Lipides",   Int(totals?.lipides   ?? 0))
            tile("Glucides",  Int(totals?.glucides  ?? 0))
        }
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
                        Button { onDelete(entry) } label: {
                            Image(systemName: "trash")
                                .foregroundColor(Color.appDanger)
                        }
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
private struct SimpleAddNutritionSheet: View {
    let onSave: (String, Double, Double, Double) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pStr = ""
    @State private var lStr = ""
    @State private var gStr = ""
    @State private var saving = false

    private var p: Double { Double(pStr.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var l: Double { Double(lStr.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var g: Double { Double(gStr.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var kcal: Int { Int((p * 4) + (g * 4) + (l * 9)) }
    private var canSave: Bool { p > 0 || l > 0 || g > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Macros (g)") {
                    macroField("Protéines", text: $pStr)
                    macroField("Lipides",   text: $lStr)
                    macroField("Glucides",  text: $gStr)
                }
                Section("Nom (optionnel)") {
                    TextField("Repas", text: $name)
                }
                Section {
                    HStack {
                        Text("Calories")
                        Spacer()
                        Text("\(kcal) kcal")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.appTextPrimary)
                    }
                }
            }
            .navigationTitle("Ajouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "…" : "Ajouter") {
                        saving = true
                        Task {
                            await onSave(name, p, l, g)
                            dismiss()
                        }
                    }
                    .disabled(!canSave || saving)
                }
            }
        }
    }

    private func macroField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 100, alignment: .leading)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NutritionView()
        .environmentObject(AppState.shared)
}
