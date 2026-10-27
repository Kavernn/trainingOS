import SwiftUI

// MARK: - Nutrition Settings Sheet

struct NutritionSettingsSheet: View {
    let settings: NutritionSettings?
    var onSaved: () async -> Void
    var embedsInNavigationStack: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var proteines:    String
    @State private var lipides:      String
    @State private var heavyGluc:    String
    @State private var moderateGluc: String
    @State private var lightGluc:    String
    @State private var restGluc:     String
    @State private var endTime:      Date
    @State private var isSaving  = false
    @State private var saveError: String? = nil

    init(
        settings: NutritionSettings?,
        embedsInNavigationStack: Bool = true,
        onSaved: @escaping () async -> Void
    ) {
        self.settings = settings
        self.embedsInNavigationStack = embedsInNavigationStack
        self.onSaved  = onSaved
        let fmt: (Double?) -> String = { v in v.map { "\(Int($0))" } ?? "" }
        let dtt = settings?.dayTypeTargets
        _proteines    = State(initialValue: fmt(settings?.proteines))
        _lipides      = State(initialValue: fmt(settings?.lipides))
        _heavyGluc    = State(initialValue: dtt.map { "\(Int($0.heavy.glucides))" }    ?? "270")
        _moderateGluc = State(initialValue: dtt.map { "\(Int($0.moderate.glucides))" } ?? "235")
        _lightGluc    = State(initialValue: dtt.map { "\(Int($0.light.glucides))" }    ?? "185")
        _restGluc     = State(initialValue: dtt.map { "\(Int($0.rest.glucides))" }     ?? "160")
        _endTime      = State(initialValue: {
            guard let t = settings?.nutritionEndTime,
                  let d = NutritionSettingsSheet.hmmFormatter.date(from: t) else {
                // Calendar.current VOLONTAIRE — l'heure de rappel nutrition suit le device.
                // Ne pas migrer vers Calendar.mtl.
                return Calendar.current.safeDate(bySettingHour: 21, minute: 0, second: 0, of: Date())
            }
            return d
        }())
    }

    private static let hmmFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private var canSave: Bool {
        [proteines, lipides, heavyGluc, moderateGluc, lightGluc, restGluc]
            .allSatisfy { Double($0) != nil }
    }

    var body: some View {
        Group {
            if embedsInNavigationStack {
                NavigationStack { settingsContent }
            } else {
                settingsContent
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Erreur de sauvegarde", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var settingsContent: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            Form {
                Section(header: Text("MACROS FIXES (TOUS LES JOURS)")) {
                    HStack {
                        TextField("180", text: $proteines).keyboardType(.numberPad).foregroundColor(.appTextPrimary)
                        Text("g protéines").foregroundColor(Color.statusBlue).font(.appLabel)
                    }
                    HStack {
                        TextField("75", text: $lipides).keyboardType(.numberPad).foregroundColor(.appTextPrimary)
                        Text("g lipides").foregroundColor(Color.statusRed).font(.appLabel)
                    }
                }
                .listRowBackground(Color.appCard)

                Section(
                    header: Text("GLUCIDES PAR TYPE DE JOURNÉE"),
                    footer: Text("La cible calorique est adaptative (moyenne glissante TDEE) — plus de saisie manuelle.")
                        .font(.appMicro).foregroundColor(.appTextSecondary)
                ) {
                    DayTypeRow(icon: "dumbbell.fill",                       color: Color.forge,
                               label: "Lourd",    glucPlaceholder: "270", gluc: $heavyGluc)
                    DayTypeRow(icon: "figure.strengthtraining.traditional", color: Color.statusYellow,
                               label: "Modéré",   glucPlaceholder: "235", gluc: $moderateGluc)
                    DayTypeRow(icon: "figure.arms.open",                    color: Color.statusCyan,
                               label: "Léger",    glucPlaceholder: "185", gluc: $lightGluc)
                    DayTypeRow(icon: "moon.fill",                           color: Color.statusBlue,
                               label: "Repos",    glucPlaceholder: "160", gluc: $restGluc)
                }
                .listRowBackground(Color.appCard)

                Section(header: Text("FENÊTRE NUTRITIONNELLE")) {
                    DatePicker("Fin de journée", selection: $endTime, displayedComponents: .hourAndMinute)
                        .foregroundColor(.appTextPrimary)
                        .tint(Color.forge)
                }
                .listRowBackground(Color.appCard)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Objectifs nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedsInNavigationStack {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Sauvegarder") { Task { await save() } }
                    .foregroundColor(Color.forge).fontWeight(.semibold)
                    .disabled(!canSave || isSaving)
            }
        }
    }

    private func save() async {
        guard let prot = Double(proteines), let lip = Double(lipides),
              let hGluc = Double(heavyGluc),  let mGluc = Double(moderateGluc),
              let lGluc = Double(lightGluc),  let rGluc = Double(restGluc) else { return }
        isSaving = true
        saveError = nil
        // Cibles caloriques stockées (par type de jour + limite globale) :
        // préservées via les valeurs serveur existantes — plus éditables ici
        // (/api/nutrition/tdee les rafraîchit automatiquement depuis le TDEE
        // courant). Compliance consommateur = compute_target_calories, pas ces
        // champs.
        let dtt = settings?.dayTypeTargets
        let heavyCal     = dtt.map { Int($0.heavy.calories)    } ?? 0
        let moderateCal  = dtt.map { Int($0.moderate.calories) } ?? 0
        let lightCal     = dtt.map { Int($0.light.calories)    } ?? 0
        let restCal      = dtt.map { Int($0.rest.calories)     } ?? 0
        let legacyCalorieLimit = settings?.calories ?? 0
        do {
            try await APIService.shared.updateNutritionSettings(
                calories:  legacyCalorieLimit,
                proteines: prot,
                glucides:  mGluc,
                lipides:   lip,
                dayTypeTargets: [
                    "light":    ["calories": lightCal,    "glucides": Int(lGluc)],
                    "moderate": ["calories": moderateCal, "glucides": Int(mGluc)],
                    "heavy":    ["calories": heavyCal,    "glucides": Int(hGluc)],
                    "rest":     ["calories": restCal,     "glucides": Int(rGluc)],
                ],
                nutritionEndTime: NutritionSettingsSheet.hmmFormatter.string(from: endTime)
            )
            await onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

struct NutritionSettingsDestination: View {
    @State private var settings: NutritionSettings?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                AppLoadingView()
            } else if let loadError {
                VStack(spacing: 16) {
                    Text(loadError)
                        .font(.appBody)
                        .foregroundColor(.appTextSecondary)
                        .multilineTextAlignment(.center)
                    Button("Réessayer") { Task { await loadSettings() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.forge)
                }
                .padding(24)
            } else {
                NutritionSettingsSheet(
                    settings: settings,
                    embedsInNavigationStack: false,
                    onSaved: {}
                )
            }
        }
        .task { await loadSettings() }
    }

    private func loadSettings() async {
        isLoading = true
        loadError = nil
        do {
            settings = try await APIService.shared.fetchNutritionDetail().settings
        } catch {
            loadError = "Impossible de charger les réglages Nutrition."
        }
        isLoading = false
    }
}

// MARK: - Day Type Row (settings sheet helper)

private struct DayTypeRow: View {
    let icon:            String
    let color:           Color
    let label:           String
    let glucPlaceholder: String
    @Binding var gluc:   String

    var body: some View {
        HStack(spacing: 8) {
            Label(label, systemImage: icon)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(color)
            Spacer()
            TextField(glucPlaceholder, text: $gluc)
                .keyboardType(.numberPad)
                .foregroundColor(.appTextPrimary)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
            Text("g glucides")
                .foregroundColor(Color.statusYellow)
                .font(.system(size: 12))
        }
        .padding(.vertical, 4)
    }
}
