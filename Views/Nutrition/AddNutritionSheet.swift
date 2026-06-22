import SwiftUI
import Combine

// MARK: - Add Nutrition Sheet

struct AddNutritionSheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var catalog: [FoodItem] = FoodCatalogStore.load()
    @State private var selected: FoodItem? = nil
    @State private var quantity = ""
    @State private var manualMode = true
    @State private var showCatalog = false
    @State private var isSaving = false
    @State private var searchText = ""
    @State private var showBarcodeScanner = false
    @State private var isLoadingBarcode = false
    @State private var barcodeNote = ""
    @State private var barcodeError: String? = nil
    // N-B4: attempted save feedback
    @State private var didAttemptSave = false
    // N-D5: callback for template log feedback
    var onLogged: ((String) -> Void)? = nil
    // N-D2: confirm discard when leaving manual mode
    @State private var showDiscardManualAlert = false
    @State private var confirmDiscard = false
    @State private var saveError: String? = nil
    @State private var showRecents = false
    @State private var showDictation = false

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
    @State private var dictationActive = false

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

    // C2: payload utilisé pour persister la saisie dans NutritionDraftStore
    fileprivate var draftPayload: NutritionDraftPayload {
        NutritionDraftPayload(
            manualMode: manualMode,
            mealType: mealType,
            manName: manName, manCal: manCal,
            manProt: manProt, manGluc: manGluc, manLip: manLip,
            barcodeNote: barcodeNote,
            selectedName: selected?.name,
            quantity: quantity
        )
    }

    private func restoreDraftIfAny() {
        guard let p = NutritionDraftStore.load() else { return }
        manualMode = p.manualMode
        mealType = p.mealType
        manName = p.manName; manCal = p.manCal
        manProt = p.manProt; manGluc = p.manGluc; manLip = p.manLip
        barcodeNote = p.barcodeNote
        quantity = p.quantity
        if let name = p.selectedName {
            selected = catalog.first(where: { $0.name == name })
        }
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
                            Section(header: HStack {
                                Text("FRÉQUENTS")
                                Spacer()
                                Button {
                                    withAnimation { showRecents.toggle() }
                                } label: {
                                    Image(systemName: showRecents ? "chevron.up" : "chevron.down")
                                        .font(.appCaption)
                                        .foregroundColor(.appTextSecondary)
                                }
                                .buttonStyle(.plain)
                                .textCase(nil)
                            }) {
                                if showRecents {
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
                            }
                            .listRowBackground(Color.appCard)
                        }

                        // ── Chips catalogue ─────────────────────────────
                        Section(header: HStack {
                            Text("CATALOGUE")
                            Spacer()
                            Button { showBarcodeScanner = true } label: {
                                Label("Scanner", systemImage: "barcode.viewfinder")
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(Color.appSuccess)
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
                                .background(Color.appSurfaceInset)
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
                                                .background(isSel ? Color.statusBlue.opacity(0.35) : Color.statusBlue.opacity(0.12))
                                                .foregroundColor(isSel ? .white : Color.statusBlue)
                                                .cornerRadius(20)
                                                .overlay(RoundedRectangle(cornerRadius: 20)
                                                    .stroke(isSel ? Color.statusBlue : Color.statusBlue.opacity(0.25),
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
                                            .foregroundColor(Color.statusBlue.opacity(0.7))
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
                                                    .background(Color.appSurfaceInset)
                                                    .foregroundColor(.appTextSecondary)
                                                    .cornerRadius(20)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Button { quantity = fmtN(item.refQty) } label: {
                                            Text(portionLabel(for: item))
                                                .font(.appCaption)
                                                .padding(.horizontal, 10).padding(.vertical, 5)
                                                .background(Color.appSurfaceInset)
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
                                            MacroPreviewPill(value: m.cal,  label: "kcal",    color: Color.appWarning)
                                            MacroPreviewPill(value: m.prot, label: "g prot",  color: Color.statusBlue)
                                            MacroPreviewPill(value: m.gluc, label: "g carbs", color: Color.statusYellow)
                                            MacroPreviewPill(value: m.lip,  label: "g lip",   color: Color.statusRed)
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
                        if showDictation {
                            Section(header: HStack {
                                Text("DICTÉE")
                                if dictationActive {
                                    Spacer()
                                    Button("Annuler") { dictationActive = false }
                                        .font(.appLabel)
                                        .foregroundColor(.appTextSecondary)
                                        .textCase(nil)
                                }
                            }) {
                                if dictationActive {
                                    FieldDictationView { name, cal, prot, gluc, lip in
                                        if !name.isEmpty { manName = name }
                                        if !cal.isEmpty  { manCal  = cal }
                                        if !prot.isEmpty { manProt = prot }
                                        if !gluc.isEmpty { manGluc = gluc }
                                        if !lip.isEmpty  { manLip  = lip }
                                        dictationActive = false
                                    }
                                } else {
                                    Button { dictationActive = true } label: {
                                        Label("Dicter les macros", systemImage: "mic.circle")
                                            .font(.appLabel)
                                            .foregroundColor(Color.forge)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .listRowBackground(Color.appCard)
                        }

                        Section(header: HStack {
                            Text("ALIMENT")
                            if !barcodeNote.isEmpty {
                                Spacer()
                                Label(barcodeNote, systemImage: "barcode.viewfinder")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.appSuccess.opacity(0.85))
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
                                    .foregroundColor(Color.appDanger)
                                if !manualMode && selected == nil {
                                    Text("Sélectionne un aliment dans le catalogue")
                                        .font(.appLabel)
                                        .foregroundColor(Color.appDanger)
                                } else if !manualMode && (quantity.isEmpty || p(quantity) <= 0) {
                                    Text("Entre une quantité valide (nombre > 0)")
                                        .font(.appLabel)
                                        .foregroundColor(Color.appDanger)
                                } else if manualMode && manName.isEmpty {
                                    Text("Entre le nom de l'aliment")
                                        .font(.appLabel)
                                        .foregroundColor(Color.appDanger)
                                } else if manualMode && manCal.isEmpty {
                                    Text("Entre les calories (kcal)")
                                        .font(.appLabel)
                                        .foregroundColor(Color.appDanger)
                                }
                            }
                        }
                        .listRowBackground(Color.appDanger.opacity(0.08))
                    }

                    // C1: network save error inline (pattern PostSessionEdit) — saisie préservée
                    if let err = saveError {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi.exclamationmark")
                                    .foregroundColor(Color.appDanger)
                                Text(err)
                                    .font(.appLabel)
                                    .foregroundColor(Color.appDanger)
                            }
                        }
                        .listRowBackground(Color.appDanger.opacity(0.08))
                    }

                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)

                if isLoadingBarcode {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(.onAccent).scaleEffect(1.4)
                        Text("Recherche du produit…")
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
                    // C1: label "Réessayer" on saveError (pattern PostSessionEdit)
                    Button(saveError != nil ? "Réessayer" : "Ajouter") {
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
                let remote = await APIService.shared.fetchFoodCatalog()
                if !remote.isEmpty {
                    let builtIn = FoodCatalogStore.builtInItems()
                    let builtInNames = Set(builtIn.map { $0.name })
                    let remoteCustom = remote.filter { !builtInNames.contains($0.name) }
                    catalog = builtIn + remoteCustom
                    FoodCatalogStore.save(catalog)
                }
            }
            // C2: restore draft (saisie survit aux interruptions)
            .onAppear { restoreDraftIfAny() }
            .onChange(of: draftPayload) { _, new in
                if isDirty {
                    NutritionDraftStore.save(payload: new)
                } else {
                    NutritionDraftStore.clear()
                }
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
            Button("Abandonner", role: .destructive) {
                NutritionDraftStore.clear()  // C2: clear sur abandon explicite
                dismiss()
            }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Les valeurs saisies seront perdues.")
        }
        .presentationDetents([.medium, .large])
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
        saveError = nil
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
            NutritionDraftStore.clear()  // C2: clear sur succès
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Nutrition Draft Store (C2: survives app kill, 24h TTL)

fileprivate struct NutritionDraftPayload: Codable, Equatable {
    var manualMode: Bool
    var mealType: String
    var manName: String
    var manCal: String
    var manProt: String
    var manGluc: String
    var manLip: String
    var barcodeNote: String
    var selectedName: String?
    var quantity: String
}

fileprivate struct PersistedNutritionDraft: Codable {
    let timestamp: Date
    let payload: NutritionDraftPayload
}

fileprivate enum NutritionDraftStore {
    private static let key = "nutrition_draft_current"
    private static let ttl: TimeInterval = 86400  // 24h — au-delà, draft zombie ignoré

    static func save(payload: NutritionDraftPayload) {
        let wrap = PersistedNutritionDraft(timestamp: Date(), payload: payload)
        if let data = try? APIService.encoder.encode(wrap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> NutritionDraftPayload? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let wrap = try? APIService.decoder.decode(PersistedNutritionDraft.self, from: data) else {
            return nil
        }
        if Date().timeIntervalSince(wrap.timestamp) > ttl {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return wrap.payload
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
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

// MARK: - Field-by-field dictation controller

final class FieldDictationController: ObservableObject {

    static let silenceDelay: Double = 1.2

    static let fields: [(prompt: String, numeric: Bool)] = [
        ("Dictez le nom de l'aliment",  false),
        ("Dictez les calories (kcal)",   true),
        ("Dictez les protéines (g)",     true),
        ("Dictez les glucides (g)",       true),
        ("Dictez les lipides (g)",        true),
    ]

    @Published var fieldIndex = 0
    @Published var liveText   = ""
    @Published var isDone     = false

    private(set) var values   = Array(repeating: "", count: 5)
    let service               = SpeechDictationService()
    private var silenceWork:  DispatchWorkItem?
    private var bag           = Set<AnyCancellable>()

    func start() {
        fieldIndex = 0; liveText = ""; isDone = false
        values = Array(repeating: "", count: 5)
        bag.removeAll()
        service.$latestTranscription
            .filter { !$0.isEmpty }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in self?.onTranscription(text) }
            .store(in: &bag)
        beginField()
    }

    func stop() {
        silenceWork?.cancel()
        service.stopDictation()
        bag.removeAll()
    }

    func advance() {
        silenceWork?.cancel()
        commitField()
    }

    func redo() {
        silenceWork?.cancel()
        service.stopDictation()
        liveText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.beginField() }
    }

    private func onTranscription(_ text: String) {
        liveText = text
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitField() }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.silenceDelay, execute: work)
    }

    private func beginField() {
        liveText = ""
        service.startDictation(existingText: "")
    }

    private func commitField() {
        silenceWork?.cancel()
        service.stopDictation()
        let raw = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        values[fieldIndex] = Self.fields[fieldIndex].numeric ? extractNumber(raw) : raw
        let next = fieldIndex + 1
        if next < Self.fields.count {
            fieldIndex = next; liveText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.beginField() }
        } else {
            isDone = true
        }
    }

    private func extractNumber(_ text: String) -> String {
        let s = text.replacingOccurrences(of: ",", with: ".")
        guard let r = s.range(of: "[0-9]+(?:\\.[0-9]+)?", options: .regularExpression) else { return "" }
        return String(s[r])
    }
}

// MARK: - Field dictation view

struct FieldDictationView: View {
    var onComplete: (_ name: String, _ cal: String, _ prot: String, _ gluc: String, _ lip: String) -> Void

    @StateObject private var ctrl = FieldDictationController()
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.statusRed)
                    .frame(width: 7, height: 7)
                    .opacity(pulsing ? 0.2 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
                Text(FieldDictationController.fields[ctrl.fieldIndex].prompt)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.appTextPrimary)
            }

            Text(ctrl.liveText.isEmpty ? "…" : ctrl.liveText)
                .font(.caption)
                .foregroundColor(ctrl.liveText.isEmpty ? .appTextSecondary : .appTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            // Toujours visible dès la 1re seconde
            HStack {
                Button("← Refaire") { ctrl.redo() }
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)

                Spacer()

                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(i < ctrl.fieldIndex  ? Color.appSuccess
                                : i == ctrl.fieldIndex ? Color.forge
                                : Color.appTextSecondary.opacity(0.25))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                Button("Suivant →") { ctrl.advance() }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.forge)
            }
        }
        .onAppear  { pulsing = true; ctrl.start() }
        .onDisappear { ctrl.stop() }
        .onChange(of: ctrl.isDone) { done in
            if done { onComplete(ctrl.values[0], ctrl.values[1], ctrl.values[2], ctrl.values[3], ctrl.values[4]) }
        }
    }
}
