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
    @State private var moodScore: Int = 0          // 0 = unset, 1–5 emoji
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

    private let moodEmojis = ["😴", "😕", "😐", "😊", "😄"]

    private var isEditing: Bool { prefillEntry != nil }

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
                                    ProgressView().tint(.white).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "heart.text.square.fill")
                                        .font(.system(size: 15))
                                }
                                Text(isLoadingHK ? "Lecture Health..." : "Remplir depuis Apple Santé")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(12)
                        }
                        .disabled(isLoadingHK)
                        .buttonStyle(SpringButtonStyle())
                        #endif

                        if showFullMode {
                            // ── MODE COMPLET ─────────────────────────────

                            // Sommeil complet + bedtime/wakeTime
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SOMMEIL").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                HStack(spacing: 12) {
                                    RecoveryField(label: "DURÉE (h)", placeholder: "7.5", text: $sleepHoursStr)
                                    RecoveryField(label: "FC REPOS (bpm)", placeholder: "58", text: $restingHrStr)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("QUALITÉ").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        Text(String(format: "%.0f / 10", sleepQuality))
                                            .font(.system(size: 13, weight: .bold)).foregroundColor(.blue)
                                    }
                                    Slider(value: $sleepQuality, in: 1...10, step: 1).tint(.orange)
                                }
                                Divider().background(Color.white.opacity(0.06))
                                // Bedtime
                                HStack {
                                    Toggle(isOn: $hasBedtime) {
                                        Text("HEURE COUCHER").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    }
                                    .toggleStyle(.switch)
                                    .tint(.blue)
                                }
                                if hasBedtime {
                                    DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                                        .datePickerStyle(.wheel)
                                        .colorScheme(.dark)
                                        .frame(maxHeight: 100)
                                        .clipped()
                                        .labelsHidden()
                                }
                                // Wake time
                                HStack {
                                    Toggle(isOn: $hasWakeTime) {
                                        Text("HEURE RÉVEIL").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    }
                                    .toggleStyle(.switch)
                                    .tint(.blue)
                                }
                                if hasWakeTime {
                                    DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                                        .datePickerStyle(.wheel)
                                        .colorScheme(.dark)
                                        .frame(maxHeight: 100)
                                        .clipped()
                                        .labelsHidden()
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Douleurs + Fatigue + Énergie
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("DOULEURS MUSCULAIRES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        Text(String(format: "%.0f / 10", soreness)).font(.system(size: 13, weight: .bold)).foregroundColor(sorenessColor(soreness))
                                    }
                                    Slider(value: $soreness, in: 0...10, step: 1).tint(sorenessColor(soreness))
                                    HStack {
                                        Text("0 = Aucune").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Sévère").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                                Divider().background(Color.white.opacity(0.06))
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("FATIGUE PERÇUE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        if fatigue == 0 {
                                            Text("—").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
                                        } else {
                                            Text(String(format: "%.0f / 10", fatigue)).font(.system(size: 13, weight: .bold)).foregroundColor(fatigueColor(fatigue))
                                        }
                                    }
                                    Slider(value: $fatigue, in: 0...10, step: 1).tint(fatigue == 0 ? .gray : fatigueColor(fatigue))
                                    HStack {
                                        Text("0 = Non renseigné").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Épuisé(e)").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                                Divider().background(Color.white.opacity(0.06))
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("ÉNERGIE PERÇUE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        if energyPre == 0 {
                                            Text("—").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
                                        } else {
                                            Text(String(format: "%.0f / 10", energyPre)).font(.system(size: 13, weight: .bold)).foregroundColor(energyPreColor(energyPre))
                                        }
                                    }
                                    Slider(value: $energyPre, in: 0...10, step: 1).tint(energyPre == 0 ? .gray : energyPreColor(energyPre))
                                    HStack {
                                        Text("0 = Non renseigné").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Excellent").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Activité
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ACTIVITÉ QUOTIDIENNE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                HStack(spacing: 12) {
                                    RecoveryField(label: "PAS", placeholder: "8500", text: $stepsStr, keyboardType: .numberPad)
                                    VStack(alignment: .leading, spacing: 4) {
                                        RecoveryField(label: "HRV (ms)", placeholder: "45", text: $hrvStr)
                                        if let hrv = Double(hrvStr.replacingOccurrences(of: ",", with: ".")),
                                           !hrvStr.isEmpty, (hrv < 20 || hrv > 200) {
                                            Text("Valeur inhabituelle (20–200 ms)")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(.orange)
                                        }
                                    }
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
                                    Image(systemName: "heart.fill").font(.system(size: 10)).foregroundColor(.red)
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
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.appSurfaceInset)
                                    .cornerRadius(10)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        } else {
                            // ── MODE RAPIDE ───────────────────────────────

                            // Sommeil (heures + qualité)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SOMMEIL").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                RecoveryField(label: "DURÉE (h)", placeholder: "7.5", text: $sleepHoursStr)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("QUALITÉ").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        if sleepQuality == 0 {
                                            Text("—").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
                                        } else {
                                            Text(String(format: "%.0f / 10", sleepQuality))
                                                .font(.system(size: 13, weight: .bold)).foregroundColor(.blue)
                                        }
                                    }
                                    Slider(value: $sleepQuality, in: 0...10, step: 1).tint(.orange)
                                    HStack {
                                        Text("0 = Non renseigné").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Excellent").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)

                            // Humeur
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("HUMEUR DU JOUR").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    Spacer()
                                    if moodScore > 0 {
                                        Text(moodEmojis[moodScore - 1])
                                            .font(.system(size: 18))
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                HStack(spacing: 0) {
                                    ForEach(1...5, id: \.self) { score in
                                        let emoji = moodEmojis[score - 1]
                                        let selected = moodScore == score
                                        Button {
                                            withAnimation(.spring(response: 0.25)) {
                                                moodScore = selected ? 0 : score
                                            }
                                        } label: {
                                            VStack(spacing: 4) {
                                                Text(emoji)
                                                    .font(.system(size: selected ? 30 : 24))
                                                    .scaleEffect(selected ? 1.15 : 1.0)
                                                    .opacity(moodScore == 0 || selected ? 1.0 : 0.4)
                                                Circle()
                                                    .fill(selected ? Color.orange : Color.clear)
                                                    .frame(width: 5, height: 5)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                        }
                                        .buttonStyle(.plain)
                                        .animation(.spring(response: 0.25), value: moodScore)
                                    }
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)

                            // Fatigue + Douleurs
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("FATIGUE PERÇUE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        if fatigue == 0 {
                                            Text("—").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
                                        } else {
                                            Text(String(format: "%.0f / 10", fatigue)).font(.system(size: 13, weight: .bold)).foregroundColor(fatigueColor(fatigue))
                                        }
                                    }
                                    Slider(value: $fatigue, in: 0...10, step: 1).tint(fatigue == 0 ? .gray : fatigueColor(fatigue))
                                    HStack {
                                        Text("0 = Non renseigné").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Épuisé(e)").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                                Divider().background(Color.white.opacity(0.06))
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("DOULEURS MUSCULAIRES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        if soreness == 0 {
                                            Text("—").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
                                        } else {
                                            Text(String(format: "%.0f / 10", soreness)).font(.system(size: 13, weight: .bold)).foregroundColor(sorenessColor(soreness))
                                        }
                                    }
                                    Slider(value: $soreness, in: 0...10, step: 1).tint(soreness == 0 ? .gray : sorenessColor(soreness))
                                    HStack {
                                        Text("0 = Aucune").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Sévère").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
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
                                        .font(.system(size: 13))
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
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
            .onAppear { prefill() }
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
        } else {
            showFullMode = prefersFull
            fillFromHealthKit()
        }
    }

    private func sorenessColor(_ v: Double) -> Color {
        if v >= 7 { return .red }; if v >= 4 { return .orange }; return .green
    }

    private func fatigueColor(_ v: Double) -> Color {
        if v >= 7 { return .red }; if v >= 4 { return .orange }; return .green
    }

    private func energyPreColor(_ v: Double) -> Color {
        if v >= 7 { return .green }; if v >= 4 { return .orange }; return .red
    }

    private func fillFromHealthKit() {
        isLoadingHK = true
        let date = selectedDate
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isLoadingHK = false; return }

            // sequential — async let LIFO crash on iOS 26 beta
            let s  = await hk.fetchSleep(for: date)
            let h  = await hk.fetchRestingHR(for: date)
            let v  = await hk.fetchHRV(for: date)
            let st = await hk.fetchSteps(for: date)
            let a  = await hk.fetchActiveEnergy(for: date)
            let m   = await hk.fetchMorningHR(for: date)
            let pw  = await hk.fetchPostWorkoutHR(for: date)
            let e   = await hk.fetchEveningHR(for: date)
            let win = await hk.fetchSleepWindow(for: date)

            if let s  { sleepHoursStr    = String(format: "%.1f", s) }
            if let h  { restingHrStr     = String(format: "%.0f", h) }
            if let v  { hrvStr           = String(format: "%.0f", v) }
            if let st { stepsStr         = "\(st)" }
            if let a  { activeEnergyStr  = String(format: "%.0f", a) }
            if let m  { hrMorningStr     = String(format: "%.0f", m) }
            if let pw { hrPostWorkoutStr = String(format: "%.0f", pw) }
            if let e  { hrEveningStr     = String(format: "%.0f", e) }
            if let win { bedtime = win.bedtime; hasBedtime = true
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
        // In quick mode, moodScore (1-5) maps to energyPre (2,4,6,8,10)
        let resolvedEnergyPre: Double? = showFullMode
            ? (energyPre == 0 ? nil : energyPre)
            : (moodScore == 0 ? nil : Double(moodScore * 2))
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
                    energyPre:     resolvedEnergyPre,
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

struct RecoveryField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .decimalPad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .foregroundColor(.white)
                .padding(10)
                .background(Color.appSurfaceInset)
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
    }
}
