import SwiftUI

// MARK: - Nutrition Settings Sheet

struct NutritionSettingsSheet: View {
    let settings: NutritionSettings?
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var proteines:    String
    @State private var lipides:      String
    @State private var heavyCal:     String
    @State private var heavyGluc:    String
    @State private var moderateCal:  String
    @State private var moderateGluc: String
    @State private var lightCal:     String
    @State private var lightGluc:    String
    @State private var restCalT:     String
    @State private var restGluc:     String
    @State private var endTime:      Date
    @State private var isSaving  = false
    @State private var saveError: String? = nil

    init(settings: NutritionSettings?, onSaved: @escaping () async -> Void) {
        self.settings = settings
        self.onSaved  = onSaved
        let fmt: (Double?) -> String = { v in v.map { "\(Int($0))" } ?? "" }
        let dtt = settings?.dayTypeTargets
        _proteines    = State(initialValue: fmt(settings?.proteines))
        _lipides      = State(initialValue: fmt(settings?.lipides))
        _heavyCal     = State(initialValue: dtt.map { "\(Int($0.heavy.calories))" }    ?? "2550")
        _heavyGluc    = State(initialValue: dtt.map { "\(Int($0.heavy.glucides))" }    ?? "270")
        _moderateCal  = State(initialValue: dtt.map { "\(Int($0.moderate.calories))" } ?? "2400")
        _moderateGluc = State(initialValue: dtt.map { "\(Int($0.moderate.glucides))" } ?? "235")
        _lightCal     = State(initialValue: dtt.map { "\(Int($0.light.calories))" }    ?? "2200")
        _lightGluc    = State(initialValue: dtt.map { "\(Int($0.light.glucides))" }    ?? "185")
        _restCalT     = State(initialValue: dtt.map { "\(Int($0.rest.calories))" }     ?? "2100")
        _restGluc     = State(initialValue: dtt.map { "\(Int($0.rest.glucides))" }     ?? "160")
        _endTime      = State(initialValue: {
            guard let t = settings?.nutritionEndTime,
                  let d = NutritionSettingsSheet.hmmFormatter.date(from: t) else {
                return Calendar.current.safeDate(bySettingHour: 21, minute: 0, second: 0, of: Date())
            }
            return d
        }())
    }

    private static let hmmFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private var canSave: Bool {
        [proteines, lipides, heavyCal, heavyGluc, moderateCal, moderateGluc,
         lightCal, lightGluc, restCalT, restGluc].allSatisfy { Double($0) != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                Form {
                    Section(header: Text("MACROS FIXES (TOUS LES JOURS)")) {
                        HStack {
                            TextField("180", text: $proteines).keyboardType(.numberPad).foregroundColor(.appTextPrimary)
                            Text("g protéines").foregroundColor(.blue).font(.appLabel)
                        }
                        HStack {
                            TextField("75", text: $lipides).keyboardType(.numberPad).foregroundColor(.appTextPrimary)
                            Text("g lipides").foregroundColor(.pink).font(.appLabel)
                        }
                    }
                    .listRowBackground(Color.appCard)

                    Section(header: Text("OBJECTIFS PAR TYPE DE JOURNÉE")) {
                        DayTypeRow(icon: "dumbbell.fill",                       color: Color.forge,
                                   label: "Lourd",    calPlaceholder: "2550",   glucPlaceholder: "270",
                                   cal: $heavyCal,    gluc: $heavyGluc)
                        DayTypeRow(icon: "figure.strengthtraining.traditional", color: .yellow,
                                   label: "Modéré",   calPlaceholder: "2400",   glucPlaceholder: "235",
                                   cal: $moderateCal, gluc: $moderateGluc)
                        DayTypeRow(icon: "figure.arms.open",                    color: Color(hex: "00BCD4"),
                                   label: "Léger",    calPlaceholder: "2200",   glucPlaceholder: "185",
                                   cal: $lightCal,    gluc: $lightGluc)
                        DayTypeRow(icon: "moon.fill",                           color: .blue,
                                   label: "Repos",    calPlaceholder: "2100",   glucPlaceholder: "160",
                                   cal: $restCalT,    gluc: $restGluc)
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") { Task { await save() } }
                        .foregroundColor(Color.forge).fontWeight(.semibold)
                        .disabled(!canSave || isSaving)
                }
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

    private func save() async {
        guard let prot = Double(proteines), let lip  = Double(lipides),
              let hCal = Double(heavyCal),    let hGluc = Double(heavyGluc),
              let mCal = Double(moderateCal), let mGluc = Double(moderateGluc),
              let lCal = Double(lightCal),    let lGluc = Double(lightGluc),
              let rCal = Double(restCalT),    let rGluc = Double(restGluc) else { return }
        isSaving = true
        saveError = nil
        do {
            try await APIService.shared.updateNutritionSettings(
                calories:  mCal,
                proteines: prot,
                glucides:  mGluc,
                lipides:   lip,
                dayTypeTargets: [
                    "light":    ["calories": Int(lCal), "glucides": Int(lGluc)],
                    "moderate": ["calories": Int(mCal), "glucides": Int(mGluc)],
                    "heavy":    ["calories": Int(hCal), "glucides": Int(hGluc)],
                    "rest":     ["calories": Int(rCal), "glucides": Int(rGluc)],
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

// MARK: - Day Type Row (settings sheet helper)

private struct DayTypeRow: View {
    let icon:            String
    let color:           Color
    let label:           String
    let calPlaceholder:  String
    let glucPlaceholder: String
    @Binding var cal:    String
    @Binding var gluc:   String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(color)
            HStack(spacing: 8) {
                TextField(calPlaceholder, text: $cal)
                    .keyboardType(.numberPad)
                    .foregroundColor(.appTextPrimary)
                    .frame(width: 60)
                Text("kcal")
                    .foregroundColor(.appTextSecondary)
                    .font(.system(size: 12))
                Spacer()
                TextField(glucPlaceholder, text: $gluc)
                    .keyboardType(.numberPad)
                    .foregroundColor(.appTextPrimary)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                Text("g glucides")
                    .foregroundColor(.yellow)
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 4)
    }
}
