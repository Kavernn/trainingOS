import SwiftUI

// MARK: - Add Nutrition Sheet

struct AddNutritionSheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var catalog: [FoodItem] = FoodCatalogStore.load()
    @State private var selected: FoodItem? = nil
    @State private var quantity = ""
    @State private var manualMode = false
    @State private var showCatalog = false
    @State private var isSaving = false
    @State private var searchText = ""
    @State private var showBarcodeScanner = false
    @State private var isLoadingBarcode = false
    @State private var barcodeNote = ""
    @State private var barcodeError: String? = nil
    @State private var templates: [MealTemplate] = []
    @State private var showManageTemplates = false
    @State private var isLoggingTemplate = false
    // N-B4: attempted save feedback
    @State private var didAttemptSave = false
    // N-D5: callback for template log feedback
    var onLogged: ((String) -> Void)? = nil
    // N-D2: confirm discard when leaving manual mode
    @State private var showDiscardManualAlert = false
    @State private var confirmDiscard = false
    @State private var saveError: String? = nil
    // N-D9: template loading state
    @State private var isLoadingTemplates = true

    private var filteredCatalog: [FoodItem] {
        searchText.isEmpty ? catalog : catalog.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var recentItems: [RecentFoodsStore.Item] {
        RecentFoodsStore.topRecent(catalog: catalog)
    }

    @State private var mealType: String = {
        let h = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
        switch h {
        case 5..<10:  return "matin"
        case 10..<14: return "midi"
        case 14..<20: return "soir"
        default:      return "collation"
        }
    }()

    // Champs mode manuel
    @State private var manName = ""
    @State private var manCal = ""
    @State private var manProt = ""
    @State private var manGluc = ""
    @State private var manLip = ""

    private var lastUsedQty: Double? {
        guard let sel = selected else { return nil }
        return RecentFoodsStore.lastQuantity(for: sel.name)
    }

    private func portionLabel(for item: FoodItem) -> String {
        switch item.refUnit {
        case "portion(s)": return "1 portion"
        case "unité(s)":   return "1 unité"
        default:           return "\(fmtN(item.refQty)) \(item.refUnit)"
        }
    }

    private func p(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private func fmtN(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private var preview: (cal: Double, prot: Double, gluc: Double, lip: Double)? {
        guard let item = selected, let qty = Double(quantity.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let m = item.macros(for: qty)
        return m
    }

    private var canSave: Bool {
        if manualMode { return !manName.isEmpty && !manCal.isEmpty }
        return selected != nil && !quantity.isEmpty && p(quantity) > 0
    }

    private var isDirty: Bool {
        selected != nil ||
        !quantity.isEmpty ||
        (manualMode && (!manName.isEmpty || !manCal.isEmpty))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                Form {
                    Section("REPAS") {
                        Picker("", selection: $mealType) {
                            Text("Matin").tag("matin")
                            Text("Midi").tag("midi")
                            Text("Soir").tag("soir")
                            Text("Collation").tag("collation")
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                    .listRowBackground(Color.appCard)

                    if !manualMode {
                        // ── Récents ──────────────────────────────────────
                        if !recentItems.isEmpty && searchText.isEmpty {
                            Section("FRÉQUENTS") {
                                ForEach(recentItems) { item in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selected = item.food
                                            quantity = fmtN(item.quantity)
                                        }
                                    } label: {
                                        HStack {
                                            Text(item.food.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.appTextPrimary)
                                            Spacer()
                                            Text("\(fmtN(item.quantity)) \(item.food.refUnit)")
                                                .font(.appLabel)
                                                .foregroundColor(.appTextSecondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .listRowBackground(Color.appCard)
                        }

                        // ── Repas sauvegardés ────────────────────────────
                        Section(header: HStack {
                            Text("REPAS SAUVEGARDÉS")
                            Spacer()
                            Button { showManageTemplates = true } label: {
                                Label("Gérer", systemImage: "slider.horizontal.3")
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(Color.forge)
                            }
                            .buttonStyle(.plain)
                            .textCase(nil)
                        }) {
                            if isLoadingTemplates {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(0..<3, id: \.self) { _ in
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.05))
                                                .frame(width: 90, height: 36)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            } else if templates.isEmpty {
                                Button { showManageTemplates = true } label: {
                                    Label("Créer un repas sauvegardé…", systemImage: "fork.knife")
                                        .font(.appLabel)
                                        .foregroundColor(Color.forge.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(templates) { template in
                                            Button { logTemplate(template) } label: {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(template.name)
                                                        .font(.appLabel.weight(.semibold))
                                                    Text("\(Int(template.totalCalories)) kcal")
                                                        .font(.appCaption)
                                                        .opacity(0.75)
                                                }
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(Color.forge.opacity(0.12))
                                                .foregroundColor(Color.forge)
                                                .cornerRadius(12)
                                                .overlay(RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.forge.opacity(0.3), lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                        .listRowBackground(Color.appCard)

                        // ── Chips catalogue ─────────────────────────────
                        Section(header: HStack {
                            Text("CATALOGUE")
                            Spacer()
                            Button { showBarcodeScanner = true } label: {
                                Label("Scanner", systemImage: "barcode.viewfinder")
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .textCase(nil)
                            Button { withAnimation { manualMode = true } } label: {
                                Label("Manuel", systemImage: "pencil")
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(.appTextSecondary)
                            }
                            .buttonStyle(.plain)
                            .textCase(nil)
                            Button {
                                showCatalog = true
                            } label: {
                                Label("Gérer", systemImage: "slider.horizontal.3")
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(Color.forge)
                            }
                            .buttonStyle(.plain)
                            .textCase(nil)
                        }) {
                            TextField("Rechercher…", text: $searchText)
                                .font(.system(size: 14))
                                .foregroundColor(.appTextPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                                .listRowBackground(Color.appCard)

                            // N-B3: empty search state
                            if !searchText.isEmpty && filteredCatalog.isEmpty {
                                VStack(spacing: 10) {
                                    Text("Aucun résultat pour \"\(searchText)\"")
                                        .font(.appLabel)
                                        .foregroundColor(.appTextSecondary)
                                    Button("Saisir manuellement") {
                                        withAnimation { manualMode = true }
                                    }
                                    .font(.appLabel.weight(.semibold))
                                    .foregroundColor(Color.forge)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .listRowBackground(Color.appCard)
                            } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(filteredCatalog) { item in
                                        let isSel = selected?.id == item.id
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selected = item
                                                quantity = ""
                                            }
                                        } label: {
                                            Text(item.name)
                                                .font(.appLabel)
                                                .padding(.horizontal, 12).padding(.vertical, 7)
                                                .background(isSel ? Color.blue.opacity(0.35) : Color.blue.opacity(0.12))
                                                .foregroundColor(isSel ? .white : .blue)
                                                .cornerRadius(20)
                                                .overlay(RoundedRectangle(cornerRadius: 20)
                                                    .stroke(isSel ? Color.blue : Color.blue.opacity(0.25),
                                                            lineWidth: isSel ? 1.5 : 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            } // end N-B3

                            // ── Quantité inline (apparaît dès la sélection) ──
                            if let item = selected {
                                VStack(spacing: 8) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "scalemass.fill")
                                            .font(.appLabel)
                                            .foregroundColor(.blue.opacity(0.7))
                                        TextField("Quantité", text: $quantity)
                                            .keyboardType(.decimalPad)
                                            .foregroundColor(.appTextPrimary)
                                            .font(.appBody.weight(.semibold))
                                        Text(item.refUnit)
                                            .foregroundColor(.appTextSecondary)
                                            .font(.system(size: 14))
                                    }
                                    // Presets quantité
                                    HStack(spacing: 6) {
                                        if let last = lastUsedQty {
                                            Button { quantity = fmtN(last) } label: {
                                                Text("Dernière · \(fmtN(last)) \(item.refUnit)")
                                                    .font(.appCaption.weight(.semibold))
                                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                                    .background(Color.forge.opacity(0.15))
                                                    .foregroundColor(Color.forge)
                                                    .cornerRadius(20)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        if item.refUnit == "g", item.refQty != 100 {
                                            Button { quantity = "100" } label: {
                                                Text("100 g")
                                                    .font(.appCaption)
                                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                                    .background(Color.white.opacity(0.06))
                                                    .foregroundColor(.appTextSecondary)
                                                    .cornerRadius(20)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Button { quantity = fmtN(item.refQty) } label: {
                                            Text(portionLabel(for: item))
                                                .font(.appCaption)
                                                .padding(.horizontal, 10).padding(.vertical, 5)
                                                .background(Color.white.opacity(0.06))
                                                .foregroundColor(.appTextSecondary)
                                                .cornerRadius(20)
                                        }
                                        .buttonStyle(.plain)
                                        Spacer()
                                    }
                                    Text("Réf : \(fmtN(item.refQty)) \(item.refUnit) = \(Int(item.calories)) kcal")
                                        .font(.appCaption)
                                        .foregroundColor(.appTextSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let m = preview {
                                        HStack(spacing: 0) {
                                            MacroPreviewPill(value: m.cal,  label: "kcal",    color: .orange)
                                            MacroPreviewPill(value: m.prot, label: "g prot",  color: .blue)
                                            MacroPreviewPill(value: m.gluc, label: "g carbs", color: .yellow)
                                            MacroPreviewPill(value: m.lip,  label: "g lip",   color: .pink)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .listRowBackground(Color.appCard)

                    } else {
                        // ── Mode manuel ────────────────────────────────
                        Section(header: HStack {
                            Text("ALIMENT")
                            if !barcodeNote.isEmpty {
                                Spacer()
                                Label(barcodeNote, systemImage: "barcode.viewfinder")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.green.opacity(0.85))
                                    .textCase(nil)
                            }
                        }) {
                            TextField("Nom", text: $manName).foregroundColor(.appTextPrimary)
                            HStack {
                                TextField("Calories (kcal)", text: $manCal).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                                Text("kcal").foregroundColor(.appTextSecondary).font(.appLabel)
                            }
                        }.listRowBackground(Color.appCard)

                        Section("MACROS (g) — optionnel") {
                            TextField("Protéines", text: $manProt).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                            TextField("Glucides",  text: $manGluc).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                            TextField("Lipides",   text: $manLip).keyboardType(.decimalPad).foregroundColor(.appTextPrimary)
                        }.listRowBackground(Color.appCard)

                        Section {
                            // N-D2: confirm discard when manual fields are filled
                            Button {
                                let hasData = !manName.isEmpty || !manCal.isEmpty
                                if hasData {
                                    showDiscardManualAlert = true
                                } else {
                                    withAnimation {
                                        manualMode = false
                                        manName = ""; manCal = ""
                                        barcodeNote = ""
                                    }
                                }
                            } label: {
                                Label("Retour au catalogue", systemImage: "list.bullet")
                                    .font(.appLabel)
                                    .foregroundColor(.appTextSecondary)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("Revenir au catalogue effacera les données saisies.", isPresented: $showDiscardManualAlert, titleVisibility: .visible) {
                                Button("Effacer et revenir", role: .destructive) {
                                    withAnimation {
                                        manualMode = false
                                        manName = ""; manCal = ""
                                        barcodeNote = ""
                                    }
                                }
                                Button("Rester en mode manuel", role: .cancel) {}
                            }
                        }
                        .listRowBackground(Color.appCard)
                    }

                    // N-B4: error message when user taps Ajouter while form invalid
                    if didAttemptSave && !canSave {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                if !manualMode && selected == nil {
                                    Text("Sélectionne un aliment dans le catalogue")
                                        .font(.appLabel)
                                        .foregroundColor(.red)
                                } else if !manualMode && (quantity.isEmpty || p(quantity) <= 0) {
                                    Text("Entre une quantité valide (nombre > 0)")
                                        .font(.appLabel)
                                        .foregroundColor(.red)
                                } else if manualMode && manName.isEmpty {
                                    Text("Entre le nom de l'aliment")
                                        .font(.appLabel)
                                        .foregroundColor(.red)
                                } else if manualMode && manCal.isEmpty {
                                    Text("Entre les calories (kcal)")
                                        .font(.appLabel)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .listRowBackground(Color.red.opacity(0.08))
                    }

                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)

                if isLoadingBarcode || isLoggingTemplate {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text(isLoggingTemplate ? "Enregistrement du repas…" : "Recherche du produit…")
                            .foregroundColor(.appTextPrimary)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            }
            // N-C2: title reflects current mode
            .navigationTitle(manualMode ? "Saisie manuelle" : "Ajouter aliment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }.foregroundColor(Color.forge)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    // N-B4: always-tappable button that validates inline
                    Button("Ajouter") {
                        if canSave {
                            save()
                        } else {
                            didAttemptSave = true
                        }
                    }
                    .foregroundColor(canSave ? Color.forge : .gray)
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showCatalog, onDismiss: {
                catalog = FoodCatalogStore.load()
            }) {
                FoodCatalogView(items: $catalog)
            }
            .task {
                // sequential — async let LIFO crash on iOS 26 beta
                // N-D9: isLoadingTemplates starts true, set false after fetch
                let remote = await APIService.shared.fetchFoodCatalog()
                let tmpl   = await APIService.shared.fetchMealTemplates()
                if !remote.isEmpty {
                    let builtIn = FoodCatalogStore.builtInItems()
                    let builtInNames = Set(builtIn.map { $0.name })
                    let remoteCustom = remote.filter { !builtInNames.contains($0.name) }
                    catalog = builtIn + remoteCustom
                    FoodCatalogStore.save(catalog)
                }
                templates = tmpl
                isLoadingTemplates = false
            }
            .sheet(isPresented: $showManageTemplates, onDismiss: {
                Task { templates = await APIService.shared.fetchMealTemplates() }
            }) {
                MealTemplateListSheet()
            }
            .sheet(isPresented: $showBarcodeScanner) {
                BarcodeScannerSheet { code in
                    handleBarcode(code)
                }
            }
            // N-D3: barcode error with retry and manual entry options
            .alert("Produit introuvable", isPresented: Binding(
                get: { barcodeError != nil },
                set: { if !$0 { barcodeError = nil } }
            ), presenting: barcodeError) { _ in
                Button("Réessayer") {
                    barcodeError = nil
                    showBarcodeScanner = true
                }
                Button("Saisir manuellement") {
                    barcodeError = nil
                    withAnimation { manualMode = true }
                }
                Button("Annuler", role: .cancel) { barcodeError = nil }
            } message: { err in
                Text(err)
            }
        }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { dismiss() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Les valeurs saisies seront perdues.")
        }
        .alert("Erreur", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(saveError ?? "") }
        .presentationDetents([.medium, .large])
    }

    private func logTemplate(_ template: MealTemplate) {
        isLoggingTemplate = true
        Task {
            do {
                try await APIService.shared.logMealTemplate(template.id, mealType: mealType)
                // N-D5: notify parent with template name for toast feedback
                onLogged?(template.name)
                await onSaved()
                isLoggingTemplate = false
                dismiss()
            } catch {
                barcodeError = "Erreur lors de l'enregistrement du repas — réessaie"
                isLoggingTemplate = false
            }
        }
    }

    private func handleBarcode(_ code: String) {
        isLoadingBarcode = true
        barcodeError = nil
        Task {
            do {
                let result = try await APIService.shared.scanBarcode(code)
                let macros = result.perServing ?? result.per100g
                let note: String = {
                    if result.perServing != nil, let sz = result.servingSize {
                        return "1 portion (\(sz))"
                    } else if result.perServing != nil {
                        return "1 portion"
                    } else {
                        return "pour 100g"
                    }
                }()
                await MainActor.run {
                    manName = result.nom
                    manCal  = "\(macros.calories)"
                    manProt = "\(macros.proteines)"
                    manGluc = "\(macros.glucides)"
                    manLip  = "\(macros.lipides)"
                    barcodeNote = note
                    withAnimation { manualMode = true }
                    isLoadingBarcode = false
                }
            } catch let e as ScanLabelError {
                await MainActor.run {
                    barcodeError = e.message
                    isLoadingBarcode = false
                }
            } catch {
                await MainActor.run {
                    barcodeError = "Produit introuvable dans la base Open Food Facts"
                    isLoadingBarcode = false
                }
            }
        }
    }

    private func save() {
        Task {
            isSaving = true
            var loggedName = ""
            do {
                if manualMode {
                    guard !manName.isEmpty, let cal = Double(manCal.replacingOccurrences(of: ",", with: ".")) else { isSaving = false; return }
                    try await APIService.shared.addNutritionEntry(
                        name: manName, calories: cal,
                        proteines: p(manProt), glucides: p(manGluc), lipides: p(manLip),
                        mealType: mealType
                    )
                    loggedName = manName
                } else {
                    guard let item = selected, let qty = Double(quantity.replacingOccurrences(of: ",", with: ".")) else { isSaving = false; return }
                    let m = item.macros(for: qty)
                    try await APIService.shared.addNutritionEntry(
                        name: item.name, calories: m.cal,
                        proteines: m.prot, glucides: m.gluc, lipides: m.lip,
                        mealType: mealType
                    )
                    RecentFoodsStore.record(name: item.name, quantity: qty, unit: item.refUnit)
                    loggedName = item.name
                }
            } catch {
                await MainActor.run { isSaving = false; saveError = "Erreur réseau — réessaie" }
                return
            }
            triggerNotificationFeedback(.success)
            onLogged?(loggedName)
            await onSaved()
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Macro Preview Pill (private helper for AddNutritionSheet)

struct MacroPreviewPill: View {
    let value: Double
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value))
                .font(.appBody.weight(.bold))
                .foregroundColor(color)
            Text(label)
                .font(.appMicro.weight(.medium))
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
