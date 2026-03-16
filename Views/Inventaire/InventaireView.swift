import SwiftUI

private let kBaseURL = "https://training-os-rho.vercel.app"

// MARK: - Model

struct InventoryItem: Identifiable {
    var id: String { name }
    var name: String
    var type: String
    var category: String
    var level: String
    var barWeight: Double
    var increment: Double
    var defaultScheme: String
    var muscles: [String]
    init(name: String, _ d: [String: Any]) {
        self.name          = name
        self.type          = d["type"]          as? String ?? "machine"
        self.category      = d["category"]      as? String ?? ""
        self.level         = d["level"]         as? String ?? ""
        self.barWeight     = d["bar_weight"]    as? Double ?? 0
        self.increment     = d["increment"]     as? Double ?? 5
        self.defaultScheme = d["default_scheme"] as? String ?? "3x8-12"
        self.muscles       = d["muscles"]       as? [String] ?? []
    }
}

// MARK: - View

struct InventaireView: View {
    @State private var items: [InventoryItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedType = "Tous"
    @State private var selectedCategory = "Tous"
    @State private var editTarget: InventoryItem?
    @State private var showAdd = false
    @State private var errorMsg: String?

    let types      = ["Tous", "barbell", "dumbbell", "cable", "machine", "bodyweight"]
    let categories = ["Tous", "push", "pull", "legs", "core", "mobility"]

    var filtered: [InventoryItem] {
        items.filter { item in
            (selectedType == "Tous" || item.type == selectedType) &&
            (selectedCategory == "Tous" || item.category == selectedCategory) &&
            (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText))
        }
        .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.orange)
                } else {
                    VStack(spacing: 0) {
                        searchBar
                        typeFilter
                        categoryFilter
                        countLabel
                        if filtered.isEmpty {
                            emptyState
                        } else {
                            itemList
                        }
                    }
                }
            }
            .navigationTitle("Inventaire")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                InventoryFormSheet(existing: nil) { saved in
                    Task { await postSave(saved) }
                }
            }
            .sheet(item: $editTarget) { target in
                InventoryFormSheet(existing: target) { saved in
                    Task { await postSave(saved, originalName: target.name) }
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: – Subviews

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Rechercher...", text: $searchText)
                .foregroundColor(.white)
                .tint(.orange)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color(hex: "11111c"))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var typeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(types, id: \.self) { t in
                    FilterChip(label: typeLabel(t), selected: selectedType == t, color: typeColor(t)) {
                        selectedType = t
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { c in
                    FilterChip(label: catLabel(c), selected: selectedCategory == c, color: catColor(c)) {
                        selectedCategory = c
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private var countLabel: some View {
        HStack {
            Text("\(filtered.count) exercice\(filtered.count != 1 ? "s" : "")")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundColor(.gray)
            Text("Aucun exercice trouvé").foregroundColor(.gray)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemList: some View {
        List {
            ForEach(filtered, id: \.name) { item in
                InventaireRow(item: item)
                    .listRowBackground(Color(hex: "11111c"))
                    .listRowSeparatorTint(Color.white.opacity(0.07))
                    .contentShape(Rectangle())
                    .onTapGesture { editTarget = item }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await deleteItem(item.name) }
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: – Network

    private func loadData() async {
        isLoading = true
        let url = URL(string: "\(kBaseURL)/api/inventaire_data")!
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let inv  = json["inventory"] as? [String: [String: Any]] {
            let loaded = inv.map { InventoryItem(name: $0.key, $0.value) }
            await MainActor.run { items = loaded }
        }
        await MainActor.run { isLoading = false }
    }

    private func postSave(_ item: InventoryItem, originalName: String? = nil) async {
        var body: [String: Any] = [
            "name":           item.name,
            "type":           item.type,
            "category":       item.category,
            "level":          item.level,
            "bar_weight":     item.barWeight,
            "increment":      item.increment,
            "default_scheme": item.defaultScheme,
        ]
        if let orig = originalName, orig != item.name {
            body["original_name"] = orig
        }
        guard let url = URL(string: "\(kBaseURL)/api/save_exercise") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
        CacheService.shared.clear(for: "inventaire_data")
        CacheService.shared.clear(for: "programme_data")
        await loadData()
    }

    private func deleteItem(_ name: String) async {
        guard let url = URL(string: "\(kBaseURL)/api/delete_exercise") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])
        _ = try? await URLSession.shared.data(for: req)
        await MainActor.run { items.removeAll { $0.name == name } }
        CacheService.shared.clear(for: "inventaire_data")
        CacheService.shared.clear(for: "programme_data")
    }

    // MARK: – Helpers

    private func typeLabel(_ t: String) -> String {
        switch t {
        case "barbell": return "Barre"; case "dumbbell": return "Haltère"
        case "cable": return "Câble"; case "machine": return "Machine"
        case "bodyweight": return "Corps"; default: return "Tous"
        }
    }

    private func catLabel(_ c: String) -> String {
        switch c {
        case "push": return "Push"; case "pull": return "Pull"; case "legs": return "Jambes"
        case "core": return "Core"; case "mobility": return "Mobilité"; default: return "Tous"
        }
    }

    private func typeColor(_ t: String) -> Color {
        switch t {
        case "barbell": return .orange; case "dumbbell": return .blue
        case "cable": return .teal; case "machine": return .purple
        case "bodyweight": return .green; default: return .gray
        }
    }

    private func catColor(_ c: String) -> Color {
        switch c {
        case "push": return .red; case "pull": return .blue
        case "legs": return .green; case "core": return .orange
        case "mobility": return .purple; default: return .gray
        }
    }
}

// MARK: - Row

struct InventaireRow: View {
    let item: InventoryItem

    var typeIcon: String {
        switch item.type {
        case "barbell":    return "chart.bar.fill"
        case "dumbbell":   return "dumbbell.fill"
        case "cable":      return "link"
        case "bodyweight": return "figure.walk"
        default:           return "figure.strengthtraining.traditional"
        }
    }

    var typeColor: Color {
        switch item.type {
        case "barbell": return .orange; case "dumbbell": return .blue
        case "cable": return .teal; case "bodyweight": return .green
        default: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: typeIcon)
                    .font(.system(size: 16))
                    .foregroundColor(typeColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Text(item.type.capitalized)
                        .font(.system(size: 11)).foregroundColor(.gray)
                    if !item.category.isEmpty {
                        Text("·").foregroundColor(.gray.opacity(0.4)).font(.system(size: 11))
                        Text(item.category.capitalized)
                            .font(.system(size: 11)).foregroundColor(.gray)
                    }
                    if !item.defaultScheme.isEmpty {
                        Text("·").foregroundColor(.gray.opacity(0.4)).font(.system(size: 11))
                        Text(item.defaultScheme)
                            .font(.system(size: 11, weight: .medium)).foregroundColor(.orange.opacity(0.8))
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.4))
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Form Sheet (Add & Edit)

struct InventoryFormSheet: View {
    let existing: InventoryItem?
    let onSave: (InventoryItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name         = ""
    @State private var type         = "machine"
    @State private var category     = ""
    @State private var level        = ""
    @State private var defaultScheme = "3x8-12"
    @State private var increment    = "5"
    @State private var barWeight    = "0"

    let types      = ["barbell", "dumbbell", "cable", "machine", "bodyweight"]
    let categories = ["", "push", "pull", "legs", "core", "mobility"]
    let levels     = ["", "beginner", "intermediate", "advanced"]
    let schemes    = ["3x5", "4x5-7", "3x8-10", "4x8-10", "3x10-12", "4x12-15", "3x15"]

    private var isEditing: Bool { existing != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Form {
                    Section("Nom") {
                        TextField("Nom de l'exercice", text: $name)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    Section("Type") {
                        Picker("Type", selection: $type) {
                            ForEach(types, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    Section("Catégorie") {
                        Picker("Catégorie", selection: $category) {
                            ForEach(categories, id: \.self) {
                                Text($0.isEmpty ? "—" : $0.capitalized).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    Section("Schéma par défaut") {
                        TextField("ex: 4x6-8", text: $defaultScheme)
                            .foregroundColor(.white)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(schemes, id: \.self) { s in
                                    Button { defaultScheme = s } label: {
                                        Text(s)
                                            .font(.system(size: 12, weight: .medium))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(defaultScheme == s ? Color.orange : Color(hex: "191926"))
                                            .foregroundColor(defaultScheme == s ? .black : .white)
                                            .cornerRadius(16)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    Section("Paramètres") {
                        HStack {
                            Text("Incrément (lbs)").foregroundColor(.gray)
                            Spacer()
                            TextField("5", text: $increment)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                                .frame(width: 60)
                        }
                        if type == "barbell" {
                            HStack {
                                Text("Poids barre (lbs)").foregroundColor(.gray)
                                Spacer()
                                TextField("45", text: $barWeight)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.white)
                                    .frame(width: 60)
                            }
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    Section("Niveau") {
                        Picker("Niveau", selection: $level) {
                            ForEach(levels, id: \.self) {
                                Text($0.isEmpty ? "—" : $0.capitalized).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color(hex: "11111c"))
                }
                .scrollContentBackground(.hidden)
                .foregroundColor(.white)
            }
            .navigationTitle(isEditing ? "Modifier" : "Nouvel exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        var item = InventoryItem(name: trimmed, [:])
                        item.type          = type
                        item.category      = category
                        item.level         = level
                        item.defaultScheme = defaultScheme
                        item.increment     = Double(increment) ?? 5
                        item.barWeight     = Double(barWeight) ?? 0
                        onSave(item)
                        dismiss()
                    }
                    .foregroundColor(canSave ? .orange : .gray)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if let e = existing {
                name          = e.name
                type          = e.type
                category      = e.category
                level         = e.level
                defaultScheme = e.defaultScheme
                increment     = String(e.increment)
                barWeight     = String(e.barWeight)
            }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let selected: Bool
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? color.opacity(0.2) : Color(hex: "191926"))
                .foregroundColor(selected ? color : .gray)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? color.opacity(0.5) : Color.clear, lineWidth: 1))
        }
    }
}
