import SwiftUI

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
                            .font(.system(size: 52)).foregroundColor(.gray.opacity(0.5))
                        Text("Aucun repas sauvegardé")
                            .foregroundColor(.gray)
                        Button("Créer mon premier repas") { showCreate = true }
                            .buttonStyle(.borderedProminent).tint(.orange)
                    }
                } else {
                    List {
                        ForEach(templates) { template in
                            Button { editTarget = template } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(template.name)
                                            .foregroundColor(.white).fontWeight(.semibold)
                                        HStack(spacing: 10) {
                                            Text("\(Int(template.totalCalories)) kcal")
                                                .font(.system(size: 12)).foregroundColor(.orange)
                                            Text("\(template.items.count) aliment\(template.items.count > 1 ? "s" : "")")
                                                .font(.system(size: 12)).foregroundColor(.gray)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12)).foregroundColor(.gray)
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
                    Button("Fermer") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus").foregroundColor(.orange)
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
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.appCard)

                    Section(header: HStack {
                        Text("ALIMENTS")
                        Spacer()
                        Button {
                            withAnimation { showAddItem.toggle() }
                        } label: {
                            Image(systemName: showAddItem ? "minus.circle.fill" : "plus.circle.fill")
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .textCase(nil)
                    }) {
                        if items.isEmpty && !showAddItem {
                            Text("Utilise + pour ajouter un aliment")
                                .font(.caption).foregroundColor(.gray)
                        }
                        ForEach($items) { $item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("Nom", text: $item.name)
                                        .foregroundColor(.white)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("\(Int(item.calories)) kcal · \(String(format: "%.0fg", item.proteines)) prot")
                                        .font(.caption).foregroundColor(.gray)
                                }
                            }
                        }
                        .onDelete { items.remove(atOffsets: $0) }
                    }
                    .listRowBackground(Color.appCard)

                    if showAddItem {
                        Section("NOUVEL ALIMENT") {
                            TextField("Nom", text: $newItemName).foregroundColor(.white)
                            HStack {
                                TextField("Calories", text: $newItemCal)
                                    .keyboardType(.decimalPad).foregroundColor(.white)
                                Text("kcal").foregroundColor(.gray).font(.caption)
                            }
                            HStack {
                                TextField("Protéines", text: $newItemProt)
                                    .keyboardType(.decimalPad).foregroundColor(.white)
                                Text("g").foregroundColor(.gray).font(.caption)
                            }
                            HStack {
                                TextField("Glucides", text: $newItemGluc)
                                    .keyboardType(.decimalPad).foregroundColor(.white)
                                Text("g").foregroundColor(.gray).font(.caption)
                            }
                            HStack {
                                TextField("Lipides", text: $newItemLip)
                                    .keyboardType(.decimalPad).foregroundColor(.white)
                                Text("g").foregroundColor(.gray).font(.caption)
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
                            .foregroundColor(.orange)
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
                                    .font(.system(size: 13)).foregroundColor(.orange)
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
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "…" : "Sauvegarder") { save() }
                        .foregroundColor(.orange).fontWeight(.semibold)
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
