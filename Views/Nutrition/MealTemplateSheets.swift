import SwiftUI

// MARK: - Meal Composer Sheet

struct MealComposerSheet: View {
    let onSaved: () async -> Void
    let onLogged: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var catalog: [FoodItem] = []
    @State private var composedSet: [UUID: String] = [:]
    @State private var selectedCategory = "Tout"
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var saveError: String? = nil

    @State private var mealType: String = {
        let h = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
        switch h {
        case 5..<10:  return "matin"
        case 10..<14: return "midi"
        case 14..<20: return "soir"
        default:      return "collation"
        }
    }()

    private let categoryLabels = ["Tout", "Viande", "Fruit", "Légume", "Perso"]

    private var filteredCatalog: [FoodItem] {
        var items = catalog
        if selectedCategory != "Tout" {
            let cat = selectedCategory == "Perso" ? "Autre" : selectedCategory
            items = items.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return items
    }

    private var composedCount: Int {
        composedSet.values.filter { v in
            (Double(v.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
        }.count
    }

    private var totalCal:  Double { composedTotal().0 }
    private var totalProt: Double { composedTotal().1 }
    private var totalGluc: Double { composedTotal().2 }
    private var totalLip:  Double { composedTotal().3 }

    private func composedTotal() -> (Double, Double, Double, Double) {
        composedSet.reduce((0.0, 0.0, 0.0, 0.0)) { acc, pair in
            let g = Double(pair.value.replacingOccurrences(of: ",", with: ".")) ?? 0
            guard let food = catalog.first(where: { $0.id == pair.key }), g > 0 else { return acc }
            let m = food.macros(for: g)
            return (acc.0 + m.cal, acc.1 + m.prot, acc.2 + m.gluc, acc.3 + m.lip)
        }
    }

    private func toggle(_ food: FoodItem) {
        if composedSet[food.id] != nil {
            composedSet.removeValue(forKey: food.id)
        } else {
            composedSet[food.id] = "100"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    mealTypePicker
                    categoryFilter
                    searchBar
                    Divider().background(Color.white.opacity(0.08))
                    foodList
                }
                if composedCount > 0 {
                    ComposerBottomBar(
                        count: composedCount,
                        cal: totalCal, prot: totalProt, gluc: totalGluc, lip: totalLip,
                        isSaving: isSaving, error: saveError,
                        onSave: save
                    )
                }
            }
            .navigationTitle("Composer un repas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundColor(Color.forge)
                }
            }
            .task { catalog = FoodCatalogStore.load() }
        }
    }

    private var mealTypePicker: some View {
        Picker("", selection: $mealType) {
            Text("Matin").tag("matin")
            Text("Midi").tag("midi")
            Text("Soir").tag("soir")
            Text("Collation").tag("collation")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categoryLabels, id: \.self) { cat in
                    let active = selectedCategory == cat
                    Button { selectedCategory = cat } label: {
                        Text(cat)
                            .font(.system(size: 13, weight: active ? .bold : .regular))
                            .foregroundColor(active ? .white : .appTextSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(active ? Color.forge : Color.appCard)
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.appTextMuted)
            TextField("Rechercher un aliment…", text: $searchText)
                .foregroundColor(.appTextPrimary)
        }
        .padding(10)
        .background(Color.appCard)
        .cornerRadius(10)
        .padding(.horizontal, 14).padding(.bottom, 8)
    }

    private var foodList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredCatalog) { food in
                    ComposerItemRow(
                        food: food,
                        isComposed: composedSet[food.id] != nil,
                        grams: Binding(
                            get: { composedSet[food.id] ?? "100" },
                            set: { composedSet[food.id] = $0 }
                        ),
                        onToggle: { toggle(food) }
                    )
                    Divider().background(Color.white.opacity(0.06)).padding(.leading, 48)
                }
            }
            .padding(.bottom, composedCount > 0 ? 120 : 24)
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            var count = 0
            do {
                for (foodId, gramsStr) in composedSet {
                    let g = Double(gramsStr.replacingOccurrences(of: ",", with: ".")) ?? 0
                    guard let food = catalog.first(where: { $0.id == foodId }), g > 0 else { continue }
                    let m = food.macros(for: g)
                    try await APIService.shared.addNutritionEntry(
                        name: food.name, calories: m.cal,
                        proteines: m.prot, glucides: m.gluc, lipides: m.lip,
                        mealType: mealType
                    )
                    RecentFoodsStore.record(name: food.name, quantity: g, unit: food.refUnit)
                    count += 1
                }
            } catch {
                saveError = "Erreur réseau — réessaie"
                return
            }
            triggerNotificationFeedback(.success)
            onLogged?(count)
            await onSaved()
            dismiss()
        }
    }
}

// MARK: - Composer Item Row

private struct ComposerItemRow: View {
    let food: FoodItem
    let isComposed: Bool
    @Binding var grams: String
    let onToggle: () -> Void

    private var gramsValue: Double {
        Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: isComposed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(isComposed ? Color.forge : .appTextMuted)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name)
                            .font(.system(size: 14, weight: isComposed ? .semibold : .regular))
                            .foregroundColor(isComposed ? .appTextPrimary : .appTextSecondary)
                            .lineLimit(1)
                        Text(perHundredLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.appTextMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            if isComposed {
                inlineGramsRow
            }
        }
        .background(isComposed ? Color.forge.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.18), value: isComposed)
    }

    private var perHundredLabel: String {
        "\(Int(food.calories)) kcal · \(fmtV(food.proteines))g P · \(fmtV(food.glucides))g G · \(fmtV(food.lipides))g L  /\(Int(food.refQty))g"
    }

    private var inlineGramsRow: some View {
        let m = food.macros(for: gramsValue)
        let calLabel  = gramsValue > 0 ? "\(Int(m.cal)) kcal" : ""
        let protLabel = gramsValue > 0 ? "\(fmtV(m.prot))g P" : ""
        return HStack(spacing: 10) {
            TextField("g", text: $grams)
                .keyboardType(.decimalPad)
                .frame(width: 72)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.appCard)
                .cornerRadius(8)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.center)
            Text("g")
                .foregroundColor(.appTextSecondary)
                .font(.appLabel)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(calLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.forge)
                Text(protLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.appTextSecondary)
            }
            .opacity(gramsValue > 0 ? 1 : 0)
            Button(action: onToggle) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.appTextMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 54).padding(.trailing, 14).padding(.bottom, 12)
        .background(Color.forge.opacity(0.06))
    }

    private func fmtV(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

// MARK: - Composer Bottom Bar

private struct ComposerBottomBar: View {
    let count: Int
    let cal: Double
    let prot: Double
    let gluc: Double
    let lip: Double
    let isSaving: Bool
    let error: String?
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let error {
                Text(error)
                    .font(.appCaption).foregroundColor(Color.appDanger)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(count) aliment\(count > 1 ? "s" : "")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                    HStack(spacing: 10) {
                        Text("\(Int(cal)) kcal")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                        Text("P \(fmt(prot))g").font(.appCaption).foregroundColor(Color.statusBlue)
                        Text("G \(fmt(gluc))g").font(.appCaption).foregroundColor(Color.forge)
                        Text("L \(fmt(lip))g").font(.appCaption).foregroundColor(Color.statusRed)
                    }
                }
                Spacer()
                Button(action: onSave) {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white).frame(width: 100)
                        } else {
                            Text("Ajouter \(count) entrée\(count > 1 ? "s" : "")")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.forge)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

// MARK: - Meal Template List

struct MealTemplateListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [MealTemplate] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var editTarget: MealTemplate? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.white)
                } else if templates.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "fork.knife.circle")
                            .font(.system(size: 52)).foregroundColor(.appTextMuted)
                        Text("Aucun repas sauvegardé")
                            .foregroundColor(.appTextSecondary)
                        Button("Créer mon premier repas") { showCreate = true }
                            .buttonStyle(.borderedProminent).tint(Color.forge)
                    }
                } else {
                    List {
                        ForEach(templates) { template in
                            Button { editTarget = template } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(template.name)
                                            .foregroundColor(.appTextPrimary).fontWeight(.semibold)
                                        HStack(spacing: 10) {
                                            Text("\(Int(template.totalCalories)) kcal")
                                                .font(.system(size: 12)).foregroundColor(Color.forge)
                                            Text("\(template.items.count) aliment\(template.items.count > 1 ? "s" : "")")
                                                .font(.system(size: 12)).foregroundColor(.appTextSecondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12)).foregroundColor(.appTextSecondary)
                                }
                            }
                            .listRowBackground(Color.appCard)
                        }
                        .onDelete { idxs in
                            let toDelete = idxs.map { templates[$0] }
                            templates.remove(atOffsets: idxs)
                            Task {
                                for t in toDelete {
                                    try? await APIService.shared.deleteMealTemplate(t.id)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Repas sauvegardés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundColor(Color.forge)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus").foregroundColor(Color.forge)
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await reload() } }) {
                MealTemplateEditorSheet(template: nil) { _ in }
            }
            .sheet(item: $editTarget, onDismiss: { Task { await reload() } }) { t in
                MealTemplateEditorSheet(template: t) { _ in }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        templates = await APIService.shared.fetchMealTemplates()
        isLoading = false
    }
}

// MARK: - Meal Template Editor

struct MealTemplateEditorSheet: View {
    let template: MealTemplate?
    var onSaved: (MealTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var items: [MealTemplateItem]
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var showAddItem = false
    @State private var newItemName = ""
    @State private var newItemCal = ""
    @State private var newItemProt = ""
    @State private var newItemGluc = ""
    @State private var newItemLip = ""

    init(template: MealTemplate?, onSaved: @escaping (MealTemplate) -> Void) {
        self.template = template
        self.onSaved  = onSaved
        _name  = State(initialValue: template?.name ?? "")
        _items = State(initialValue: template?.items ?? [])
    }

    private func p(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    private var totalProteines: Double { items.reduce(0) { $0 + $1.proteines } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                Form {
                    Section("NOM") {
                        TextField("Ex: Petit déjeuner protéiné", text: $name)
                            .foregroundColor(.appTextPrimary)
                    }
                    .listRowBackground(Color.appCard)

                    Section(header: HStack {
                        Text("ALIMENTS")
                        Spacer()
                        Button {
                            withAnimation { showAddItem.toggle() }
                        } label: {
                            Image(systemName: showAddItem ? "minus.circle.fill" : "plus.circle.fill")
                                .foregroundColor(Color.forge)
                        }
                        .buttonStyle(.plain)
                        .textCase(nil)
                    }) {
                        if items.isEmpty && !showAddItem {
                            Text("Utilise + pour ajouter un aliment")
                                .font(.caption).foregroundColor(.appTextSecondary)
                        }
                        ForEach($items) { $item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("Nom", text: $item.name)
                                        .foregroundColor(.appTextPrimary)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("\(Int(item.calories)) kcal · \(String(format: "%.0fg", item.proteines)) prot")
                                        .font(.caption).foregroundColor(.appTextSecondary)
                                }
                            }
                        }
                        .onDelete { items.remove(atOffsets: $0) }
                    }
                    .listRowBackground(Color.appCard)

                    if showAddItem {
                        Section("NOUVEL ALIMENT") {
                            TextField("Nom", text: $newItemName).foregroundColor(.appTextPrimary)
                            HStack {
                                TextField("Calories", text: $newItemCal)
                                    .keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                                Text("kcal").foregroundColor(.appTextSecondary).font(.caption)
                            }
                            HStack {
                                TextField("Protéines", text: $newItemProt)
                                    .keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                                Text("g").foregroundColor(.appTextSecondary).font(.caption)
                            }
                            HStack {
                                TextField("Glucides", text: $newItemGluc)
                                    .keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                                Text("g").foregroundColor(.appTextSecondary).font(.caption)
                            }
                            HStack {
                                TextField("Lipides", text: $newItemLip)
                                    .keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                                Text("g").foregroundColor(.appTextSecondary).font(.caption)
                            }
                            Button("Ajouter") {
                                guard !newItemName.isEmpty else { return }
                                withAnimation {
                                    items.append(MealTemplateItem(
                                        name: newItemName, calories: p(newItemCal),
                                        proteines: p(newItemProt), glucides: p(newItemGluc),
                                        lipides: p(newItemLip)
                                    ))
                                    newItemName = ""; newItemCal = ""
                                    newItemProt = ""; newItemGluc = ""; newItemLip = ""
                                    showAddItem = false
                                }
                            }
                            .foregroundColor(Color.forge)
                            .disabled(newItemName.isEmpty)
                        }
                        .listRowBackground(Color.appCard)
                    }

                    if !items.isEmpty {
                        Section {
                            HStack {
                                Text("Total")
                                Spacer()
                                Text("\(Int(totalCalories)) kcal · \(Int(totalProteines))g prot")
                                    .font(.appLabel).foregroundColor(Color.forge)
                            }
                        }
                        .listRowBackground(Color.appCard)
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(template == nil ? "Nouveau repas" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "…" : "Sauvegarder") { save() }
                        .foregroundColor(Color.forge).fontWeight(.semibold)
                        .disabled(name.isEmpty || items.isEmpty || isSaving)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
    }

    private func save() {
        Task {
            isSaving = true
            do {
                if let t = template {
                    try await APIService.shared.updateMealTemplate(id: t.id, name: name, items: items)
                    onSaved(MealTemplate(id: t.id, name: name, items: items))
                } else {
                    let created = try await APIService.shared.createMealTemplate(name: name, items: items)
                    onSaved(created)
                }
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
