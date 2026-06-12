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
    var loadProfile: String
    var gifUrl: String?
    var useCount: Int
    var notes: String?
    // classification anatomique + fonctionnelle (migration 063)
    var muscleGroup: String
    var muscleSpecific: String?
    var secondaryMuscles: [String]
    var movementPattern: String
    var weightType: String
    var equipment: [String]
    var alternateName: String?

    init(name: String, _ d: [String: Any]) {
        self.name             = name
        self.type             = d["type"]             as? String ?? "machine"
        self.category         = d["category"]         as? String ?? ""
        self.pattern          = d["pattern"]          as? String ?? ""
        self.level            = d["level"]            as? String ?? ""
        self.barWeight        = d["bar_weight"]       as? Double ?? 0
        self.increment        = d["increment"]        as? Double ?? 5
        self.defaultScheme    = d["default_scheme"]   as? String ?? "3x8-12"
        self.muscles          = d["muscles"]          as? [String] ?? []
        self.trackingType     = d["tracking_type"]    as? String ?? "reps"
        self.restSeconds      = d["rest_seconds"]     as? Int
        self.loadProfile      = d["load_profile"]     as? String ?? ""
        self.gifUrl           = d["gif_url"]          as? String
        self.useCount         = d["use_count"]        as? Int ?? 0
        self.notes            = d["tips"]             as? String
        self.muscleGroup      = d["muscle_group"]     as? String ?? ""
        self.muscleSpecific   = d["muscle_specific"]  as? String
        self.secondaryMuscles = d["secondary_muscles"] as? [String] ?? []
        self.movementPattern  = d["movement_pattern"] as? String ?? ""
        self.weightType       = d["weight_type"]      as? String ?? ""
        self.equipment        = d["equipment"]        as? [String] ?? []
        self.alternateName    = d["alternate_name"]   as? String
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
    @State private var showGaps = false
    @State private var gapsCount = 0
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
            (debouncedSearch.isEmpty || item.name.localizedCaseInsensitiveContains(debouncedSearch) || (item.alternateName?.localizedCaseInsensitiveContains(debouncedSearch) == true))
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
                                .foregroundColor(Color.onAccent)
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
                    HStack(spacing: 14) {
                        NavigationLink(destination: GraveyardView()) {
                            Image(systemName: "archivebox.fill")
                                .font(.appBody.weight(.semibold))
                                .foregroundColor(Color(hex: "8B6AFF"))
                        }
                        if gapsCount > 0 {
                            Button { showGaps = true } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "tag.fill")
                                        .font(.appBody.weight(.semibold))
                                        .foregroundColor(Color.forge)
                                    Text("\(gapsCount)")
                                        .font(.appMicro.weight(.black))
                                        .foregroundColor(.white)
                                        .padding(2)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                        .offset(x: 6, y: -6)
                                }
                            }
                        }
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
            .sheet(isPresented: $showGaps) {
                ClassificationGapsSheet { newCount in
                    gapsCount = newCount
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
                .foregroundColor(.appTextPrimary)
                .tint(Color.forge)
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
                    .listRowSeparatorTint(Color.appSeparator)
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
        await loadGapsCount()
    }

    private func loadGapsCount() async {
        guard let url = URL(string: "\(kBaseURL)/api/exercises/classification_gaps") else { return }
        if let (data, _) = try? await URLSession.authed.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let total = json["total"] as? Int {
            await MainActor.run { gapsCount = total }
        }
    }

    private func postSave(_ item: InventoryItem, originalName: String? = nil) async {
        var body: [String: Any] = [
            "name":              item.name,
            "type":              item.type,
            "category":          item.category,
            "pattern":           item.pattern,
            "level":             item.level,
            "bar_weight":        item.barWeight,
            "increment":         item.increment,
            "default_scheme":    item.defaultScheme,
            "muscles":           item.muscles,
            "tracking_type":     item.trackingType,
            "rest_seconds":      item.restSeconds as Any,
            "load_profile":      item.loadProfile.isEmpty ? NSNull() : item.loadProfile,
            "tips":              item.notes ?? NSNull(),
            "muscle_group":      item.muscleGroup.isEmpty ? NSNull() : item.muscleGroup,
            "muscle_specific":   item.muscleSpecific ?? NSNull(),
            "secondary_muscles": item.secondaryMuscles,
            "movement_pattern":  item.movementPattern.isEmpty ? NSNull() : item.movementPattern,
            "weight_type":       item.weightType.isEmpty ? NSNull() : item.weightType,
            "equipment":         item.equipment,
            "alternate_name":    item.alternateName ?? NSNull(),
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
                        .foregroundColor(.appTextPrimary)
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
                if let alias = item.alternateName, !alias.isEmpty {
                    Text(alias)
                        .font(.appCaption)
                        .foregroundColor(.gray.opacity(0.6))
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
                            .font(.appCaption.weight(.medium)).foregroundColor(Color.forge.opacity(0.8))
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
                        .foregroundColor(Color.forge.opacity(0.75))
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

// ── Taxonomie musculaire ──────────────────────────────────────────────────────

private let kMusclesByGroup: [(group: String, specifics: [String])] = [
    ("Pectoraux", [
        "Pectoral majeur — chef claviculaire", "Pectoral majeur — chef sternal",
        "Pectoral majeur — chef costal", "Pectoral mineur", "Serratus antérieur"
    ]),
    ("Dos", [
        "Grand dorsal", "Trapèze — chef supérieur", "Trapèze — chef moyen",
        "Trapèze — chef inférieur", "Rhomboïdes", "Grand rond",
        "Érecteurs du rachis", "Multifides"
    ]),
    ("Épaules", [
        "Deltoïde antérieur", "Deltoïde médial", "Deltoïde postérieur",
        "Sous-épineux", "Supra-épineux", "Sous-scapulaire", "Petit rond"
    ]),
    ("Biceps+Avant-bras", [
        "Biceps brachial — longue portion", "Biceps brachial — courte portion",
        "Brachial", "Brachioradialis", "Supinateur",
        "Fléchisseurs du poignet", "Extenseurs du poignet"
    ]),
    ("Triceps", [
        "Triceps — longue portion", "Triceps — chef latéral",
        "Triceps — chef médial", "Anconé"
    ]),
    ("Quadriceps", [
        "Vaste latéral", "Vaste médial", "Vaste intermédiaire", "Droit fémoral"
    ]),
    ("Ischio-jambiers", [
        "Biceps fémoral — longue portion", "Biceps fémoral — courte portion",
        "Semi-tendineux", "Semi-membraneux"
    ]),
    ("Fessiers", [
        "Grand fessier", "Moyen fessier", "Petit fessier", "Tenseur du fascia lata"
    ]),
    ("Mollets", [
        "Gastrocnémien — chef médial", "Gastrocnémien — chef latéral",
        "Soléaire", "Tibial antérieur"
    ]),
    ("Core", [
        "Droit de l'abdomen", "Oblique externe", "Oblique interne",
        "Transverse de l'abdomen", "Carré des lombes", "Psoas"
    ]),
    ("Hanches", [
        "Grand adducteur", "Long adducteur", "Court adducteur", "Gracile", "Pectiné"
    ]),
    ("Cou", ["Sterno-cléido-mastoïdien", "Splénius"]),
    ("Autre", [])
]

private let kMovementPatterns: [(String, String)] = [
    ("push_horizontal",    "Poussée horizontale"),
    ("push_vertical",      "Poussée verticale"),
    ("pull_horizontal",    "Tirage horizontal"),
    ("pull_vertical",      "Tirage vertical"),
    ("squat",              "Squat / Quad"),
    ("hinge",              "Charnière / Hanche"),
    ("unilateral_leg",     "Unilatéral jambe"),
    ("press_machine",      "Presse machine"),
    ("isolation_arm",      "Isolation bras"),
    ("isolation_shoulder", "Isolation épaule"),
    ("isolation_leg",      "Isolation jambe"),
    ("core",               "Core / Gainage"),
    ("rotation",           "Rotation"),
    ("carry",              "Carry / Transport"),
    ("cardio",             "Cardio"),
    ("accessory_wrist",    "Accessoire poignet"),
    ("other",              "Autre"),
]

private struct WeightTypeOption {
    let key: String
    let label: String
    let note: String
    let color: Color
}

private let kWeightTypes: [WeightTypeOption] = [
    WeightTypeOption(key: "barbell",      label: "Barre",        note: "Poids par côté + barre",   color: Color.forge),
    WeightTypeOption(key: "dumbbell",     label: "Haltères",     note: "Poids par haltère",         color: .blue),
    WeightTypeOption(key: "cable_single", label: "Câble",        note: "Poids de la pile",          color: .teal),
    WeightTypeOption(key: "cable_double", label: "Câble ×2",     note: "Pile × 2 (bilatéral)",     color: .teal),
    WeightTypeOption(key: "press",        label: "Presse",       note: "Charge totale machine",     color: .purple),
    WeightTypeOption(key: "fixed_weight", label: "Poids fixe",   note: "Pas de reps comptées",      color: .yellow),
    WeightTypeOption(key: "bodyweight",   label: "Corps",        note: "Poids corporel",            color: .green),
    WeightTypeOption(key: "endurance",    label: "Endurance",    note: "Durée en secondes",         color: .cyan),
    WeightTypeOption(key: "machine",      label: "Machine",      note: "Sélecteur de pile",         color: Color(hex: "8B6AFF")),
]

private let kEquipmentOptions = [
    "Barre", "Haltères", "Machine", "Câble", "Bandes",
    "Poids du corps", "Smith Machine", "TRX", "Autre"
]

// ── Backward compat helpers ───────────────────────────────────────────────────

private func muscleGroupToEnglish(_ g: String) -> String {
    switch g {
    case "Pectoraux":         return "chest"
    case "Dos":               return "back"
    case "Épaules":           return "shoulders"
    case "Biceps+Avant-bras": return "biceps"
    case "Triceps":           return "triceps"
    case "Quadriceps":        return "quads"
    case "Ischio-jambiers":   return "hamstrings"
    case "Fessiers":          return "fessiers"
    case "Mollets":           return "calves"
    case "Core":              return "core"
    case "Hanches":           return "adductors"
    case "Cou":               return "neck"
    default:                  return "other"
    }
}

private func weightTypeToLegacy(_ wt: String) -> String {
    switch wt {
    case "barbell":      return "barbell"
    case "dumbbell":     return "dumbbell"
    case "cable_single": return "cable"
    case "cable_double": return "cable_double"
    case "bodyweight":   return "bodyweight"
    case "endurance":    return "bodyweight"
    case "press":        return "press"
    case "fixed_weight": return "fixed_weight"
    default:             return "machine"
    }
}

private func movementPatternToLegacy(_ mp: String) -> String {
    switch mp {
    case "push_horizontal", "push_vertical":   return "push"
    case "pull_horizontal", "pull_vertical":   return "pull"
    case "squat", "unilateral_leg":            return "squat"
    case "hinge":                              return "hinge"
    case "core", "rotation":                   return "core"
    case "carry":                              return "carry"
    default:                                   return "isolation"
    }
}

private func categoryFromMovementPattern(_ mp: String) -> String {
    switch mp {
    case "push_horizontal", "push_vertical":                   return "push"
    case "pull_horizontal", "pull_vertical":                   return "pull"
    case "squat", "hinge", "unilateral_leg", "press_machine",
         "isolation_leg":                                      return "legs"
    case "core", "rotation":                                   return "core"
    case "cardio":                                             return "mobility"
    default:                                                   return ""
    }
}

// ── Muscles secondaires — sheet ───────────────────────────────────────────────

private struct SecondaryMusclesSheet: View {
    @Binding var selected: Set<String>
    let excludedPrimary: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                List {
                    ForEach(kMusclesByGroup, id: \.group) { entry in
                        if !entry.specifics.isEmpty {
                            Section {
                                ForEach(entry.specifics, id: \.self) { muscle in
                                    let isPrimary = muscle == excludedPrimary
                                    let isSelected = selected.contains(muscle)
                                    let isMaxed = selected.count >= 3 && !isSelected
                                    Button {
                                        guard !isPrimary, !isMaxed else { return }
                                        if isSelected { selected.remove(muscle) } else { selected.insert(muscle) }
                                    } label: {
                                        HStack {
                                            Text(muscle)
                                                .font(.appLabel.weight(.regular))
                                                .foregroundColor(isPrimary || isMaxed ? .gray.opacity(0.4) : .white)
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill").foregroundColor(Color.forge)
                                            } else if isPrimary {
                                                Text("principal").font(.appMicro).foregroundColor(.gray.opacity(0.5))
                                            }
                                        }
                                    }
                                    .disabled(isPrimary || isMaxed)
                                    .listRowBackground(Color.appCard)
                                }
                            } header: {
                                Text(entry.group)
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(.gray)
                                    .textCase(nil)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Muscles secondaires (max 3)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.foregroundColor(Color.forge)
                }
            }
        }
    }
}

// ── Formulaire principal ──────────────────────────────────────────────────────

struct InventoryFormSheet: View {
    let existing: InventoryItem?
    var prefillName: String? = nil
    var existingNames: [String] = []
    let onSave: (InventoryItem) -> Void

    @Environment(\.dismiss) private var dismiss

    // Identité
    @State private var name          = ""
    @State private var alternateName = ""
    // Classification musculaire
    @State private var muscleGroup       = ""
    @State private var muscleSpecific    = ""
    @State private var secondaryMuscles: Set<String> = []
    @State private var showSecondarySheet = false
    // Pattern fonctionnel
    @State private var movementPattern  = ""
    // Calcul du poids
    @State private var weightType       = ""
    @State private var equipmentSet: Set<String> = []
    @State private var barWeight        = "0"
    // Progression
    @State private var trackingType     = "reps"
    @State private var defaultScheme    = "3x8-12"
    @State private var timeSets         = 3
    @State private var timeDuration     = 30
    @State private var increment        = "5"
    // Profil / Niveau / Notes / Repos (legacy)
    @State private var level       = ""
    @State private var loadProfile = ""
    @State private var notes       = ""
    @State private var restSecs: Int? = nil

    let schemes         = ["3x5", "4x5-7", "3x8-10", "4x8-10", "3x10-12", "4x12-15", "3x15"]
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
    private var canSave: Bool { !trimmedName.isEmpty && !isDuplicate && !muscleGroup.isEmpty && !weightType.isEmpty && !movementPattern.isEmpty }

    private var availableSpecifics: [String] {
        kMusclesByGroup.first(where: { $0.group == muscleGroup })?.specifics ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                Form {
                    identitySection
                    muscleSection
                    movementPatternSection
                    weightTypeSection
                    trackingSection
                    progressionSection
                    loadProfileSection
                    levelSection
                    notesSection
                    restSection
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .foregroundColor(.appTextPrimary)
            }
            .navigationTitle(isEditing ? "Modifier" : "Nouvel exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Sauvegarder" : "Créer l'exercice") {
                        guard canSave else { return }
                        saveItem()
                    }
                    .foregroundColor(canSave ? Color.forge : .gray)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear { loadExisting() }
        .sheet(isPresented: $showSecondarySheet) {
            SecondaryMusclesSheet(
                selected: $secondaryMuscles,
                excludedPrimary: muscleSpecific.isEmpty ? nil : muscleSpecific
            )
        }
    }

    // MARK: – Save / Load

    private func saveItem() {
        var item = InventoryItem(name: trimmedName, [:])
        item.muscleGroup      = muscleGroup
        item.muscleSpecific   = muscleSpecific.isEmpty ? nil : muscleSpecific
        item.secondaryMuscles = secondaryMuscles.sorted()
        item.movementPattern  = movementPattern
        item.weightType       = weightType
        item.equipment        = equipmentSet.sorted()
        item.alternateName    = alternateName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : alternateName.trimmingCharacters(in: .whitespaces)
        item.type             = weightTypeToLegacy(weightType)
        item.category         = categoryFromMovementPattern(movementPattern)
        item.pattern          = movementPatternToLegacy(movementPattern)
        item.level            = level
        item.muscles          = muscleGroup.isEmpty ? [] : [muscleGroupToEnglish(muscleGroup)]
        item.defaultScheme    = (trackingType == "time" || weightType == "endurance") ? generatedScheme : defaultScheme
        item.increment        = Double(increment) ?? 5
        item.barWeight        = Double(barWeight) ?? 0
        item.trackingType     = (weightType == "endurance") ? "time" : trackingType
        item.restSeconds      = restSecs
        item.loadProfile      = loadProfile
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes            = n.isEmpty ? nil : n
        onSave(item)
        dismiss()
    }

    private func loadExisting() {
        if let e = existing {
            name             = e.name
            alternateName    = e.alternateName ?? ""
            muscleGroup      = e.muscleGroup.isEmpty ? englishToMuscleGroup(e.muscles.first ?? "") : e.muscleGroup
            muscleSpecific   = e.muscleSpecific ?? ""
            secondaryMuscles = Set(e.secondaryMuscles)
            movementPattern  = e.movementPattern
            weightType       = e.weightType.isEmpty ? legacyTypeToWeightType(e.type, tracking: e.trackingType) : e.weightType
            equipmentSet     = Set(e.equipment)
            barWeight        = String(e.barWeight)
            trackingType     = e.trackingType
            defaultScheme    = e.defaultScheme
            increment        = String(e.increment)
            level            = e.level
            loadProfile      = e.loadProfile
            restSecs         = e.restSeconds
            notes            = e.notes ?? ""
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

    private func legacyTypeToWeightType(_ t: String, tracking: String) -> String {
        if tracking == "time" { return "endurance" }
        switch t {
        case "barbell", "ez-bar": return "barbell"
        case "dumbbell":          return "dumbbell"
        case "cable":             return "cable_single"
        case "cable_double":      return "cable_double"
        case "bodyweight":        return "bodyweight"
        case "press":             return "press"
        case "fixed_weight":      return "fixed_weight"
        default:                  return "machine"
        }
    }

    private func englishToMuscleGroup(_ eng: String) -> String {
        switch eng {
        case "chest":                          return "Pectoraux"
        case "back", "lats", "traps":          return "Dos"
        case "shoulders", "delts", "rear delts": return "Épaules"
        case "biceps", "forearms":             return "Biceps+Avant-bras"
        case "triceps":                        return "Triceps"
        case "quads", "quadriceps":            return "Quadriceps"
        case "hamstrings":                     return "Ischio-jambiers"
        case "fessiers", "glutes":             return "Fessiers"
        case "calves":                         return "Mollets"
        case "core", "abs":                    return "Core"
        case "adductors":                      return "Hanches"
        default:                               return ""
        }
    }

    // MARK: – Section helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.appCaption.weight(.semibold))
            .foregroundColor(.gray)
            .textCase(nil)
    }

    private func requiredBadge(_ missing: Bool) -> some View {
        Group {
            if missing {
                Text("REQUIS")
                    .font(.appMicro.weight(.bold))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
    }

    // MARK: – Sections

    @ViewBuilder
    private var identitySection: some View {
        Section {
            TextField("Nom de l'exercice", text: $name)
                .foregroundColor(.appTextPrimary)
            if isDuplicate {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.appCaption).foregroundColor(.yellow)
                    Text("Un exercice avec ce nom existe déjà.")
                        .font(.appCaption).foregroundColor(.yellow)
                }
            }
            TextField("Nom alternatif (ex: Bench Press)", text: $alternateName)
                .foregroundColor(.white.opacity(0.6))
                .font(.appLabel.weight(.regular))
        } header: {
            sectionHeader("Nom *")
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder
    private var muscleSection: some View {
        Section {
            Picker("Groupe principal *", selection: $muscleGroup) {
                Text("Choisir…").tag("")
                ForEach(kMusclesByGroup, id: \.group) { entry in
                    Text(entry.group).tag(entry.group)
                }
            }
            .pickerStyle(.menu)
            .tint(muscleGroup.isEmpty ? .gray : Color.forge)

            if !availableSpecifics.isEmpty {
                Picker("Muscle spécifique", selection: $muscleSpecific) {
                    Text("Aucun (optionnel)").tag("")
                    ForEach(availableSpecifics, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.forge.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Muscles secondaires")
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.gray)
                    Spacer()
                    if secondaryMuscles.count < 3 {
                        Button {
                            showSecondarySheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("Ajouter").font(.appCaption.weight(.medium))
                            }
                            .foregroundColor(Color.forge)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !secondaryMuscles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(secondaryMuscles.sorted(), id: \.self) { muscle in
                                HStack(spacing: 4) {
                                    Text(muscle)
                                        .font(.appMicro.weight(.medium))
                                        .lineLimit(1)
                                    Button {
                                        secondaryMuscles.remove(muscle)
                                    } label: {
                                        Image(systemName: "xmark").font(.appMicro)
                                    }
                                }
                                .foregroundColor(.appTextPrimary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.forge.opacity(0.2))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.forge.opacity(0.3), lineWidth: 1))
                            }
                        }
                    }
                } else {
                    Text("Optionnel — max 3, ne comptent pas dans les stats")
                        .font(.appMicro).foregroundColor(.gray.opacity(0.55))
                }
            }
        } header: {
            HStack {
                sectionHeader("Classification musculaire")
                Spacer()
                requiredBadge(muscleGroup.isEmpty)
            }
        }
        .listRowBackground(Color.appCard)
        .onChange(of: muscleGroup) { _, _ in
            if !availableSpecifics.contains(muscleSpecific) { muscleSpecific = "" }
        }
    }

    @ViewBuilder
    private var movementPatternSection: some View {
        Section {
            let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(kMovementPatterns, id: \.0) { key, label in
                    let sel = movementPattern == key
                    Button { movementPattern = (movementPattern == key ? "" : key) } label: {
                        Text(label)
                            .font(.appCaption.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(sel ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(sel ? Color.forge : Color.appSurfaceInset)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? .clear : Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } header: {
            HStack(spacing: 4) {
                sectionHeader("Pattern de mouvement")
                Text("·  requis")
                    .font(.appMicro)
                    .foregroundColor(movementPattern.isEmpty ? Color.forge.opacity(0.7) : .gray.opacity(0.5))
                    .textCase(nil)
            }
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder
    private var weightTypeSection: some View {
        Section {
            let cols3 = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols3, spacing: 8) {
                ForEach(kWeightTypes, id: \.key) { opt in
                    let sel = weightType == opt.key
                    Button { weightType = opt.key } label: {
                        VStack(spacing: 3) {
                            Text(opt.label)
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(sel ? .black : opt.color)
                            Text(opt.note)
                                .font(.appMicro)
                                .foregroundColor(sel ? .black.opacity(0.65) : .gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(sel ? opt.color : opt.color.opacity(0.1))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? .clear : opt.color.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            if weightType == "press" {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundColor(.purple)
                    Text("Le poids du sled n'est pas inclus. Logguez la charge totale chargée.")
                        .font(.appCaption).foregroundColor(.gray)
                }
            }
            if weightType == "fixed_weight" {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundColor(.yellow)
                    Text("Logguez uniquement le poids utilisé. Les reps sont optionnelles.")
                        .font(.appCaption).foregroundColor(.gray)
                }
            }
            if weightType == "barbell" {
                HStack {
                    Text("Poids barre (lbs)").foregroundColor(.gray)
                    Spacer()
                    TextField("45", text: $barWeight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.appTextPrimary)
                        .frame(width: 60)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Équipement (optionnel)")
                    .font(.appCaption).foregroundColor(.gray)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(kEquipmentOptions, id: \.self) { eq in
                            let sel = equipmentSet.contains(eq)
                            Button {
                                if sel { equipmentSet.remove(eq) } else { equipmentSet.insert(eq) }
                            } label: {
                                Text(eq)
                                    .font(.appCaption.weight(.medium))
                                    .foregroundColor(sel ? .black : .white)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(sel ? Color.forge : Color.appSurfaceInset)
                                    .cornerRadius(16)
                                    .overlay(Capsule().stroke(sel ? .clear : Color.white.opacity(0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: {
            HStack {
                sectionHeader("Type de poids")
                Spacer()
                requiredBadge(weightType.isEmpty)
            }
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder
    private var trackingSection: some View {
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
    }

    @ViewBuilder
    private var progressionSection: some View {
        if trackingType == "time" || weightType == "endurance" {
            Section {
                HStack {
                    Text("Séries").foregroundColor(.gray)
                    Spacer()
                    Stepper("\(timeSets)", value: $timeSets, in: 1...10).labelsHidden()
                    Text("\(timeSets)").foregroundColor(.appTextPrimary).frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Durée par série").font(.appCaption).foregroundColor(.gray)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(durationOptions, id: \.self) { d in
                                Button { timeDuration = d } label: {
                                    Text(formatDur(d))
                                        .font(.appCaption.weight(.medium))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(timeDuration == d ? Color.cyan : Color.appSurfaceInset)
                                        .foregroundColor(timeDuration == d ? .black : .white)
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }
                }
                HStack {
                    Text("Schéma").foregroundColor(.gray).font(.appLabel.weight(.regular))
                    Spacer()
                    Text(generatedScheme).font(.appLabel.weight(.semibold)).foregroundColor(.cyan)
                }
            } header: {
                sectionHeader("Configuration temps")
            }
            .listRowBackground(Color.appCard)
        } else {
            Section {
                TextField("ex: 4x6-8", text: $defaultScheme).foregroundColor(.appTextPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(schemes, id: \.self) { s in
                            Button { defaultScheme = s } label: {
                                Text(s)
                                    .font(.appCaption.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(defaultScheme == s ? Color.forge : Color.appSurfaceInset)
                                    .foregroundColor(defaultScheme == s ? Color.onAccent : .white)
                                    .cornerRadius(16)
                            }
                        }
                    }
                }
            } header: {
                sectionHeader("Schéma par défaut")
            }
            .listRowBackground(Color.appCard)
        }

        Section {
            HStack {
                Text("Incrément (lbs)").foregroundColor(.gray)
                Spacer()
                TextField("5", text: $increment)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.appTextPrimary)
                    .frame(width: 60)
            }
        } header: {
            sectionHeader("Progression")
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder
    private var loadProfileSection: some View {
        Section {
            let opts: [(String, String, Color)] = [
                ("compound_heavy",       "Composé lourd\n5–8 reps",  .red),
                ("compound_hypertrophy", "Composé hyper\n8–12 reps", Color.forge),
                ("isolation",            "Isolation\n12–15 reps",     .yellow),
            ]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
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
        } header: {
            sectionHeader("Profil de charge")
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder
    private var levelSection: some View {
        Section {
            let levels: [(String, String)] = [
                ("beginner", "Débutant"), ("intermediate", "Intermédiaire"), ("advanced", "Avancé")
            ]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(levels, id: \.0) { key, label in
                    let sel = level == key
                    Button { level = (level == key ? "" : key) } label: {
                        Text(label)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(sel ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(sel ? Color.forge : Color.appSurfaceInset)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? .clear : Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader("Niveau")
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder
    private var notesSection: some View {
        Section {
            TextField("Cues techniques, conseils, variantes…", text: $notes, axis: .vertical)
                .foregroundColor(.appTextPrimary)
                .lineLimit(3...6)
        } header: {
            sectionHeader("Notes personnelles")
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder
    private var restSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { restSecs = nil } label: {
                        Text("—")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(restSecs == nil ? .black : .gray)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(restSecs == nil ? Color.forge : Color.appSurfaceInset)
                            .clipShape(Capsule())
                    }
                    ForEach([30, 45, 60, 90, 120, 180], id: \.self) { s in
                        Button { restSecs = s } label: {
                            Text(formatDur(s))
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(restSecs == s ? .black : .white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(restSecs == s ? Color.forge : Color.appSurfaceInset)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            if let r = restSecs {
                HStack {
                    Text("Repos configuré").foregroundColor(.gray).font(.appLabel.weight(.regular))
                    Spacer()
                    Text(formatDur(r)).font(.appLabel.weight(.semibold)).foregroundColor(Color.forge)
                }
            }
        } header: {
            sectionHeader("Temps de repos par défaut")
        }
        .listRowBackground(Color.appCard)
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
                Divider().background(Color.appSeparatorSubtle).padding(.horizontal, 16)
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
                Color.appBg.ignoresSafeArea()
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
                                        Color.appSurfaceInset
                                            .frame(height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                            .overlay(Image(systemName: "photo.slash").foregroundColor(.gray))
                                    default:
                                        Color.appSurfaceInset
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
                                            .foregroundColor(Color.forge)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Color.forge.opacity(0.1))
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
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
            .toolbarBackground(Color.appBg, for: .navigationBar)
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
                .background(active ? Color.forge.opacity(0.2) : Color.clear)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if active { Rectangle().fill(Color.forge).frame(height: 2) }
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
                    ProgressView().tint(Color.forge)
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
                            .foregroundColor(.appTextPrimary)
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
                    Divider().background(Color.appSeparator)
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
                        .foregroundColor(.appTextPrimary)
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
                    ProgressView().tint(Color.forge)
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
                                            .foregroundColor(.appTextPrimary)
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
                                .listRowSeparatorTint(Color.appSeparator)
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

    private func addTo(seance seanceName: String) async {
        await MainActor.run { pendingSeance = seanceName }
        guard let url = URL(string: "\(kBaseURL)/api/programme") else {
            await MainActor.run { pendingSeance = nil }; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let scheme = exercise.defaultScheme.isEmpty ? "3x8-12" : exercise.defaultScheme
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "action": "add", "jour": seanceName,
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

// MARK: - ClassificationGapsSheet

private struct ClassificationGap: Identifiable, Decodable {
    var id: String { name }
    let name: String
    let currentMuscleGroup:   String?
    let currentMuscleSpecific: String?
    let suggestedMuscleGroup:  String?
    let suggestedMuscleSpecific: String?
    let suggestedMovementPattern: String?

    enum CodingKeys: String, CodingKey {
        case name
        case currentMuscleGroup      = "current_muscle_group"
        case currentMuscleSpecific   = "current_muscle_specific"
        case suggestedMuscleGroup    = "suggested_muscle_group"
        case suggestedMuscleSpecific  = "suggested_muscle_specific"
        case suggestedMovementPattern = "suggested_movement_pattern"
    }
}

struct ClassificationGapsSheet: View {
    let onCountChange: (Int) -> Void

    @State private var gaps: [ClassificationGap] = []
    @State private var isLoading = true
    @State private var appliedNames: Set<String> = []
    @State private var skippedNames: Set<String> = []
    @State private var applyingName: String?
    @Environment(\.dismiss) private var dismiss

    private var visible: [ClassificationGap] {
        gaps.filter { !skippedNames.contains($0.name) && !appliedNames.contains($0.name) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.forge)
                } else if visible.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.green)
                        Text("Tout est classifié")
                            .font(.appTitle)
                            .foregroundColor(.appTextPrimary)
                        Text("Tous les exercices ont un groupe musculaire et un muscle spécifique.")
                            .font(.appBody)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        Section {
                            Text("Ces exercices ont des suggestions basées sur leur nom. Applique-les un à un ou passe.")
                                .font(.appCaption)
                                .foregroundColor(.gray)
                                .listRowBackground(Color.appBg)
                        }
                        ForEach(visible) { gap in
                            gapRow(gap)
                                .listRowBackground(Color.appCard)
                                .listRowSeparatorTint(Color.appSeparator)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("\(visible.count) suggestion\(visible.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.gray)
                }
            }
        }
        .task { await loadGaps() }
    }

    @ViewBuilder
    private func gapRow(_ gap: ClassificationGap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(gap.name)
                .font(.appBody.weight(.semibold))
                .foregroundColor(.appTextPrimary)

            VStack(alignment: .leading, spacing: 3) {
                if let mg = gap.suggestedMuscleGroup ?? gap.currentMuscleGroup {
                    tagLine(icon: "person.crop.circle", label: "Groupe", value: mg, color: .blue)
                }
                if let ms = gap.suggestedMuscleSpecific {
                    tagLine(icon: "target", label: "Spécifique", value: ms, color: .forge)
                }
                if let mp = gap.suggestedMovementPattern {
                    tagLine(icon: "arrow.triangle.2.circlepath", label: "Pattern", value: mp, color: .purple)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await applyGap(gap) }
                } label: {
                    HStack(spacing: 4) {
                        if applyingName == gap.name {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark")
                        }
                        Text("Appliquer")
                    }
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.forge)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(applyingName != nil)

                Button {
                    withAnimation { skippedNames.insert(gap.name) }
                    onCountChange(visible.count - 1)
                } label: {
                    Text("Passer")
                        .font(.appLabel)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(applyingName != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func tagLine(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text("\(label): ")
                .font(.appCaption)
                .foregroundColor(.gray)
            + Text(value)
                .font(.appCaption.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private func loadGaps() async {
        guard let url = URL(string: "\(kBaseURL)/api/exercises/classification_gaps") else {
            await MainActor.run { isLoading = false }; return
        }
        if let (data, _) = try? await URLSession.authed.data(from: url),
           let json = try? JSONDecoder().decode([String: [ClassificationGap]].self, from: data),
           let loaded = json["gaps"] {
            await MainActor.run { gaps = loaded; isLoading = false }
            onCountChange(loaded.count)
        } else {
            await MainActor.run { isLoading = false }
        }
    }

    private func applyGap(_ gap: ClassificationGap) async {
        guard let url = URL(string: "\(kBaseURL)/api/exercises/classify") else { return }
        await MainActor.run { applyingName = gap.name }
        var body: [String: Any] = ["name": gap.name]
        if let v = gap.suggestedMuscleGroup  ?? gap.currentMuscleGroup  { body["muscle_group"]     = v }
        if let v = gap.suggestedMuscleSpecific                           { body["muscle_specific"]  = v }
        if let v = gap.suggestedMovementPattern                          { body["movement_pattern"] = v }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.authed.data(for: req)
        await MainActor.run {
            appliedNames.insert(gap.name)
            applyingName = nil
            onCountChange(visible.count)
        }
    }
}
