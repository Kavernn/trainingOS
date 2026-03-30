import SwiftUI

// MARK: - Catalogue Manager Sheet

struct FoodCatalogView: View {
    @Binding var items: [FoodItem]
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var editTarget: FoodItem? = nil
    @State private var pendingDelete: IndexSet? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.35))
                        Text("Catalogue vide")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                        Text("Tape + pour ajouter un aliment")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                } else {
                    List {
                        ForEach(items) { item in
                            Button { editTarget = item } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text("pour \(formatQty(item.refQty)) \(item.refUnit)")
                                                .font(.system(size: 12))
                                                .foregroundColor(.gray)
                                        }
                                        HStack(spacing: 12) {
                                            macroChip("\(Int(item.calories)) kcal", .orange)
                                            macroChip("\(fmt(item.proteines))g P", .blue)
                                            macroChip("\(fmt(item.glucides))g C", .yellow)
                                            macroChip("\(fmt(item.lipides))g L", .pink)
                                        }
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.gray.opacity(0.35))
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color(hex: "11111c"))
                        }
                        .onDelete { idx in
                            pendingDelete = idx
                            showDeleteConfirm = true
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Catalogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").foregroundColor(.orange)
                    }
                }
            }
            .confirmationDialog("Supprimer cet aliment du catalogue ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let idx = pendingDelete {
                        items.remove(atOffsets: idx)
                        FoodCatalogStore.save(items)
                        Task { await APIService.shared.saveFoodCatalog(items) }
                    }
                }
                Button("Annuler", role: .cancel) { pendingDelete = nil }
            }
            .sheet(isPresented: $showAdd) {
                FoodItemFormView(existing: nil) { newItem in
                    items.append(newItem)
                    FoodCatalogStore.save(items)
                    Task { await APIService.shared.saveFoodCatalog(items) }
                }
            }
            .sheet(item: $editTarget) { item in
                FoodItemFormView(existing: item) { updated in
                    if let idx = items.firstIndex(where: { $0.id == updated.id }) {
                        items[idx] = updated
                        FoodCatalogStore.save(items)
                        Task { await APIService.shared.saveFoodCatalog(items) }
                    }
                }
            }
        }
    }

    private func macroChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(6)
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private func formatQty(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

// MARK: - Add / Edit Form

struct FoodItemFormView: View {
    let existing: FoodItem?
    let onSave: (FoodItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var refQty: String
    @State private var refUnit: String
    @State private var calories: String
    @State private var proteines: String
    @State private var glucides: String
    @State private var lipides: String

    private let units = ["g", "ml", "unité(s)", "portion(s)"]

    init(existing: FoodItem?, onSave: @escaping (FoodItem) -> Void) {
        self.existing = existing
        self.onSave = onSave
        let f = { (v: Double) -> String in
            v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
        }
        let item = existing
        _name      = State(initialValue: item?.name ?? "")
        _refQty    = State(initialValue: item.map { f($0.refQty) } ?? "100")
        _refUnit   = State(initialValue: item?.refUnit ?? "g")
        _calories  = State(initialValue: item.map { f($0.calories) } ?? "")
        _proteines = State(initialValue: item.map { f($0.proteines) } ?? "")
        _glucides  = State(initialValue: item.map { f($0.glucides) } ?? "")
        _lipides   = State(initialValue: item.map { f($0.lipides) } ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && Double(refQty.replacingOccurrences(of: ",", with: ".")) != nil
        && Double(calories.replacingOccurrences(of: ",", with: ".")) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Form {
                    Section("ALIMENT") {
                        TextField("Nom", text: $name).foregroundColor(.white)
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    Section("QUANTITÉ DE RÉFÉRENCE") {
                        HStack {
                            TextField("Quantité", text: $refQty)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                            Picker("", selection: $refUnit) {
                                ForEach(units, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(.orange)
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    Section("MACROS POUR CETTE QUANTITÉ") {
                        HStack {
                            TextField("Calories", text: $calories).keyboardType(.decimalPad).foregroundColor(.white)
                            Text("kcal").foregroundColor(.gray).font(.system(size: 13))
                        }
                        HStack {
                            TextField("Protéines", text: $proteines).keyboardType(.decimalPad).foregroundColor(.white)
                            Text("g").foregroundColor(.gray).font(.system(size: 13))
                        }
                        HStack {
                            TextField("Glucides", text: $glucides).keyboardType(.decimalPad).foregroundColor(.white)
                            Text("g").foregroundColor(.gray).font(.system(size: 13))
                        }
                        HStack {
                            TextField("Lipides", text: $lipides).keyboardType(.decimalPad).foregroundColor(.white)
                            Text("g").foregroundColor(.gray).font(.system(size: 13))
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(existing == nil ? "Nouvel aliment" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") { save() }
                        .foregroundColor(.orange).fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let p = { (s: String) -> Double in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let item = FoodItem(
            id:        existing?.id ?? UUID(),
            name:      name.trimmingCharacters(in: .whitespaces),
            refQty:    p(refQty),
            refUnit:   refUnit,
            calories:  p(calories),
            proteines: p(proteines),
            glucides:  p(glucides),
            lipides:   p(lipides)
        )
        onSave(item)
        dismiss()
    }

}

private func fmt(_ v: Double) -> String {
    v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
}
