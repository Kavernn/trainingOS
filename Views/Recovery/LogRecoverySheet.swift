import SwiftUI

struct LogRecoverySheet: View {
    var prefillEntry: RecoveryEntry? = nil
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hk = HealthKitService.shared

    @State private var selectedDate = Date()
    @State private var sleepHoursStr = ""
    @State private var sleepQuality: Double = 0
    @State private var restingHrStr = ""
    @State private var hrvStr = ""
    @State private var stepsStr = ""
    @State private var activeEnergyStr = ""
    @State private var hrMorningStr = ""
    @State private var hrPostWorkoutStr = ""
    @State private var hrEveningStr = ""
    @State private var soreness: Double = 0
    @State private var fatigue: Double = 0
    @State private var energyPre: Double = 0
    @State private var bedtime = Date()
    @State private var wakeTime = Date()
    @State private var hasBedtime = false
    @State private var hasWakeTime = false
    @State private var notes = ""
    @State private var isSaving = false
    @State private var isLoadingHK = false
    @State private var apiError: String? = nil
    @State private var showFullMode = false
    @AppStorage("recoveryLogPrefersFull") private var prefersFull = false
    @AppStorage("recoveryLogFullUseCount") private var fullUseCount = 0
    @State private var initialSnapshot: RecoverySnapshot? = nil
    @State private var confirmDiscard = false

    private var isEditing: Bool { prefillEntry != nil }

    private var currentSnapshot: RecoverySnapshot {
        RecoverySnapshot(
            selectedDate: selectedDate,
            sleepHoursStr: sleepHoursStr, sleepQuality: sleepQuality,
            restingHrStr: restingHrStr, hrvStr: hrvStr,
            stepsStr: stepsStr, activeEnergyStr: activeEnergyStr,
            hrMorningStr: hrMorningStr, hrPostWorkoutStr: hrPostWorkoutStr,
            hrEveningStr: hrEveningStr,
            soreness: soreness, fatigue: fatigue, energyPre: energyPre,
            hasBedtime: hasBedtime, hasWakeTime: hasWakeTime,
            bedtime: bedtime, wakeTime: wakeTime,
            notes: notes
        )
    }

    private var isDirty: Bool {
        guard let snap = initialSnapshot else { return false }
        return selectedDate      != snap.selectedDate      ||
               sleepHoursStr     != snap.sleepHoursStr     ||
               sleepQuality      != snap.sleepQuality      ||
               restingHrStr      != snap.restingHrStr      ||
               hrvStr            != snap.hrvStr            ||
               stepsStr          != snap.stepsStr          ||
               activeEnergyStr   != snap.activeEnergyStr   ||
               hrMorningStr      != snap.hrMorningStr      ||
               hrPostWorkoutStr  != snap.hrPostWorkoutStr  ||
               hrEveningStr      != snap.hrEveningStr      ||
               soreness          != snap.soreness          ||
               fatigue           != snap.fatigue           ||
               energyPre         != snap.energyPre         ||
               hasBedtime        != snap.hasBedtime        ||
               hasWakeTime       != snap.hasWakeTime       ||
               (hasBedtime  && bedtime  != snap.bedtime)   ||
               (hasWakeTime && wakeTime != snap.wakeTime)  ||
               notes             != snap.notes
    }

    private var dateStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {

                        // Date picker — toujours visible
                        DatePicker("Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(14).background(Color.appCard).cornerRadius(12)

                        // HealthKit auto-fill — toujours visible
                        #if !targetEnvironment(macCatalyst)
                        Button(action: fillFromHealthKit) {
                            HStack(spacing: 8) {
                                if isLoadingHK {
                                    ProgressView().tint(.onAccent).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "heart.text.square.fill")
                                        .font(.appBody)
                                }
                                Text(isLoadingHK ? "Lecture Health..." : "Remplir depuis Apple Santé")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.appTextPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.statusRed.opacity(0.85))
                            .cornerRadius(12)
                        }
                        .disabled(isLoadingHK)
                        .buttonStyle(SpringButtonStyle())
                        #endif

                        if showFullMode {
                            // ── MODE COMPLET ─────────────────────────────

                            // Activité — pas en tête, prioritaire visuellement
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ACTIVITÉ QUOTIDIENNE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                RecoveryField(label: "PAS", placeholder: "8500", text: $stepsStr, keyboardType: .numberPad)
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Sommeil complet + bedtime/wakeTime
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SOMMEIL").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                HStack(spacing: 12) {
                                    RecoveryField(label: "DURÉE (h)", placeholder: "7.5", text: $sleepHoursStr)
                                    RecoveryField(label: "FC REPOS (bpm)", placeholder: "58", text: $restingHrStr)
                                }
                                Divider().background(Color.appSeparator)
                                // Bedtime
                                HStack {
                                    Toggle(isOn: $hasBedtime) {
                                        Text("HEURE COUCHER").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    }
                                    .toggleStyle(.switch)
                                    .tint(.statusBlue)
                                }
                                if hasBedtime {
                                    DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }
                                // Wake time
                                HStack {
                                    Toggle(isOn: $hasWakeTime) {
                                        Text("HEURE RÉVEIL").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    }
                                    .toggleStyle(.switch)
                                    .tint(.statusBlue)
                                }
                                if hasWakeTime {
                                    DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Check-in subjectif — composant partagé (4 sliders 0-10)
                            MorningCheckInBlock(sleepQuality: $sleepQuality,
                                                fatigue: $fatigue,
                                                soreness: $soreness,
                                                energyPre: $energyPre)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // HRV & dépense
                            VStack(alignment: .leading, spacing: 8) {
                                Text("HRV & DÉPENSE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        RecoveryField(label: "HRV (ms)", placeholder: "45", text: $hrvStr)
                                        if let hrv = Double(hrvStr.replacingOccurrences(of: ",", with: ".")),
                                           !hrvStr.isEmpty, (hrv < 20 || hrv > 200) {
                                            Text("Valeur inhabituelle (20–200 ms)")
                                                .font(.appMicro.weight(.semibold))
                                                .foregroundColor(Color.forge)
                                        }
                                    }
                                    Spacer().frame(maxWidth: .infinity)
                                }
                                HStack(spacing: 12) {
                                    RecoveryField(label: "ÉNERGIE ACTIVE (kcal)", placeholder: "350", text: $activeEnergyStr, keyboardType: .numberPad)
                                    Spacer().frame(maxWidth: .infinity)
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Fréquence cardiaque
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "heart.fill").font(.system(size: 10)).foregroundColor(.statusRed)
                                    Text("FRÉQUENCE CARDIAQUE (bpm)").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                }
                                HStack(spacing: 12) {
                                    RecoveryField(label: "MATIN (06-09h)", placeholder: "62", text: $hrMorningStr, keyboardType: .numberPad)
                                    RecoveryField(label: "POST SÉANCE (+30min)", placeholder: "88", text: $hrPostWorkoutStr, keyboardType: .numberPad)
                                }
                                HStack(spacing: 12) {
                                    RecoveryField(label: "SOIR (21-23h)", placeholder: "58", text: $hrEveningStr, keyboardType: .numberPad)
                                    Spacer().frame(maxWidth: .infinity)
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Notes
                            VStack(alignment: .leading, spacing: 6) {
                                Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                TextField("Comment tu te sens...", text: $notes, axis: .vertical)
                                    .lineLimit(3, reservesSpace: true)
                                    .foregroundColor(.appTextPrimary)
                                    .padding(12)
                                    .background(Color.appSurfaceInset)
                                    .cornerRadius(10)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        } else {
                            // ── MODE RAPIDE ───────────────────────────────

                            // Sommeil (durée seule — qualité est dans le check-in)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SOMMEIL").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                RecoveryField(label: "DURÉE (h)", placeholder: "7.5", text: $sleepHoursStr)
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)

                            // Check-in subjectif — composant partagé (4 sliders 0-10)
                            MorningCheckInBlock(sleepQuality: $sleepQuality,
                                                fatigue: $fatigue,
                                                soreness: $soreness,
                                                energyPre: $energyPre)
                        }

                        // Bouton Logger — toujours visible
                        PrimaryButton(title: "Logger", isLoading: isSaving, action: save)

                        // Lien mode complet — seulement en mode rapide
                        if !showFullMode {
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) { showFullMode = true }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 12))
                                    Text("Plus de détails")
                                        .font(.appLabel)
                                }
                                .foregroundColor(Color(white: 0.40))
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(20)
                    .animation(.easeInOut(duration: 0.3), value: showFullMode)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Modifier la récupération" : "Récupération du jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }.foregroundColor(Color.forge)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Les valeurs saisies seront perdues.")
            }
            .onAppear {
                prefill()
                initialSnapshot = currentSnapshot
            }
        }
    }

    private func prefill() {
        if let e = prefillEntry {
            showFullMode = true
            if let h   = e.sleepHours    { sleepHoursStr    = String(format: "%.1f", h) }
            if let q   = e.sleepQuality  { sleepQuality     = q }
            if let hr  = e.restingHr     { restingHrStr     = String(format: "%.0f", hr) }
            if let v   = e.hrv           { hrvStr           = String(format: "%.0f", v) }
            if let s   = e.steps         { stepsStr         = "\(s)" }
            if let ae  = e.activeEnergy  { activeEnergyStr  = String(format: "%.0f", ae) }
            if let hrm = e.hrMorning     { hrMorningStr     = String(format: "%.0f", hrm) }
            if let hrp = e.hrPostWorkout { hrPostWorkoutStr = String(format: "%.0f", hrp) }
            if let hre = e.hrEvening     { hrEveningStr     = String(format: "%.0f", hre) }
            if let so  = e.soreness      { soreness   = so }
            if let fa  = e.fatigue       { fatigue    = fa }
            if let ep  = e.energyPre     { energyPre  = ep }
            notes = e.notes ?? ""
            if let bt = e.bedtime,
               let d = timeFmt.date(from: bt) { bedtime = d; hasBedtime = true }
            if let wt = e.wakeTime,
               let d = timeFmt.date(from: wt) { wakeTime = d; hasWakeTime = true }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            if let d = e.date, let parsed = f.date(from: d) { selectedDate = parsed }
            // HK fallback: fill missing sleep window (manual values already set above take priority)
            if !hasBedtime || !hasWakeTime {
                let date = selectedDate
                Task {
                    let authorized = await hk.requestAuthorization()
                    guard authorized else { return }
                    if let win = await hk.fetchSleepWindow(for: date) {
                        if !hasBedtime { bedtime = win.bedtime; hasBedtime = true }
                        if !hasWakeTime { wakeTime = win.wakeTime; hasWakeTime = true }
                    }
                }
            }
        } else {
            showFullMode = prefersFull
            fillFromHealthKit()
        }
    }

    private func fillFromHealthKit() {
        isLoadingHK = true
        let date = selectedDate
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isLoadingHK = false; return }
            let snap = await hk.fetchRecoverySnapshot(for: date)
            if let s  = snap.sleepHours    { sleepHoursStr    = String(format: "%.1f", s) }
            if let h  = snap.restingHr     { restingHrStr     = String(format: "%.0f", h) }
            if let v  = snap.hrv           { hrvStr           = String(format: "%.0f", v) }
            if let st = snap.steps         { stepsStr         = "\(st)" }
            if let a  = snap.activeEnergy  { activeEnergyStr  = String(format: "%.0f", a) }
            if let m  = snap.hrMorning     { hrMorningStr     = String(format: "%.0f", m) }
            if let pw = snap.hrPostWorkout { hrPostWorkoutStr = String(format: "%.0f", pw) }
            if let e  = snap.hrEvening     { hrEveningStr     = String(format: "%.0f", e) }
            if let win = snap.sleepWindow  { bedtime = win.bedtime; hasBedtime = true
                                             wakeTime = win.wakeTime; hasWakeTime = true }
            isLoadingHK = false
        }
    }

    private func save() {
        isSaving = true
        if showFullMode {
            fullUseCount += 1
            if fullUseCount >= 3 { prefersFull = true }
        }
        Task {
            do {
                try await APIService.shared.logRecovery(
                    sleepHours:    Double(sleepHoursStr.replacingOccurrences(of: ",", with: ".")),
                    sleepQuality:  sleepQuality > 0 ? sleepQuality : nil,
                    restingHr:     Double(restingHrStr),
                    hrv:           Double(hrvStr),
                    steps:         stepsStr.isEmpty ? nil : (Int(stepsStr) ?? Int(Double(stepsStr.replacingOccurrences(of: ",", with: ".")) ?? 0)),
                    soreness:      soreness == 0 ? nil : soreness,
                    fatigue:       fatigue == 0 ? nil : fatigue,
                    energyPre:     energyPre == 0 ? nil : energyPre,
                    activeEnergy:  activeEnergyStr.isEmpty ? nil : Double(activeEnergyStr),
                    hrMorning:     hrMorningStr.isEmpty ? nil : Double(hrMorningStr),
                    hrPostWorkout: hrPostWorkoutStr.isEmpty ? nil : Double(hrPostWorkoutStr),
                    hrEvening:     hrEveningStr.isEmpty ? nil : Double(hrEveningStr),
                    notes:         notes,
                    date:          dateStr,
                    bedtime:       hasBedtime ? timeFmt.string(from: bedtime) : nil,
                    wakeTime:      hasWakeTime ? timeFmt.string(from: wakeTime) : nil
                )
                triggerNotificationFeedback(.success)
                triggerImpact(style: .medium)
                await onSaved()
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                apiError = "Erreur réseau — réessaie"
            }
        }
    }
}

private struct RecoverySnapshot {
    var selectedDate: Date
    var sleepHoursStr: String
    var sleepQuality: Double
    var restingHrStr: String
    var hrvStr: String
    var stepsStr: String
    var activeEnergyStr: String
    var hrMorningStr: String
    var hrPostWorkoutStr: String
    var hrEveningStr: String
    var soreness: Double
    var fatigue: Double
    var energyPre: Double
    var hasBedtime: Bool
    var hasWakeTime: Bool
    var bedtime: Date
    var wakeTime: Date
    var notes: String
}

struct RecoveryField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .decimalPad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .foregroundColor(.appTextPrimary)
                .padding(10)
                .background(Color.appSurfaceInset)
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Morning Check-In Block (4 sliders subjectifs 0-10)
// Source unique partagée par LogRecoverySheet (Santé) et MorningRevealView.
// Convention : 0 = non renseigné → nil envoyé à /api/log_recovery.
struct MorningCheckInBlock: View {
    @Binding var sleepQuality: Double
    @Binding var fatigue: Double
    @Binding var soreness: Double
    @Binding var energyPre: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sliderRow(label: "QUALITÉ SOMMEIL", value: $sleepQuality,
                      color: Color.statusBlue,
                      low: "0 = Non renseigné", high: "10 = Excellent")
            Divider().background(Color.appSeparator)
            sliderRow(label: "FATIGUE PERÇUE", value: $fatigue,
                      color: Self.fatigueColor(fatigue),
                      low: "0 = Non renseigné", high: "10 = Épuisé(e)")
            Divider().background(Color.appSeparator)
            sliderRow(label: "DOULEURS MUSCULAIRES", value: $soreness,
                      color: Self.sorenessColor(soreness),
                      low: "0 = Aucune", high: "10 = Sévère")
            Divider().background(Color.appSeparator)
            sliderRow(label: "ÉNERGIE PERÇUE", value: $energyPre,
                      color: Self.energyPreColor(energyPre),
                      low: "0 = Non renseigné", high: "10 = Excellent")
        }
        .padding(14).background(Color.appCard).cornerRadius(12)
    }

    @ViewBuilder
    private func sliderRow(label: String, value: Binding<Double>, color: Color,
                           low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if value.wrappedValue == 0 {
                    Text("—").font(.appLabel.weight(.bold)).foregroundColor(.gray)
                } else {
                    Text(String(format: "%.0f / 10", value.wrappedValue))
                        .font(.appLabel.weight(.bold)).foregroundColor(color)
                }
            }
            Slider(value: value, in: 0...10, step: 1)
                .tint(value.wrappedValue == 0 ? .gray : color)
            HStack {
                Text(low).font(.appMicro).foregroundColor(.gray)
                Spacer()
                Text(high).font(.appMicro).foregroundColor(.gray)
            }
        }
    }

    static func sorenessColor(_ v: Double) -> Color {
        if v >= 7 { return .statusRed }; if v >= 4 { return .statusOrange }; return .statusGreen
    }
    static func fatigueColor(_ v: Double) -> Color {
        if v >= 7 { return .statusRed }; if v >= 4 { return .statusOrange }; return .statusGreen
    }
    static func energyPreColor(_ v: Double) -> Color {
        if v >= 7 { return .statusGreen }; if v >= 4 { return .statusOrange }; return .statusRed
    }
}
