import SwiftUI
import Combine
import Charts

private let kBaseURL = APIConfig.base

// MARK: - Model

struct InventoryItem: Identifiable {
    var id: String { name }
    var name: String
    var type: String
    var category: String
    var pattern: String
    var level: String
    var barWeight: Double
    var increment: Double
    var defaultScheme: String
    var muscles: [String]
    var trackingType: String
    var restSeconds: Int?
    var loadProfile: String   // "compound_heavy" | "compound_hypertrophy" | "isolation" | ""
    var gifUrl: String?
    var useCount: Int
    var notes: String?
    init(name: String, _ d: [String: Any]) {
        self.name          = name
        self.type          = d["type"]          as? String ?? "machine"
        self.category      = d["category"]      as? String ?? ""
        self.pattern       = d["pattern"]       as? String ?? ""
        self.level         = d["level"]         as? String ?? ""
        self.barWeight     = d["bar_weight"]    as? Double ?? 0
        self.increment     = d["increment"]     as? Double ?? 5
        self.defaultScheme = d["default_scheme"] as? String ?? "3x8-12"
        self.muscles       = d["muscles"]       as? [String] ?? []
        self.trackingType  = d["tracking_type"] as? String ?? "reps"
        self.restSeconds   = d["rest_seconds"]  as? Int
        self.loadProfile   = d["load_profile"]  as? String ?? ""
        self.gifUrl        = d["gif_url"]        as? String
        self.useCount      = d["use_count"]      as? Int ?? 0
        self.notes         = d["tips"]            as? String
    }
}

// MARK: - View

struct CatalogueView: View {
    @State private var items: [InventoryItem] = []
    @State private var inProgram: Set<String> = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var selectedType = "Tous"
    @State private var selectedCategory = "Tous"
    @State private var filterProgram = false
    @State private var editTarget: InventoryItem?
    @State private var showAdd = false
    @State private var prefillName = ""
    @State private var errorMsg: String?
    @State private var pendingDelete: String?
    @State private var addToProgramTarget: InventoryItem?
    @State private var detailTarget: InventoryItem?

    private enum SortOrder: String, CaseIterable {
        case alpha     = "A–Z"
        case frequency = "Fréquence"
        var icon: String { self == .alpha ? "textformat.abc" : "chart.bar.fill" }
    }
    @State private var sortOrder: SortOrder = .alpha

    let types      = ["Tous", "barbell", "ez-bar", "dumbbell", "cable", "cable_double", "machine", "bodyweight", "endurance"]
    let categories = ["Tous", "push", "pull", "legs", "core", "mobility"]

    var filtered: [InventoryItem] {
        let base = items.filter { item in
            (selectedType == "Tous" ||
             (selectedType == "endurance" ? item.trackingType == "time" : item.type == selectedType)) &&
            (selectedCategory == "Tous" || item.category == selectedCategory) &&
            (!filterProgram || inProgram.contains(item.name)) &&
            (debouncedSearch.isEmpty || item.name.localizedCaseInsensitiveContains(debouncedSearch))
        }
        switch sortOrder {
        case .alpha:     return base.sorted { $0.name < $1.name }
        case .frequency: return base.sorted { $0.useCount > $1.useCount }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if isLoading {
                    CatalogueSkeletonView()
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
                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            prefillName = ""
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.forge)
                                .clipShape(Circle())
                                .shadow(color: Color.forge.opacity(0.4), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                        .padding(.bottom, fabBottomPadding + 16)
                    }
                }
                .zIndex(5)
            }
            .navigationTitle("Catalogue")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: GraveyardView()) {
                        Image(systemName: "archivebox.fill")
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(Color(hex: "8B6AFF"))
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                Label(order.rawValue, systemImage: sortOrder == order ? "checkmark" : order.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(sortOrder == .frequency ? Color.forge : .gray)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                InventoryFormSheet(existing: nil, prefillName: prefillName.isEmpty ? nil : prefillName, existingNames: items.map(\.name)) { saved in
                    Task { await postSave(saved) }
                }
            }
            .sheet(item: $editTarget) { target in
                InventoryFormSheet(existing: target, existingNames: items.map(\.name)) { saved in
                    Task { await postSave(saved, originalName: target.name) }
                }
            }
            .sheet(item: $addToProgramTarget) { target in
                AddExerciseToProgramSheet(exercise: target) {
                    Task { await loadData() }
                }
            }
            .sheet(item: $detailTarget) { target in
                CatalogueExerciseDetailView(item: target, isInProgram: inProgram.contains(target.name)) {
                    editTarget = target
                } onArchive: {
                    pendingDelete = target.name
                } onAddToProgram: {
                    addToProgramTarget = target
                } onReload: {
                    Task { await loadData() }
                }
            }
        }
        .task { await loadData() }
        .onChange(of: searchText) { _, new in
            if new.isEmpty {
                debouncedSearch = ""
            } else {
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if searchText == new { debouncedSearch = new }
                }
            }
        }
        .confirmationDialog(
            "Archiver \(pendingDelete ?? "") ?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archiver", role: .destructive) {
                if let name = pendingDelete {
                    Task { await deleteItem(name) }
                    pendingDelete = nil
                }
            }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Ton historique et tes stats sont préservés. L'exercice n'apparaîtra plus dans le catalogue.")
        }
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
        .background(Color.appCard)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var typeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(types, id: \.self) { t in
                    ChipButton(label: typeLabel(t), isSelected: selectedType == t, size: .small) {
                        selectedType = t
                    }
                }
                ChipButton(label: "⭐ En programme", isSelected: filterProgram, size: .small) {
                    filterProgram.toggle()
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
                    ChipButton(label: catLabel(c), isSelected: selectedCategory == c, size: .small) {
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
                .font(.appCaption.weight(.medium))
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        if debouncedSearch.isEmpty {
            EmptyStateView(icon: "books.vertical.fill", title: "Catalogue vide", compact: true)
                .padding(.top, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 14) {
                EmptyStateView(icon: "magnifyingglass", title: "Aucun exercice pour « \(debouncedSearch) »", compact: true)
                Button {
                    prefillName = debouncedSearch
                    showAdd = true
                } label: {
                    Text("Créer « \(debouncedSearch) »")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(Color.forge)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.forge.opacity(0.12))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.forge.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var itemList: some View {
        List {
            ForEach(filtered, id: \.name) { item in
                CatalogueRow(item: item, isInProgram: inProgram.contains(item.name))
                    .listRowBackground(Color.appCard)
                    .listRowSeparatorTint(Color.white.opacity(0.07))
                    .contentShape(Rectangle())
                    .onTapGesture { detailTarget = item }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = item.name
                        } label: {
                            Label("Archiver", systemImage: "archivebox")
                        }
                        Button {
                            editTarget = item
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            addToProgramTarget = item
                        } label: {
                            Label("Programme", systemImage: "plus.circle.fill")
                        }
                        .tint(.green)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: – Network

    private func loadData() async {
        isLoading = true
        guard let url = URL(string: "\(kBaseURL)/api/inventaire_data") else {
            await MainActor.run { isLoading = false }; return
        }
        if let (data, _) = try? await URLSession.authed.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let inv  = json["inventory"] as? [String: [String: Any]] {
            let loaded   = inv.map { InventoryItem(name: $0.key, $0.value) }
            let prog     = Set(json["in_program"] as? [String] ?? [])
            await MainActor.run { items = loaded; inProgram = prog }
        }
        await MainActor.run { isLoading = false }
    }

    private func postSave(_ item: InventoryItem, originalName: String? = nil) async {
        var body: [String: Any] = [
            "name":           item.name,
            "type":           item.type,
            "category":       item.category,
            "pattern":        item.pattern,
            "level":          item.level,
            "bar_weight":     item.barWeight,
            "increment":      item.increment,
            "default_scheme": item.defaultScheme,
            "muscles":        item.muscles,
            "tracking_type":  item.trackingType,
            "rest_seconds":   item.restSeconds as Any,
            "load_profile":   item.loadProfile.isEmpty ? NSNull() : item.loadProfile,
            "tips":           item.notes ?? NSNull(),
        ]
        if let orig = originalName, orig != item.name {
            body["original_name"] = orig
        }
        guard let url = URL(string: "\(kBaseURL)/api/save_exercise") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "inventaire_data")
        CacheService.shared.clear(for: "programme_data")
        CacheService.shared.clear(for: "seance_data")
        await loadData()
    }

    private func deleteItem(_ name: String) async {
        guard let url = URL(string: "\(kBaseURL)/api/delete_exercise") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])
        _ = try? await URLSession.authed.data(for: req)
        await MainActor.run { items.removeAll { $0.name == name } }
        CacheService.shared.clear(for: "inventaire_data")
        CacheService.shared.clear(for: "programme_data")
        CacheService.shared.clear(for: "seance_data")
    }

    // MARK: – Helpers

    private func typeLabel(_ t: String) -> String {
        switch t {
        case "barbell": return "Barre"; case "ez-bar": return "EZ-Bar"
        case "dumbbell": return "Haltère"; case "cable": return "Câble"
        case "cable_double": return "Câble ×2"
        case "machine": return "Machine"; case "bodyweight": return "Corps"
        case "endurance": return "⏱ Endurance"
        default: return "Tous"
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
        case "barbell": return .orange; case "ez-bar": return .yellow
        case "dumbbell": return .blue; case "cable": return .teal
        case "cable_double": return .teal
        case "machine": return .purple; case "bodyweight": return .green
        default: return .gray
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

struct CatalogueRow: View {
    let item: InventoryItem
    var isInProgram: Bool = false
    @State private var showMedia = false

    func loadProfileInfo(_ lp: String) -> (String, Color) {
        switch lp {
        case "compound_heavy":        return ("LOURD", .red)
        case "compound_hypertrophy":  return ("HYPER", .orange)
        case "isolation":             return ("ISO", .yellow)
        default:                      return ("", .gray)
        }
    }

    var typeIcon: String {
        switch item.type {
        case "barbell":      return "chart.bar.fill"
        case "ez-bar":       return "chart.bar.fill"
        case "dumbbell":     return "dumbbell.fill"
        case "cable":        return "link"
        case "cable_double": return "arrow.left.and.right.circle"
        case "bodyweight":   return "figure.walk"
        default:             return "figure.strengthtraining.traditional"
        }
    }

    var typeColor: Color {
        switch item.type {
        case "barbell": return .orange; case "ez-bar": return .yellow
        case "dumbbell": return .blue; case "cable", "cable_double": return .teal
        case "bodyweight": return .green; default: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: typeIcon)
                    .font(.appBody)
                    .foregroundColor(typeColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.white)
                    if isInProgram {
                        Text("⭐")
                            .font(.appCaption)
                    }
                    if item.trackingType == "time" {
                        Text("TEMPS")
                            .font(.appMicro.weight(.bold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                HStack(spacing: 6) {
                    Text(item.type.capitalized)
                        .font(.appCaption).foregroundColor(.gray)
                    if !item.category.isEmpty {
                        Text("·").foregroundColor(.gray.opacity(0.4)).font(.appCaption)
                        Text(item.category.capitalized)
                            .font(.appCaption).foregroundColor(.gray)
                    }
                    if !item.defaultScheme.isEmpty {
                        Text("·").foregroundColor(.gray.opacity(0.4)).font(.appCaption)
                        Text(item.defaultScheme)
                            .font(.appCaption.weight(.medium)).foregroundColor(.orange.opacity(0.8))
                    }
                    if !item.loadProfile.isEmpty {
                        let (lpLabel, lpColor) = loadProfileInfo(item.loadProfile)
                        Text(lpLabel)
                            .font(.appMicro.weight(.bold))
                            .foregroundColor(lpColor)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(lpColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
            Spacer()
            if item.gifUrl != nil {
                Button {
                    showMedia = true
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.appTitle.weight(.regular))
                        .foregroundColor(.orange.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
            Image(systemName: "chevron.right")
                .font(.appCaption)
                .foregroundColor(.gray.opacity(0.4))
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showMedia) {
            ExerciseMediaSheet(exerciseName: item.name, gifUrl: item.gifUrl, muscles: item.muscles, tips: item.gifUrl != nil ? nil : nil)
        }
    }
}

// MARK: - Form Sheet (Add & Edit)

private let kMuscleGroups = [
    "chest", "shoulders", "rear delts", "triceps", "biceps",
    "lats", "traps", "rhomboids", "lower back",
    "abs", "obliques",
    "fessiers", "hamstrings", "quads", "calves",
    "forearms", "rotators", "abductors"
]

private let kPatternOptions: [(String, String)] = [
    ("horizontal_push", "H. Push"), ("vertical_push", "V. Push"),
    ("horizontal_pull", "H. Pull"), ("vertical_pull", "V. Pull"),
    ("squat", "Squat"), ("hinge", "Hinge"),
    ("core", "Core"), ("isolation", "Isolation"), ("mobility", "Mobilité")
]

struct InventoryFormSheet: View {
    let existing: InventoryItem?
    var prefillName: String? = nil
    var existingNames: [String] = []
    let onSave: (InventoryItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name          = ""
    @State private var type          = "machine"
    @State private var category      = ""
    @State private var pattern       = ""
    @State private var level         = ""
    @State private var defaultScheme = "3x8-12"
    @State private var increment     = "5"
    @State private var barWeight     = "0"
    @State private var muscles: Set<String> = []
    @State private var customMuscle  = ""
    @State private var trackingType  = "reps"
    @State private var timeSets      = 3
    @State private var timeDuration  = 30  // seconds
    @State private var restSecs: Int? = nil   // nil = pas de repos configuré
    @State private var loadProfile   = ""     // "" | "compound_heavy" | "compound_hypertrophy" | "isolation"
    @State private var notes         = ""

    let types      = ["barbell", "ez-bar", "dumbbell", "cable", "cable_double", "machine", "bodyweight"]
    let categories = ["", "push", "pull", "legs", "core", "mobility"]
    let levels     = ["", "beginner", "intermediate", "advanced"]
    let schemes    = ["3x5", "4x5-7", "3x8-10", "4x8-10", "3x10-12", "4x12-15", "3x15"]
    let durationOptions = [15, 20, 30, 45, 60, 90, 120]

    private func formatDur(_ s: Int) -> String {
        s >= 60 ? "\(s / 60)min\(s % 60 > 0 ? "\(s % 60)s" : "")" : "\(s)s"
    }
    private var generatedScheme: String { "\(timeSets)x\(formatDur(timeDuration))" }

    private var isEditing: Bool { existing != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool {
        guard !isEditing, !trimmedName.isEmpty else { return false }
        return existingNames.contains { $0.lowercased() == trimmedName.lowercased() }
    }
    private var canSave: Bool { !trimmedName.isEmpty && !isDuplicate }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                Form {
                    // ── Nom ──────────────────────────────────────
                    Section {
                        TextField("Nom de l'exercice", text: $name)
                            .foregroundColor(.white)
                        if isDuplicate {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.appCaption)
                                    .foregroundColor(.yellow)
                                Text("Un exercice avec ce nom existe déjà.")
                                    .font(.appCaption)
                                    .foregroundColor(.yellow)
                            }
                        }
                    } header: {
                        sectionHeader("Nom *")
                    }
                    .listRowBackground(Color.appCard)

                    // ── Type ─────────────────────────────────────
                    Section {
                        typeGrid
                    } header: {
                        sectionHeader("Type d'équipement")
                    }
                    .listRowBackground(Color.appCard)

                    // ── Tracking ──────────────────────────────────
                    Section {
                        Picker("Tracking", selection: $trackingType) {
                            Text("Reps / Poids").tag("reps")
                            Text("Temps").tag("time")
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        sectionHeader("Type de tracking")
                    }
                    .listRowBackground(Color.appCard)

                    // ── Catégorie ─────────────────────────────────
                    Section {
                        catGrid
                    } header: {
                        sectionHeader("Catégorie")
                    }
                    .listRowBackground(Color.appCard)

                    // ── Pattern mouvement ─────────────────────────
                    Section {
                        patternGrid
                    } header: {
                        sectionHeader("Pattern de mouvement")
                    }
                    .listRowBackground(Color.appCard)

                    // ── Muscles ───────────────────────────────────
                    Section {
                        muscleChips
                        customMuscleRow
                    } header: {
                        HStack {
                            sectionHeader("Muscles ciblés")
                            Spacer()
                            if !muscles.isEmpty {
                                Text("\(muscles.count) sélectionné\(muscles.count > 1 ? "s" : "")")
                                    .font(.appCaption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .listRowBackground(Color.appCard)

                    // ── Schéma ────────────────────────────────────
                    if trackingType == "time" {
                        Section {
                            // Sets
                            HStack {
                                Text("Séries").foregroundColor(.gray)
                                Spacer()
                                Stepper("\(timeSets)", value: $timeSets, in: 1...10)
                                    .foregroundColor(.white)
                                    .labelsHidden()
                                Text("\(timeSets)").foregroundColor(.white).frame(width: 20)
                            }
                            // Duration chips
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Durée par série")
                                    .font(.appCaption).foregroundColor(.gray)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(durationOptions, id: \.self) { d in
                                            Button { timeDuration = d } label: {
                                                Text(formatDur(d))
                                                    .font(.appCaption.weight(.medium))
                                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                                    .background(timeDuration == d ? Color.cyan : Color(hex: "191926"))
                                                    .foregroundColor(timeDuration == d ? .black : .white)
                                                    .cornerRadius(16)
                                            }
                                        }
                                    }
                                }
                            }
                            // Preview
                            HStack {
                                Text("Schéma généré").foregroundColor(.gray).font(.appLabel.weight(.regular))
                                Spacer()
                                Text(generatedScheme)
                                    .font(.appLabel.weight(.semibold)).foregroundColor(.cyan)
                            }
                        } header: {
                            sectionHeader("Configuration temps")
                        }
                        .listRowBackground(Color.appCard)
                    } else {
                        Section("Schéma par défaut") {
                            TextField("ex: 4x6-8", text: $defaultScheme)
                                .foregroundColor(.white)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(schemes, id: \.self) { s in
                                        Button { defaultScheme = s } label: {
                                            Text(s)
                                                .font(.appCaption.weight(.medium))
                                                .padding(.horizontal, 10).padding(.vertical, 5)
                                                .background(defaultScheme == s ? Color.orange : Color(hex: "191926"))
                                                .foregroundColor(defaultScheme == s ? .black : .white)
                                                .cornerRadius(16)
                                        }
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.appCard)
                    }

                    // ── Paramètres numériques (reps seulement) ────
                    if trackingType == "reps" {
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
                            if type == "barbell" || type == "ez-bar" {
                                HStack {
                                    Text(type == "ez-bar" ? "Poids barre EZ (lbs)" : "Poids barre (lbs)").foregroundColor(.gray)
                                    Spacer()
                                    TextField(type == "ez-bar" ? "25" : "45", text: $barWeight)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundColor(.white)
                                        .frame(width: 60)
                                }
                            }
                        }
                        .listRowBackground(Color.appCard)
                    }

                    // ── Profil de charge ──────────────────────────
                    Section {
                        loadProfileGrid
                    } header: {
                        sectionHeader("Profil de charge")
                    }
                    .listRowBackground(Color.appCard)

                    // ── Niveau ────────────────────────────────────
                    Section {
                        levelGrid
                    } header: {
                        sectionHeader("Niveau")
                    }
                    .listRowBackground(Color.appCard)

                    // ── Notes personnelles ────────────────────────
                    Section {
                        TextField("Cues techniques, conseils, variantes…", text: $notes, axis: .vertical)
                            .foregroundColor(.white)
                            .lineLimit(3...6)
                    } header: {
                        sectionHeader("Notes personnelles")
                    }
                    .listRowBackground(Color.appCard)

                    // ── Repos ─────────────────────────────────────
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button {
                                    restSecs = nil
                                } label: {
                                    Text("—")
                                        .font(.appLabel.weight(.semibold))
                                        .foregroundColor(restSecs == nil ? .black : .gray)
                                        .padding(.horizontal, 14).padding(.vertical, 7)
                                        .background(restSecs == nil ? Color.orange : Color(hex: "191926"))
                                        .clipShape(Capsule())
                                }
                                ForEach([30, 45, 60, 90, 120, 180], id: \.self) { s in
                                    Button {
                                        restSecs = s
                                    } label: {
                                        Text(formatDur(s))
                                            .font(.appLabel.weight(.semibold))
                                            .foregroundColor(restSecs == s ? .black : .white)
                                            .padding(.horizontal, 14).padding(.vertical, 7)
                                            .background(restSecs == s ? Color.orange : Color(hex: "191926"))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        if let r = restSecs {
                            HStack {
                                Text("Repos configuré").foregroundColor(.gray).font(.appLabel.weight(.regular))
                                Spacer()
                                Text(formatDur(r))
                                    .font(.appLabel.weight(.semibold)).foregroundColor(.orange)
                            }
                        }
                    } header: {
                        sectionHeader("Temps de repos par défaut")
                    }
                    .listRowBackground(Color.appCard)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
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
                        guard canSave else { return }
                        var item = InventoryItem(name: trimmedName, [:])
                        item.type          = type
                        item.category      = category
                        item.pattern       = pattern
                        item.level         = level
                        item.defaultScheme = (trackingType == "time") ? generatedScheme : defaultScheme
                        item.increment     = Double(increment) ?? 5
                        item.barWeight     = Double(barWeight) ?? 0
                        item.muscles       = muscles.sorted()
                        item.trackingType  = trackingType
                        item.restSeconds   = restSecs
                        item.loadProfile   = loadProfile
                        item.notes         = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
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
                pattern       = e.pattern
                level         = e.level
                defaultScheme = e.defaultScheme
                increment     = String(e.increment)
                barWeight     = String(e.barWeight)
                muscles       = Set(e.muscles)
                trackingType  = e.trackingType
                restSecs      = e.restSeconds
                loadProfile   = e.loadProfile
                notes         = e.notes ?? ""
                // Parse existing time scheme (e.g. "3x45s" → sets=3, duration=45)
                if e.trackingType == "time" {
                    let parts = e.defaultScheme.lowercased().split(separator: "x")
                    if parts.count == 2, let s = Int(parts[0]) {
                        timeSets = s
                        let durStr = String(parts[1])
                        if durStr.hasSuffix("min"), let m = Int(durStr.dropLast(3)) {
                            timeDuration = m * 60
                        } else if let sec = Int(durStr.filter { $0.isNumber }) {
                            timeDuration = sec
                        }
                    }
                }
            } else if let pn = prefillName {
                name = pn
            }
        }
    }

    // MARK: – Section grids

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.appCaption.weight(.semibold))
            .foregroundColor(.gray)
            .textCase(nil)
    }

    private var typeGrid: some View {
        let icons: [String: String] = [
            "barbell": "Barre", "ez-bar": "EZ-Bar", "dumbbell": "Haltère",
            "cable": "Câble", "cable_double": "Câble ×2", "machine": "Machine", "bodyweight": "Corps"
        ]
        let colors: [String: Color] = [
            "barbell": .orange, "ez-bar": .yellow, "dumbbell": .blue,
            "cable": .teal, "cable_double": .teal, "machine": .purple, "bodyweight": .green
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(types, id: \.self) { t in
                let sel = type == t
                Button { type = t } label: {
                    VStack(spacing: 4) {
                        Text(icons[t] ?? t.capitalized)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(sel ? .black : (colors[t] ?? .gray))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(sel ? (colors[t] ?? .gray) : (colors[t] ?? .gray).opacity(0.12))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? .clear : (colors[t] ?? .gray).opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var catGrid: some View {
        let labels = ["push": "Push", "pull": "Pull", "legs": "Jambes",
                      "core": "Core", "mobility": "Mobilité"]
        let colors: [String: Color] = ["push": .red, "pull": .blue, "legs": .green,
                                        "core": .orange, "mobility": .purple]
        let opts = ["push", "pull", "legs", "core", "mobility"]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
            ForEach(opts, id: \.self) { c in
                let sel = category == c
                Button { category = (category == c ? "" : c) } label: {
                    Text(labels[c] ?? c.capitalized)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(sel ? .black : (colors[c] ?? .gray))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(sel ? (colors[c] ?? .gray) : (colors[c] ?? .gray).opacity(0.12))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? .clear : (colors[c] ?? .gray).opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var patternGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
            ForEach(kPatternOptions, id: \.0) { key, label in
                let sel = pattern == key
                Button { pattern = (pattern == key ? "" : key) } label: {
                    Text(label)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(sel ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(sel ? Color.orange : Color(hex: "191926"))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? .clear : Color.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var muscleChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
            ForEach(kMuscleGroups, id: \.self) { m in
                let sel = muscles.contains(m)
                Button {
                    if sel { muscles.remove(m) } else { muscles.insert(m) }
                } label: {
                    Text(muscleLabel(m))
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(sel ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(sel ? Color.orange : Color(hex: "191926"))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? .clear : Color.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var customMuscleRow: some View {
        HStack(spacing: 8) {
            TextField("Autre muscle...", text: $customMuscle)
                .foregroundColor(.white)
                .font(.appLabel.weight(.regular))
            Button {
                let m = customMuscle.trimmingCharacters(in: .whitespaces).lowercased()
                guard !m.isEmpty else { return }
                muscles.insert(m)
                customMuscle = ""
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(customMuscle.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .orange)
                    .font(.appTitle.weight(.regular))
            }
            .disabled(customMuscle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var levelGrid: some View {
        let labels = ["beginner": "Débutant", "intermediate": "Intermédiaire", "advanced": "Avancé"]
        let opts = ["beginner", "intermediate", "advanced"]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(opts, id: \.self) { l in
                let sel = level == l
                Button { level = (level == l ? "" : l) } label: {
                    Text(labels[l] ?? l.capitalized)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(sel ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(sel ? Color.orange : Color(hex: "191926"))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? .clear : Color.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var loadProfileGrid: some View {
        let opts: [(String, String, Color)] = [
            ("compound_heavy",        "Composé lourd\n5–8 reps",    .red),
            ("compound_hypertrophy",  "Composé hyper\n8–12 reps",   .orange),
            ("isolation",             "Isolation\n12–15 reps",       .yellow),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(opts, id: \.0) { value, label, color in
                let sel = loadProfile == value
                Button { loadProfile = (loadProfile == value ? "" : value) } label: {
                    Text(label)
                        .font(.appCaption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(sel ? .black : color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(sel ? color : color.opacity(0.12))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? .clear : color.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func muscleLabel(_ m: String) -> String {
        switch m {
        case "chest": return "Pectoraux"; case "shoulders": return "Épaules"
        case "rear delts": return "Post. Épaule"; case "triceps": return "Triceps"
        case "biceps": return "Biceps"; case "lats": return "Dorsaux"
        case "traps": return "Trapèzes"; case "rhomboids": return "Rhomboïdes"
        case "lower back": return "Lombaires"; case "abs": return "Abdos"
        case "obliques": return "Obliques"; case "fessiers": return "Fessiers"
        case "hamstrings": return "Ischio"; case "quads": return "Quadriceps"
        case "calves": return "Mollets"; case "forearms": return "Avant-bras"
        case "rotators": return "Rotateurs"; case "abductors": return "Abducteurs"
        default: return m.capitalized
        }
    }
}

// MARK: - Skeleton

private struct CatalogueSkeletonView: View {
    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { i in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.07))
                            .frame(width: CGFloat([140, 110, 160, 90, 130][i % 5]), height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: CGFloat([80, 60, 100, 70, 90][i % 5]), height: 9)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .opacity(shimmer ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.9).repeatForever().delay(Double(i) * 0.05), value: shimmer)
                Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
            }
            Spacer()
        }
        .onAppear { shimmer = true }
    }
}

// MARK: - Exercise Media Sheet

struct ExerciseMediaSheet: View {
    let exerciseName: String
    let gifUrl: String?
    let muscles: [String]
    let tips: String?

    @Environment(\.dismiss) private var dismiss
    @State private var showAlt = false

    private var altUrl: String? {
        guard let g = gifUrl else { return nil }
        return g.replacingOccurrences(of: "/0.jpg", with: "/1.jpg")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0D0D14").ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Images (start / end position)
                        if let url = gifUrl {
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    imageTab(label: "Départ", active: !showAlt) { showAlt = false }
                                    imageTab(label: "Arrivée", active: showAlt)  { showAlt = true  }
                                }
                                .padding(.bottom, 10)

                                let displayUrl = (showAlt ? altUrl : gifUrl) ?? url
                                AsyncImage(url: URL(string: displayUrl)) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable()
                                            .scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                            .transition(.opacity)
                                    case .failure:
                                        Color(hex: "191926")
                                            .frame(height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                            .overlay(Image(systemName: "photo.slash").foregroundColor(.gray))
                                    default:
                                        Color(hex: "191926")
                                            .frame(height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                            .overlay(ProgressView())
                                    }
                                }
                                .animation(.easeInOut(duration: 0.2), value: showAlt)
                            }
                            .padding(.horizontal, 16)
                        }

                        // Muscles
                        if !muscles.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("MUSCLES")
                                    .font(.appCaption.weight(.black)).tracking(2)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                FlowLayout(spacing: 8) {
                                    ForEach(muscles, id: \.self) { m in
                                        Text(m.capitalized)
                                            .font(.appCaption.weight(.medium))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Color.orange.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Tips
                        if let t = tips, !t.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("COACHING")
                                    .font(.appCaption.weight(.black)).tracking(2)
                                    .foregroundColor(.gray)
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.appCaption)
                                        .foregroundColor(.yellow)
                                    Text(t)
                                        .font(.appLabel.weight(.regular))
                                        .foregroundColor(.white.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(14)
                            .background(Color.yellow.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                        }

                        if gifUrl == nil && muscles.isEmpty {
                            EmptyStateView(icon: "photo.slash", title: "Aucun média disponible pour cet exercice.", compact: true)
                                .padding(.top, 40)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
            .toolbarBackground(Color(hex: "0D0D14"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func imageTab(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.appCaption.weight(.semibold))
                .foregroundColor(active ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(active ? Color.orange.opacity(0.2) : Color.clear)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if active { Rectangle().fill(Color.orange).frame(height: 2) }
        }
    }
}

// MARK: - Flow Layout (muscle chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Exercise Detail View

private struct ExerciseDetail {
    var e1rmCurrent: Double?
    var e1rmBest: Double?
    var lastSession: LastSession?
    var history: [HistoryEntry]
    var trend30d: [TrendPoint]
    var inSessions: [String]

    struct LastSession { var date: String; var weight: Double?; var reps: String }
    struct HistoryEntry {
        var date: String; var weight: Double?; var reps: String
        var sets: [[Double]]; var rpe: Double?; var e1rm: Double?
    }
    struct TrendPoint { var date: String; var e1rm: Double }
}

struct CatalogueExerciseDetailView: View {
    let item: InventoryItem
    let isInProgram: Bool
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onAddToProgram: () -> Void
    let onReload: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detail: ExerciseDetail?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.orange)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            if let d = detail {
                                if d.e1rmCurrent != nil || d.e1rmBest != nil {
                                    statsSection(d)
                                }
                                if !d.trend30d.isEmpty {
                                    trendSection(d.trend30d)
                                }
                                if !d.history.isEmpty {
                                    historySection(d.history)
                                }
                                if !d.inSessions.isEmpty {
                                    programmeSection(d.inSessions)
                                }
                            } else {
                                EmptyStateView(icon: "chart.bar.xaxis", title: "Aucun historique pour cet exercice.", compact: true)
                                    .padding(.top, 40)
                            }
                            actionsSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onEdit() }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(Color.forge)
                    }
                }
            }
        }
        .task { await loadDetail() }
    }

    // MARK: – Sections

    private func statsSection(_ d: ExerciseDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STATS")
                .font(.appCaption.weight(.black)).tracking(2)
                .foregroundColor(.gray)

            HStack(spacing: 12) {
                if let cur = d.e1rmCurrent {
                    statCard(label: "e1RM actuel", value: String(format: "%.1f", cur), unit: "lbs", accent: Color.forge)
                }
                if let best = d.e1rmBest {
                    statCard(label: "Meilleur e1RM", value: String(format: "%.1f", best), unit: "lbs", accent: .yellow)
                }
            }

            if let last = d.lastSession {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                    Text("Dernière séance")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(frenchDate(last.date))
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                    if let w = last.weight {
                        Text("· \(Int(w))lbs × \(last.reps)")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.appCard)
                .cornerRadius(10)
            }
        }
    }

    private func statCard(label: String, value: String, unit: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.appCaption)
                .foregroundColor(.gray)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                Text(unit)
                    .font(.appCaption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    private func trendSection(_ trend: [ExerciseDetail.TrendPoint]) -> some View {
        let vals = trend.map(\.e1rm)
        let minV = (vals.min() ?? 0) * 0.97
        let maxV = (vals.max() ?? 1) * 1.03
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PROGRESSION 30J")
                    .font(.appCaption.weight(.black)).tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                let delta = (vals.last ?? 0) - (vals.first ?? 0)
                if delta != 0 {
                    Text(delta > 0 ? "+\(String(format: "%.1f", delta))lbs" : "\(String(format: "%.1f", delta))lbs")
                        .font(.appCaption.weight(.bold))
                        .foregroundColor(delta > 0 ? .green : .red)
                }
            }
            Chart {
                ForEach(Array(trend.enumerated()), id: \.offset) { i, pt in
                    AreaMark(x: .value("", i), y: .value("", pt.e1rm))
                        .foregroundStyle(LinearGradient(
                            colors: [Color.forge.opacity(0.3), Color.forge.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("", i), y: .value("", pt.e1rm))
                        .foregroundStyle(Color.forge)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    if i == trend.count - 1 {
                        PointMark(x: .value("", i), y: .value("", pt.e1rm))
                            .foregroundStyle(Color.forge)
                            .symbolSize(30)
                    }
                }
            }
            .chartYScale(domain: minV...maxV)
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 72)
            .padding(.horizontal, 4)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(12)
    }

    private func historySection(_ history: [ExerciseDetail.HistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HISTORIQUE")
                .font(.appCaption.weight(.black)).tracking(2)
                .foregroundColor(.gray)
            ForEach(Array(history.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(frenchDateShort(entry.date))
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(width: 56, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 3) {
                        let setsSummary = setsSummaryText(entry)
                        Text(setsSummary)
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(.white)
                        HStack(spacing: 6) {
                            if let e1rm = entry.e1rm {
                                Text("e1RM \(String(format: "%.0f", e1rm))lbs")
                                    .font(.appCaption)
                                    .foregroundColor(Color.forge.opacity(0.8))
                            }
                            if let rpe = entry.rpe {
                                Text("RPE \(String(format: "%.1f", rpe))")
                                    .font(.appCaption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                if history.last?.date != entry.date {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(12)
    }

    private func programmeSection(_ sessions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROGRAMME")
                .font(.appCaption.weight(.black)).tracking(2)
                .foregroundColor(.gray)
            ForEach(sessions, id: \.self) { s in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.appLabel)
                    Text(s)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(12)
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            if !isInProgram {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onAddToProgram() }
                } label: {
                    Label("Ajouter au programme", systemImage: "plus.circle.fill")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green.opacity(0.85))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onArchive() }
            } label: {
                Label("Archiver cet exercice", systemImage: "archivebox")
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: – Network

    private func loadDetail() async {
        guard let url = URL(string: "\(kBaseURL)/api/exercise_detail?name=\(item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            await MainActor.run { isLoading = false }; return
        }
        guard let (data, _) = try? await URLSession.authed.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            await MainActor.run { isLoading = false }; return
        }

        let e1rmCurrent = json["e1rm_current"] as? Double
        let e1rmBest    = json["e1rm_best"]    as? Double

        var lastSession: ExerciseDetail.LastSession? = nil
        if let ls = json["last_session"] as? [String: Any], let d = ls["date"] as? String {
            lastSession = ExerciseDetail.LastSession(
                date: d,
                weight: ls["weight"] as? Double,
                reps: ls["reps"] as? String ?? ""
            )
        }

        let historyRaw = json["history"] as? [[String: Any]] ?? []
        let history: [ExerciseDetail.HistoryEntry] = historyRaw.compactMap { h in
            guard let date = h["date"] as? String else { return nil }
            let rawSets = h["sets"] as? [[Any]] ?? []
            let sets: [[Double]] = rawSets.compactMap { s in
                guard s.count >= 2,
                      let w = (s[0] as? Double) ?? (s[0] as? Int).map(Double.init),
                      let r = (s[1] as? Double) ?? (s[1] as? Int).map(Double.init) else { return nil }
                return [w, r]
            }
            return ExerciseDetail.HistoryEntry(
                date: date,
                weight: h["weight"] as? Double,
                reps: h["reps"] as? String ?? "",
                sets: sets,
                rpe: h["rpe"] as? Double,
                e1rm: h["e1rm"] as? Double
            )
        }

        let trendRaw = json["trend_30d"] as? [[String: Any]] ?? []
        let trend: [ExerciseDetail.TrendPoint] = trendRaw.compactMap { t in
            guard let d = t["date"] as? String, let e = t["e1rm"] as? Double else { return nil }
            return ExerciseDetail.TrendPoint(date: d, e1rm: e)
        }.sorted { $0.date < $1.date }

        let inSessions = json["in_sessions"] as? [String] ?? []

        let built = ExerciseDetail(
            e1rmCurrent: e1rmCurrent, e1rmBest: e1rmBest,
            lastSession: lastSession, history: history,
            trend30d: trend, inSessions: inSessions
        )
        await MainActor.run {
            detail  = (e1rmCurrent != nil || !history.isEmpty || !inSessions.isEmpty) ? built : nil
            isLoading = false
        }
    }

    // MARK: – Helpers

    private func setsSummaryText(_ entry: ExerciseDetail.HistoryEntry) -> String {
        if !entry.sets.isEmpty {
            let grouped = Dictionary(grouping: entry.sets, by: { $0[0] })
            if grouped.count == 1, let w = grouped.keys.first {
                return "\(entry.sets.count) × \(Int(entry.sets[0][1])) reps @ \(Int(w))lbs"
            }
            return entry.sets.map { "\(Int($0[1]))@\(Int($0[0]))" }.joined(separator: " / ")
        }
        if let w = entry.weight {
            return "\(Int(w))lbs × \(entry.reps) reps"
        }
        return "\(entry.reps) reps"
    }

    private func frenchDate(_ iso: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: iso) else { return iso }
        let out = DateFormatter(); out.locale = Locale(identifier: "fr_CA"); out.dateFormat = "d MMMM yyyy"
        return out.string(from: d)
    }

    private func frenchDateShort(_ iso: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: iso) else { return iso }
        let out = DateFormatter(); out.locale = Locale(identifier: "fr_CA"); out.dateFormat = "d MMM"
        return out.string(from: d)
    }
}

// MARK: - Add to Programme Sheet

struct AddExerciseToProgramSheet: View {
    let exercise: InventoryItem
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var seances: [String] = []
    @State private var isLoading = true
    @State private var pendingSeance: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.orange)
                } else if seances.isEmpty {
                    EmptyStateView(icon: "list.bullet.clipboard", title: "Aucune séance dans ton programme", compact: true)
                        .padding(.top, 60)
                } else {
                    List {
                        Section {
                            ForEach(seances, id: \.self) { seance in
                                Button {
                                    guard pendingSeance == nil else { return }
                                    Task { await addTo(seance: seance) }
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "dumbbell.fill")
                                            .font(.appLabel)
                                            .foregroundColor(.gray)
                                            .frame(width: 28)
                                        Text(seance)
                                            .font(.appLabel.weight(.semibold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        if pendingSeance == seance {
                                            ProgressView().tint(.forge).scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(.green)
                                                .font(.appBody)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.appCard)
                                .listRowSeparatorTint(Color.white.opacity(0.07))
                            }
                        } header: {
                            Text("Ajouter à quelle séance ?")
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(.gray)
                                .textCase(nil)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundColor(.gray)
                }
            }
        }
        .task { await loadSeances() }
    }

    private func loadSeances() async {
        guard let url = URL(string: "\(kBaseURL)/api/programme_data") else {
            await MainActor.run { isLoading = false }; return
        }
        if let (data, _) = try? await URLSession.authed.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let prog = json["full_program"] as? [String: Any] {
            let names = prog.keys.sorted()
            await MainActor.run { seances = names; isLoading = false }
        } else {
            await MainActor.run { isLoading = false }
        }
    }

    private func addTo(seance: String) async {
        await MainActor.run { pendingSeance = seance }
        guard let url = URL(string: "\(kBaseURL)/api/programme") else {
            await MainActor.run { pendingSeance = nil }; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let scheme = exercise.defaultScheme.isEmpty ? "3x8-12" : exercise.defaultScheme
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "action": "add", "jour": seance,
            "exercise": exercise.name, "scheme": scheme
        ])
        _ = try? await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "programme_data")
        CacheService.shared.clear(for: "seance_data")
        await MainActor.run {
            pendingSeance = nil
            onAdded()
            dismiss()
        }
    }
}
