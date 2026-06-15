import SwiftUI

// MARK: - Catalogue Manager Sheet

struct FoodCatalogView: View {
    @Binding var items: [FoodItem]
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var editTarget: FoodItem? = nil
    @State private var pendingDeleteId: UUID? = nil
    @State private var showDeleteConfirm = false
    @State private var searchText = ""
    // N-D7: track sync failures
    @State private var syncFailed = false

    private var filteredItems: [FoodItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // N-D7: sync failure banner
                    if syncFailed {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.icloud.fill")
                                .foregroundColor(Color.forge)
                            Text("Modifications non synchronisées")
                                .font(.appLabel)
                                .foregroundColor(.appTextPrimary)
                            Spacer()
                            Button {
                                Task { await syncCatalog(items) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(Color.forge)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.forge.opacity(0.1))
                    }

                    List {
                        ForEach(filteredItems) { item in
                            Button {
                                if !item.isBuiltIn { editTarget = item }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(item.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.appTextPrimary)
                                            if item.isBuiltIn {
                                                categoryBadge(item.category)
                                            }
                                            Spacer()
                                            Text("pour \(formatQty(item.refQty)) \(item.refUnit)")
                                                .font(.system(size: 12))
                                                .foregroundColor(.appTextSecondary)
                                        }
                                        HStack(spacing: 12) {
                                            macroChip("\(Int(item.calories)) kcal", Color.appWarning)
                                            macroChip("\(fmt(item.proteines))g P", Color.statusBlue)
                                            macroChip("\(fmt(item.glucides))g C", Color.statusYellow)
                                            macroChip("\(fmt(item.lipides))g L", Color.statusRed)
                                        }
                                    }
                                    if !item.isBuiltIn {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.appTextMuted)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.appCard)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !item.isBuiltIn {
                                    Button(role: .destructive) {
                                        pendingDeleteId = item.id
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Rechercher un aliment")
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Catalogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundColor(Color.forge)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").foregroundColor(Color.forge)
                    }
                }
            }
            .confirmationDialog("Supprimer cet aliment du catalogue ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let deleteId = pendingDeleteId {
                        items.removeAll { $0.id == deleteId }
                        FoodCatalogStore.save(items)
                        Task { await syncCatalog(items) }
                    }
                }
                Button("Annuler", role: .cancel) { pendingDeleteId = nil }
            }
            .sheet(isPresented: $showAdd) {
                FoodItemFormView(existing: nil) { newItem in
                    items.append(newItem)
                    FoodCatalogStore.save(items)
                    Task { await syncCatalog(items) }
                }
            }
            .sheet(item: $editTarget) { item in
                FoodItemFormView(existing: item) { updated in
                    if let idx = items.firstIndex(where: { $0.id == updated.id }) {
                        items[idx] = updated
                        FoodCatalogStore.save(items)
                        Task { await syncCatalog(items) }
                    }
                }
            }
        }
    }

    // N-D7: wrapped save with error tracking
    // offline → offlinePost enqueue (SyncManager retry auto, no throw) → syncFailed=false
    // server error 4xx/5xx → throws → syncFailed=true, bannière visible
    private func syncCatalog(_ current: [FoodItem]) async {
        do {
            try await APIService.shared.saveFoodCatalog(current)
            syncFailed = false
        } catch {
            syncFailed = true
        }
    }

    @ViewBuilder
    private func categoryBadge(_ cat: String) -> some View {
        let color: Color = cat == "Viande" ? Color.appDanger : cat == "Fruit" ? Color.appSuccess : cat == "Légume" ? Color.appWarning : .gray
        Text(cat)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
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

    private enum FoodField: Int, Hashable { case name, qty, calories, proteines, glucides, lipides }
    @FocusState private var foodFocus: FoodField?

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
                Color.appBg.ignoresSafeArea()
                Form {
                    Section("ALIMENT") {
                        TextField("Nom", text: $name)
                            .foregroundColor(.appTextPrimary)
                            .focused($foodFocus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { foodFocus = .qty }
                    }
                    .listRowBackground(Color.appCard)

                    Section("QUANTITÉ DE RÉFÉRENCE") {
                        HStack {
                            TextField("Quantité", text: $refQty)
                                .keyboardType(.decimalPad)
                                .focused($foodFocus, equals: .qty)
                                .foregroundColor(.appTextPrimary)
                            Picker("", selection: $refUnit) {
                                ForEach(units, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.forge)
                        }
                        // N-D8: inline validation for refQty
                        if !refQty.isEmpty && Double(refQty.replacingOccurrences(of: ",", with: ".")) == nil {
                            Text("Doit être un nombre")
                                .font(.caption)
                                .foregroundColor(Color.appDanger)
                        }
                    }
                    .listRowBackground(Color.appCard)

                    Section("MACROS POUR CETTE QUANTITÉ") {
                        HStack {
                            TextField("Calories", text: $calories)
                                .keyboardType(.decimalPad).focused($foodFocus, equals: .calories).foregroundColor(.appTextPrimary)
                            Text("kcal").foregroundColor(.appTextSecondary).font(.appLabel)
                        }
                        HStack {
                            TextField("Protéines", text: $proteines)
                                .keyboardType(.decimalPad).focused($foodFocus, equals: .proteines).foregroundColor(.appTextPrimary)
                            Text("g").foregroundColor(.appTextSecondary).font(.appLabel)
                        }
                        HStack {
                            TextField("Glucides", text: $glucides)
                                .keyboardType(.decimalPad).focused($foodFocus, equals: .glucides).foregroundColor(.appTextPrimary)
                            Text("g").foregroundColor(.appTextSecondary).font(.appLabel)
                        }
                        HStack {
                            TextField("Lipides", text: $lipides)
                                .keyboardType(.decimalPad).focused($foodFocus, equals: .lipides).foregroundColor(.appTextPrimary)
                            Text("g").foregroundColor(.appTextSecondary).font(.appLabel)
                        }
                    }
                    .listRowBackground(Color.appCard)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(existing == nil ? "Nouvel aliment" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") { save() }
                        .foregroundColor(Color.forge).fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if let f = foodFocus {
                        let next: FoodField? = {
                            switch f {
                            case .qty: return .calories
                            case .calories: return .proteines
                            case .proteines: return .glucides
                            case .glucides: return .lipides
                            default: return nil
                            }
                        }()
                        if let next {
                            Button("Suivant →") { foodFocus = next }
                                .font(.appBody.weight(.semibold)).foregroundColor(Color.forge)
                        } else {
                            Button("Ok") { foodFocus = nil }
                                .font(.appBody.weight(.semibold)).foregroundColor(Color.forge)
                        }
                    } else {
                        Button("Ok") { foodFocus = nil }
                            .font(.appBody.weight(.semibold)).foregroundColor(Color.forge)
                    }
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
