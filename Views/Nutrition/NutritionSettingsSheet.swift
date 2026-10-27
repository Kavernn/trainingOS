import SwiftUI

// MARK: - Nutrition Settings Sheet

struct NutritionSettingsSheet: View {
    let settings: NutritionSettings?
    var onSaved: () async -> Void
    var embedsInNavigationStack: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var proteines: String
    @State private var endTime:   Date
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
        _proteines = State(initialValue: fmt(settings?.proteines))
        _endTime   = State(initialValue: {
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

    private var canSave: Bool { Double(proteines) != nil }

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
                Section(
                    header: Text("CIBLE PROTÉINES"),
                    footer: Text("La cible calorique est adaptative (moyenne glissante TDEE) — plus de saisie manuelle. Glucides/lipides ne sont plus suivis.")
                        .font(.appMicro).foregroundColor(.appTextSecondary)
                ) {
                    HStack {
                        TextField("180", text: $proteines).keyboardType(.numberPad).foregroundColor(.appTextPrimary)
                        Text("g protéines").foregroundColor(Color.statusBlue).font(.appLabel)
                    }
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
        guard let prot = Double(proteines) else { return }
        isSaving = true
        saveError = nil
        // Legacy calorie_limit préservé via valeur serveur — plus éditable ici
        // (/api/nutrition/tdee rafraîchit les cibles caloriques auto). Les
        // champs glucides/lipides du payload API restent envoyés avec les
        // valeurs serveur existantes tant que le backend n'est pas nettoyé —
        // round-trip inoffensif.
        let dtt = settings?.dayTypeTargets
        let heavyCal    = dtt.map { Int($0.heavy.calories)    } ?? 0
        let moderateCal = dtt.map { Int($0.moderate.calories) } ?? 0
        let lightCal    = dtt.map { Int($0.light.calories)    } ?? 0
        let restCal     = dtt.map { Int($0.rest.calories)     } ?? 0
        let legacyCalorieLimit = settings?.calories ?? 0
        do {
            try await APIService.shared.updateNutritionSettings(
                calories:  legacyCalorieLimit,
                proteines: prot,
                dayTypeTargets: [
                    "light":    ["calories": lightCal],
                    "moderate": ["calories": moderateCal],
                    "heavy":    ["calories": heavyCal],
                    "rest":     ["calories": restCal],
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
