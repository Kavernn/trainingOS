import SwiftUI

// MARK: - Ritual Engagement Card (état dynamique du cycle engagement)

struct RitualDemonCard: View {
    let ritual: RitualToday
    let onComplete: () -> Void
    @State private var showRitual = false

    private var pendingCount: Int {
        ritual.engagements.filter { !$0.isAddressed }.count
    }

    private var readyCardTitle: String {
        let n = ritual.tomorrowEngagements.count
        return "DEMAIN : \(n) ENGAGEMENT\(n > 1 ? "S" : "") ✓"
    }

    var body: some View {
        cardContent
            .fullScreenCover(isPresented: $showRitual, onDismiss: onComplete) {
                RitualView()
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        if !ritual.engagements.isEmpty && !ritual.allEngagementsAddressed {
            pendingCard
        } else if ritual.allEngagementsAddressed && !ritual.tomorrowCreated {
            prepareCard
        } else if ritual.tomorrowCreated {
            readyCard
        } else {
            firstDayCard
        }
    }

    // Engagements en attente d'adressage
    private var pendingCard: some View {
        Button { showRitual = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: "F59E0B").opacity(0.12)).frame(width: 36, height: 36)
                    Image(systemName: "checklist")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(Color(hex: "F59E0B"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(pendingCount) ENGAGEMENT\(pendingCount > 1 ? "S" : "") EN ATTENTE")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(Color(hex: "F59E0B").opacity(0.85))
                        .tracking(0.5)
                    if let ts = ritual.engagementsCreatedAt {
                        Text(ts)
                            .font(.appCaption)
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color(hex: "F59E0B").opacity(0.6))
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "F59E0B").opacity(0.25), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // Tout adressé, manque la création du soir
    private var prepareCard: some View {
        Button { showRitual = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: "F59E0B").opacity(0.08)).frame(width: 36, height: 36)
                    Image(systemName: "moon.stars.fill")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(Color(hex: "F59E0B").opacity(0.7))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRÉPARE DEMAIN")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(Color(hex: "F59E0B").opacity(0.8))
                        .tracking(0.5)
                    Text("Journée clôturée · Crée tes engagements.")
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color(hex: "F59E0B").opacity(0.5))
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "F59E0B").opacity(0.15), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // Demain déjà préparé
    private var readyCard: some View {
        Button { showRitual = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: "22C55E").opacity(0.1)).frame(width: 36, height: 36)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(Color(hex: "22C55E").opacity(0.7))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(readyCardTitle)
                        .font(.appMicro.weight(.black))
                        .foregroundColor(Color(hex: "22C55E").opacity(0.75))
                        .tracking(0.5)
                    Text("Cycle complété.")
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "22C55E").opacity(0.15), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // Premier jour / aucun engagement
    private var firstDayCard: some View {
        Button { showRitual = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: "F59E0B").opacity(0.08)).frame(width: 36, height: 36)
                    Image(systemName: "sunrise.fill")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(Color(hex: "F59E0B").opacity(0.7))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("CE SOIR, CRÉE TES ENGAGEMENTS")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(Color(hex: "F59E0B").opacity(0.75))
                        .tracking(0.5)
                    Text("Aucun engagement prévu pour demain.")
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color(hex: "F59E0B").opacity(0.5))
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "F59E0B").opacity(0.12), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

}

// MARK: - Breathwork Nudge Card

struct BreathworkNudgeCard: View {
    @AppStorage("breathwork.nudge.dismissed.date") private var dismissedDate = ""

    private var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    var body: some View {
        if dismissedDate != todayStr {
            HStack(spacing: 10) {
                Image(systemName: "wind")
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.teal)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Stress élevé détecté")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("5 min de cohérence cardiaque maintenant.")
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.55))
                }

                Spacer()

                Button { dismissedDate = todayStr } label: {
                    Image(systemName: "xmark")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.teal.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}

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
                                        .foregroundColor(selectedContext == ctx ? .black : .white.opacity(0.7))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(selectedContext == ctx ? Color(hex: "E8441A") : Color.white.opacity(0.06))
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
                                .foregroundColor(intensity >= 7 ? Color(hex: "E8441A") : .white)
                        }
                        Slider(value: $intensity, in: 1...10, step: 1)
                            .tint(Color(hex: "E8441A"))
                    }

                    // Yielded toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("J'ai cédé")
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Cochez si vous avez succombé à la tentation.")
                                .font(.appCaption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Toggle("", isOn: $yielded)
                            .tint(Color(hex: "E8441A"))
                            .labelsHidden()
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
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
                                ProgressView().tint(.white)
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
                        .background(Color(hex: "C0201A"))
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
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    HStack(spacing: 16) {
                        battleButton(
                            label: "VICTOIRE",
                            icon: "checkmark.seal.fill",
                            color: Color(hex: "22C55E"),
                            status: .victory
                        )
                        battleButton(
                            label: "DÉFAITE",
                            icon: "xmark.seal.fill",
                            color: Color(hex: "EF4444"),
                            status: .lost
                        )
                    }

                    if saved {
                        Label("Enregistré", systemImage: "checkmark")
                            .font(.appLabel)
                            .foregroundColor(.green)
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

// MARK: - EveningRoutineCard

struct EveningRoutineCard: View {
    let ritual: RitualToday
    let onRoutineUpdated: () -> Void

    @State private var noFood: Bool
    @State private var dimLights: Bool
    @State private var shower: Bool
    @State private var connection: Bool
    @State private var deconnect: Bool
    @State private var prioritiesDone: Bool
    @State private var bedtimeOk: Bool
    @State private var isExpanded = true
    @State private var showRitual = false

    init(ritual: RitualToday, onRoutineUpdated: @escaping () -> Void) {
        self.ritual = ritual
        self.onRoutineUpdated = onRoutineUpdated
        _noFood         = State(initialValue: ritual.routineNoFood)
        _dimLights      = State(initialValue: ritual.routineDimLights)
        _shower         = State(initialValue: ritual.routineShower)
        _connection     = State(initialValue: ritual.routineConnection)
        _deconnect      = State(initialValue: ritual.routineDeconnect)
        _prioritiesDone = State(initialValue: ritual.routinePrioritiesDone)
        _bedtimeOk      = State(initialValue: ritual.routineBedtimeOk)
    }

    private var checkedCount: Int {
        [noFood, dimLights, shower, connection, deconnect, prioritiesDone, bedtimeOk]
            .filter { $0 }.count
    }
    private var allDone: Bool { checkedCount == 7 }
    private var currentHour: Int { Calendar.current.component(.hour, from: Date()) }
    private var softLimitWarning: Bool { currentHour >= 22 && !deconnect }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if !allDone || isExpanded {
                progressBar
                    .padding(.top, 10)
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.top, 10)
                itemsList
                    .padding(.top, 4)
            }
            if allDone && !isExpanded {
                expandButton
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(allDone ? Color.green.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .onAppear {
            NotificationService.scheduleEveningRoutineBedtimeReminder(bedtimeOkAlreadyChecked: bedtimeOk)
        }
        .onChange(of: ritual.routinePrioritiesDone) { _, newValue in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { prioritiesDone = newValue }
        }
        .onChange(of: allDone) { _, done in
            if done { withAnimation(.easeInOut(duration: 0.3)) { isExpanded = false } }
        }
        .onChange(of: bedtimeOk) { _, checked in
            if checked { NotificationService.cancelEveningRoutineBedtimeReminder() }
        }
        .fullScreenCover(isPresented: $showRitual, onDismiss: onRoutineUpdated) {
            RitualView()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        let icon       = allDone ? "checkmark.circle.fill" : "moon.stars.fill"
        let title      = allDone ? "Routine complétée" : "Routine de soir"
        let titleColor = allDone ? Color.green : Color.white.opacity(0.85)
        let iconColor  = allDone ? Color.green : Color.white.opacity(0.55)
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.appLabel)
                .foregroundColor(iconColor)
            Text(title)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(titleColor)
            Spacer()
            if allDone {
                Text("\(checkedCount)/7")
                    .font(.appMicro.weight(.medium))
                    .foregroundColor(.green.opacity(0.7))
            } else {
                timeBadge
            }
        }
    }

    private var timeBadge: some View {
        let hourColor = softLimitWarning ? Color.orange : Color.white.opacity(0.3)
        let bgColor   = softLimitWarning ? Color.orange.opacity(0.12) : Color.white.opacity(0.05)
        return HStack(spacing: 3) {
            Text("22h")
                .font(.appMicro.weight(.medium))
                .foregroundColor(hourColor)
            Text("·").font(.appMicro).foregroundColor(.white.opacity(0.2))
            Text("23h30")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(bgColor)
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.3), value: softLimitWarning)
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let count    = checkedCount
        let barColor = allDone ? Color.green : Color.forge
        return GeometryReader { geo in
            let filledWidth = count > 0 ? geo.size.width * CGFloat(count) / 7.0 : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06)).frame(height: 2)
                Capsule()
                    .fill(barColor)
                    .frame(width: filledWidth, height: 2)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: count)
            }
        }
        .frame(height: 2)
    }

    // MARK: - Items list

    private var itemsList: some View {
        VStack(spacing: 0) {
            itemRow("🍽️", "Arrêter de manger",      checked: $noFood,      field: "routine_no_food")
            itemRow("💡", "Tamiser les lumières",    checked: $dimLights,   field: "routine_dim_lights")
            itemRow("🚿", "Douche chaude",           checked: $shower,      field: "routine_shower")
            itemRow("👦", "Connexion avec ton fils", checked: $connection,  field: "routine_connection")
            deconnectRow
            prioritiesRow
            itemRow("🌙", "Au lit avant l'heure",    checked: $bedtimeOk,   field: "routine_bedtime_ok")
        }
    }

    // MARK: - Generic item row

    private func itemRow(
        _ emoji: String,
        _ label: String,
        checked: Binding<Bool>,
        field: String
    ) -> some View {
        let isChecked  = checked.wrappedValue
        let textColor  = isChecked ? Color.white.opacity(0.45) : Color.white.opacity(0.8)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { checked.wrappedValue.toggle() }
            let newVal = checked.wrappedValue
            Task { try? await APIService.shared.saveEveningRoutineItem(field, value: newVal) }
        } label: {
            HStack(spacing: 10) {
                checkCircle(checked: isChecked)
                Text(emoji).font(.system(size: 14))
                Text(label)
                    .font(.appCaption)
                    .foregroundColor(textColor)
                    .strikethrough(isChecked, color: .white.opacity(0.2))
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Abrutissement positif (with 22h warning badge)

    private var deconnectRow: some View {
        let isChecked = deconnect
        let textColor = isChecked ? Color.white.opacity(0.45) : Color.white.opacity(0.8)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { deconnect.toggle() }
            let newVal = deconnect
            Task { try? await APIService.shared.saveEveningRoutineItem("routine_deconnect", value: newVal) }
        } label: {
            HStack(spacing: 10) {
                checkCircle(checked: isChecked)
                Text("🎮").font(.system(size: 14))
                Text("Abrutissement positif")
                    .font(.appCaption)
                    .foregroundColor(textColor)
                    .strikethrough(isChecked, color: .white.opacity(0.2))
                Spacer()
                if softLimitWarning {
                    Text("22h")
                        .font(.appMicro.weight(.bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: softLimitWarning)
    }

    // MARK: - Priorités demain (auto-check via tomorrow_intention)

    private var prioritiesRow: some View {
        Group {
            if prioritiesDone {
                HStack(spacing: 10) {
                    checkCircle(checked: true)
                    Text("📝").font(.system(size: 14))
                    Text("Priorités demain")
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.45))
                        .strikethrough(true, color: .white.opacity(0.2))
                    Spacer()
                    Text("auto ✓")
                        .font(.appMicro)
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }
                .padding(.vertical, 8)
            } else {
                Button { showRitual = true } label: {
                    HStack(spacing: 10) {
                        checkCircle(checked: false)
                        Text("📝").font(.system(size: 14))
                        Text("Priorités demain")
                            .font(.appCaption)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.appMicro.weight(.semibold))
                            .foregroundColor(.white.opacity(0.25))
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Expand button

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
        } label: {
            HStack(spacing: 4) {
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
                Text("Voir les détails")
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
            }
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Check circle

    private func checkCircle(checked: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(checked ? Color.green.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1.5)
                .frame(width: 20, height: 20)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: checked)
    }
}
