import SwiftUI

// MARK: - Quick War Room Trigger Sheet

struct QuickWarRoomTriggerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedContext: TriggerContext = .stress
    @State private var intensity: Double = 5
    @State private var yielded = false
    @State private var isSaving = false
    @State private var saved = false

    private let contexts: [TriggerContext] = [.stress, .social, .boredom, .pain, .celebration, .exhaustion]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Context picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CONTEXTE")
                            .font(.appCaption.weight(.bold))
                            .foregroundColor(.gray)
                            .tracking(0.8)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(contexts, id: \.rawValue) { ctx in
                                Button {
                                    withAnimation(.spring(response: 0.25)) { selectedContext = ctx }
                                } label: {
                                    Text(ctx.label)
                                        .font(.appCaption.weight(selectedContext == ctx ? .bold : .regular))
                                        .foregroundColor(selectedContext == ctx ? .black : Color.appOnSurface.opacity(0.7))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(selectedContext == ctx ? Color.appDanger : Color.appSurfaceInset)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Intensity
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("INTENSITÉ")
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(.gray)
                                .tracking(0.8)
                            Spacer()
                            Text("\(Int(intensity))/10")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(intensity >= 7 ? Color.appDanger : .white)
                        }
                        Slider(value: $intensity, in: 1...10, step: 1)
                            .tint(Color.appDanger)
                    }

                    // Yielded toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("J'ai cédé")
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.appTextPrimary)
                            Text("Cochez si vous avez succombé à la tentation.")
                                .font(.appCaption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Toggle("", isOn: $yielded)
                            .tint(Color.appDanger)
                            .labelsHidden()
                    }
                    .padding(14)
                    .background(Color.appSurfaceInset)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    // Save
                    Button {
                        Task {
                            isSaving = true
                            _ = try? await APIService.shared.logTrigger(
                                context: selectedContext,
                                intensity: Int(intensity),
                                yielded: yielded,
                                contextNote: nil,
                                heldWith: []
                            )
                            isSaving = false
                            saved = true
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView().tint(.onAccent)
                            } else if saved {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("Logger la tentation")
                                    .font(.appBody.weight(.bold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.appDanger)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || saved)
                }
                .padding(20)
            }
            .navigationTitle("Tentation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.gray)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.appBg)
    }
}

// MARK: - Quick Battle Sheet (War Room victory / defeat)

struct QuickBattleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 28) {
                    Text("Comment s'est terminée la journée ?")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    HStack(spacing: 16) {
                        battleButton(
                            label: "VICTOIRE",
                            icon: "checkmark.seal.fill",
                            color: Color.appSuccess,
                            status: .victory
                        )
                        battleButton(
                            label: "DÉFAITE",
                            icon: "xmark.seal.fill",
                            color: Color.appDanger,
                            status: .lost
                        )
                    }

                    if saved {
                        Label("Enregistré", systemImage: "checkmark")
                            .font(.appLabel)
                            .foregroundColor(Color.appSuccess)
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Résultat du jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.gray)
                }
            }
        }
        .presentationDetents([.height(280)])
        .presentationBackground(Color.appBg)
    }

    @ViewBuilder
    private func battleButton(label: String, icon: String, color: Color, status: BattleStatus) -> some View {
        Button {
            guard !isSaving, !saved else { return }
            isSaving = true
            Task {
                _ = try? await APIService.shared.upsertBattle(
                    date: DateFormatter.isoDate.string(from: Date()),
                    status: status
                )
                await MainActor.run {
                    isSaving = false
                    saved = true
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
                Text(label)
                    .font(.appCaption.weight(.black))
                    .foregroundColor(color)
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || saved)
    }
}


// MARK: - Evening Reminders Store (UserDefaults)

enum EveningRemindersStore {
    private static let key = "eveningReminders.items"

    static func get() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ items: [String]) {
        UserDefaults.standard.set(items, forKey: key)
    }

    static func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = get()
        items.append(trimmed)
        save(items)
    }

    static func remove(at index: Int) {
        var items = get()
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        save(items)
    }
}

// MARK: - EveningSleepCard (aide-mémoire bienveillant, après 20h)

struct EveningSleepCard: View {
    @State private var showSheet = false

    static let sleepTips: [(title: String, body: String)] = [
        ("Baisse les lumières",
         "Une heure avant de dormir, tamise les lumières vives. La lumière forte retarde la mélatonine, l'hormone qui prépare ton corps au sommeil."),
        ("Éloigne les écrans",
         "La lumière bleue des écrans trompe ton cerveau et le maintient en éveil. Si tu peux, pose le téléphone 30 minutes avant le lit, ou passe en mode nuit."),
        ("Garde la chambre fraîche",
         "Ton corps s'endort plus facilement quand il refroidit légèrement. Une pièce autour de 18-19°C aide la transition vers le sommeil profond."),
        ("Même heure, chaque soir",
         "La régularité compte autant que la durée. Te coucher et te lever à des heures stables cale ton horloge interne."),
        ("Laisse retomber la pression",
         "Le sommeil n'arrive pas sur commande. Quelques minutes de calme — respiration lente, lecture légère — signalent à ton corps qu'il peut lâcher prise."),
        ("La caféine reste longtemps",
         "Un café de fin d'après-midi peut encore agir au coucher. Si ton sommeil est fragile, coupe tôt dans la journée."),
    ]

    // Rotation stable : 1 conseil par jour calendaire (aperçu sur la carte)
    private var todayTip: (title: String, body: String) {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return Self.sleepTips[(day - 1) % Self.sleepTips.count]
    }

    var body: some View {
        Button { showSheet = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.appLabel)
                        .foregroundColor(Color.statusPurple.opacity(0.75))
                    Text("Routine du soir")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(Color.appOnSurface.opacity(0.9))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(Color.appOnSurface.opacity(0.3))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(todayTip.title)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(Color.appOnSurface.opacity(0.8))
                    Text(todayTip.body)
                        .font(.appCaption)
                        .foregroundColor(Color.appOnSurface.opacity(0.6))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.statusPurple.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            EveningSleepSheet()
        }
    }
}

// MARK: - EveningSleepSheet (détail ouvrable : conseils + rappels perso + réveil)

struct EveningSleepSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reminders: [String] = EveningRemindersStore.get()
    @State private var newReminder: String = ""
    @ObservedObject private var alarm = SmartAlarmService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sleepTipsSection
                    remindersSection
                    if alarm.isEnabled { alarmSection }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color.appBg)
            .navigationTitle("Routine du soir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(Color.forge)
                }
            }
        }
    }

    private var sleepTipsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("QUELQUES REPÈRES POUR UNE BONNE NUIT")
                .font(.appMicro.weight(.bold))
                .tracking(1.5)
                .foregroundColor(Color.appOnSurface.opacity(0.5))
            ForEach(EveningSleepCard.sleepTips, id: \.title) { tip in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tip.title)
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(Color.appOnSurface.opacity(0.9))
                    Text(tip.body)
                        .font(.appCaption)
                        .foregroundColor(Color.appOnSurface.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MES RAPPELS")
                .font(.appMicro.weight(.bold))
                .tracking(1.5)
                .foregroundColor(Color.appOnSurface.opacity(0.5))

            if reminders.isEmpty {
                Text("Ajoute un rappel personnel pour le soir.")
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(0.4))
                    .italic()
            } else {
                ForEach(Array(reminders.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundColor(Color.statusPurple.opacity(0.6))
                        Text(item)
                            .font(.appCaption)
                            .foregroundColor(Color.appOnSurface.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            EveningRemindersStore.remove(at: idx)
                            reminders = EveningRemindersStore.get()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.appCaption)
                                .foregroundColor(Color.statusRed.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                }
            }

            HStack(spacing: 8) {
                TextField("Nouveau rappel…", text: $newReminder)
                    .font(.appCaption)
                    .padding(8)
                    .background(Color.appCard)
                    .cornerRadius(8)
                    .submitLabel(.done)
                    .onSubmit { addReminder() }
                Button { addReminder() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.appBody)
                        .foregroundColor(canAddReminder ? Color.forge : Color.appOnSurface.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(!canAddReminder)
            }
            .padding(.top, 6)
        }
    }

    private var canAddReminder: Bool {
        !newReminder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addReminder() {
        guard canAddReminder else { return }
        EveningRemindersStore.add(newReminder)
        newReminder = ""
        reminders = EveningRemindersStore.get()
    }

    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RÉVEIL")
                .font(.appMicro.weight(.bold))
                .tracking(1.5)
                .foregroundColor(Color.appOnSurface.opacity(0.5))
            alarmRow
        }
    }

    private var alarmRow: some View {
        let isArmed: Bool
        let label: String
        if case .armed(let t) = alarm.state {
            isArmed = true
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            label = "Armé — \(fmt.string(from: t))"
        } else {
            isArmed = false
            label = "Armer réveil cyclique"
        }
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if isArmed {
                alarm.cancelAlarm()
            } else {
                Task { try? await alarm.scheduleAlarm(bedtimeDate: Date()) }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(isArmed ? Color.appSuccess.opacity(0.6) : Color.appOnSurface.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    Image(systemName: isArmed ? "bell.fill" : "bell")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isArmed ? Color.statusGreen : Color.appOnSurface.opacity(0.5))
                }
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isArmed)
                Text("🔔").font(.system(size: 14))
                Text(label)
                    .font(.appCaption)
                    .foregroundColor(isArmed ? Color.statusGreen.opacity(0.85) : Color.appOnSurface.opacity(0.8))
                Spacer()
                if isArmed {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        alarm.cancelAlarm()
                    } label: {
                        Text("Annuler")
                            .font(.appMicro.weight(.bold))
                            .foregroundColor(Color.forge)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.forge.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.appCard)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isArmed)
    }
}
