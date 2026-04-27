import SwiftUI

private let kBaseURL = "https://training-os-rho.vercel.app"

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
    }
}

// MARK: - View

struct InventaireView: View {
    @State private var items: [InventoryItem] = []
    @State private var inProgram: Set<String> = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedType = "Tous"
    @State private var selectedCategory = "Tous"
    @State private var filterProgram = false
    @State private var editTarget: InventoryItem?
    @State private var showAdd = false
    @State private var errorMsg: String?
    @State private var pendingDelete: String?

    let types      = ["Tous", "barbell", "ez-bar", "dumbbell", "cable", "machine", "bodyweight"]
    let categories = ["Tous", "push", "pull", "legs", "core", "mobility"]

    var filtered: [InventoryItem] {
        items.filter { item in
            (selectedType == "Tous" || item.type == selectedType) &&
            (selectedCategory == "Tous" || item.category == selectedCategory) &&
            (!filterProgram || inProgram.contains(item.name)) &&
            (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText))
        }
        .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                if isLoading {
                    InventaireSkeletonView()
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
        .confirmationDialog(
            inProgram.contains(pendingDelete ?? "")
                ? "Cet exercice est dans ton programme — le supprimer le retirera de toutes tes séances."
                : "Supprimer \(pendingDelete ?? "") de l'inventaire ?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let name = pendingDelete {
                    Task { await deleteItem(name) }
                    pendingDelete = nil
                }
            }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
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
                FilterChip(label: "⭐ En programme", selected: filterProgram, color: .orange) {
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
                InventaireRow(item: item, isInProgram: inProgram.contains(item.name))
                    .listRowBackground(Color(hex: "11111c"))
                    .listRowSeparatorTint(Color.white.opacity(0.07))
                    .contentShape(Rectangle())
                    .onTapGesture { editTarget = item }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = item.name
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
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
        let url = URL(string: "\(kBaseURL)/api/inventaire_data")!
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
    }

    // MARK: – Helpers

    private func typeLabel(_ t: String) -> String {
        switch t {
        case "barbell": return "Barre"; case "ez-bar": return "EZ-Bar"
        case "dumbbell": return "Haltère"; case "cable": return "Câble"
        case "machine": return "Machine"; case "bodyweight": return "Corps"
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

struct InventaireRow: View {
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
        case "barbell":    return "chart.bar.fill"
        case "ez-bar":     return "chart.bar.fill"
        case "dumbbell":   return "dumbbell.fill"
        case "cable":      return "link"
        case "bodyweight": return "figure.walk"
        default:           return "figure.strengthtraining.traditional"
        }
    }

    var typeColor: Color {
        switch item.type {
        case "barbell": return .orange; case "ez-bar": return .yellow
        case "dumbbell": return .blue; case "cable": return .teal
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
                    .font(.system(size: 16))
                    .foregroundColor(typeColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if isInProgram {
                        Text("⭐")
                            .font(.system(size: 10))
                    }
                    if item.trackingType == "time" {
                        Text("TEMPS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
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
                    if !item.loadProfile.isEmpty {
                        let (lpLabel, lpColor) = loadProfileInfo(item.loadProfile)
                        Text(lpLabel)
                            .font(.system(size: 9, weight: .bold))
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
                        .font(.system(size: 20))
                        .foregroundColor(.orange.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
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

    let types      = ["barbell", "ez-bar", "dumbbell", "cable", "machine", "bodyweight"]
    let categories = ["", "push", "pull", "legs", "core", "mobility"]
    let levels     = ["", "beginner", "intermediate", "advanced"]
    let schemes    = ["3x5", "4x5-7", "3x8-10", "4x8-10", "3x10-12", "4x12-15", "3x15"]
    let durationOptions = [15, 20, 30, 45, 60, 90, 120]

    private func formatDur(_ s: Int) -> String {
        s >= 60 ? "\(s / 60)min\(s % 60 > 0 ? "\(s % 60)s" : "")" : "\(s)s"
    }
    private var generatedScheme: String { "\(timeSets)x\(formatDur(timeDuration))" }

    private var isEditing: Bool { existing != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Form {
                    // ── Nom ──────────────────────────────────────
                    Section("Nom") {
                        TextField("Nom de l'exercice", text: $name)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    // ── Type ─────────────────────────────────────
                    Section {
                        typeGrid
                    } header: {
                        sectionHeader("Type d'équipement")
                    }
                    .listRowBackground(Color(hex: "11111c"))

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
                    .listRowBackground(Color(hex: "11111c"))

                    // ── Catégorie ─────────────────────────────────
                    Section {
                        catGrid
                    } header: {
                        sectionHeader("Catégorie")
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    // ── Pattern mouvement ─────────────────────────
                    Section {
                        patternGrid
                    } header: {
                        sectionHeader("Pattern de mouvement")
                    }
                    .listRowBackground(Color(hex: "11111c"))

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
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .listRowBackground(Color(hex: "11111c"))

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
                                    .font(.system(size: 12)).foregroundColor(.gray)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(durationOptions, id: \.self) { d in
                                            Button { timeDuration = d } label: {
                                                Text(formatDur(d))
                                                    .font(.system(size: 12, weight: .medium))
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
                                Text("Schéma généré").foregroundColor(.gray).font(.system(size: 13))
                                Spacer()
                                Text(generatedScheme)
                                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.cyan)
                            }
                        } header: {
                            sectionHeader("Configuration temps")
                        }
                        .listRowBackground(Color(hex: "11111c"))
                    } else {
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
                        .listRowBackground(Color(hex: "11111c"))
                    }

                    // ── Profil de charge ──────────────────────────
                    Section {
                        loadProfileGrid
                    } header: {
                        sectionHeader("Profil de charge")
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    // ── Niveau ────────────────────────────────────
                    Section {
                        levelGrid
                    } header: {
                        sectionHeader("Niveau")
                    }
                    .listRowBackground(Color(hex: "11111c"))

                    // ── Repos ─────────────────────────────────────
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button {
                                    restSecs = nil
                                } label: {
                                    Text("—")
                                        .font(.system(size: 13, weight: .semibold))
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
                                            .font(.system(size: 13, weight: .semibold))
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
                                Text("Repos configuré").foregroundColor(.gray).font(.system(size: 13))
                                Spacer()
                                Text(formatDur(r))
                                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.orange)
                            }
                        }
                    } header: {
                        sectionHeader("Temps de repos par défaut")
                    }
                    .listRowBackground(Color(hex: "11111c"))
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
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        var item = InventoryItem(name: trimmed, [:])
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
            }
        }
    }

    // MARK: – Section grids

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.gray)
            .textCase(nil)
    }

    private var typeGrid: some View {
        let icons: [String: String] = [
            "barbell": "Barre", "ez-bar": "EZ-Bar", "dumbbell": "Haltère",
            "cable": "Câble", "machine": "Machine", "bodyweight": "Corps"
        ]
        let colors: [String: Color] = [
            "barbell": .orange, "ez-bar": .yellow, "dumbbell": .blue,
            "cable": .teal, "machine": .purple, "bodyweight": .green
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(types, id: \.self) { t in
                let sel = type == t
                Button { type = t } label: {
                    VStack(spacing: 4) {
                        Text(icons[t] ?? t.capitalized)
                            .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 13))
            Button {
                let m = customMuscle.trimmingCharacters(in: .whitespaces).lowercased()
                guard !m.isEmpty else { return }
                muscles.insert(m)
                customMuscle = ""
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(customMuscle.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .orange)
                    .font(.system(size: 20))
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
                        .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 10, weight: .semibold))
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

private struct InventaireSkeletonView: View {
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
                                    .font(.system(size: 10, weight: .black)).tracking(2)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                FlowLayout(spacing: 8) {
                                    ForEach(muscles, id: \.self) { m in
                                        Text(m.capitalized)
                                            .font(.system(size: 12, weight: .medium))
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
                                    .font(.system(size: 10, weight: .black)).tracking(2)
                                    .foregroundColor(.gray)
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.yellow)
                                    Text(t)
                                        .font(.system(size: 13))
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
                            VStack(spacing: 12) {
                                Image(systemName: "photo.slash").font(.system(size: 36)).foregroundColor(.gray.opacity(0.4))
                                Text("Aucun média disponible pour cet exercice.")
                                    .font(.system(size: 13)).foregroundColor(.gray).multilineTextAlignment(.center)
                            }
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
                .font(.system(size: 12, weight: .semibold))
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
