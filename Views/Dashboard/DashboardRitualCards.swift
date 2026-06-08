import SwiftUI

// MARK: - Evening Ritual Entry Card

struct EveningRitualEntryCard: View {
    let ritual: RitualToday
    let onComplete: () -> Void
    @State private var showRitualEvening = false

    var body: some View {
        Button { showRitualEvening = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "1a0a0a"))
                        .frame(width: 36, height: 36)
                    Image(systemName: "flame.fill")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(Color(hex: "E8441A"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("FERME TA JOURNÉE")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(Color(hex: "E8441A").opacity(0.8))
                        .tracking(0.5)
                    if let intention = ritual.intention, !intention.isEmpty {
                        Text("« \(intention) »")
                            .font(.appCaption.weight(.medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    } else {
                        Text("Tu avais posé une intention ce matin.")
                            .font(.appCaption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                Text("BURNED / SURVIVED")
                    .font(.appMicro.weight(.bold))
                    .foregroundColor(Color(hex: "E8441A"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "E8441A").opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "E8441A").opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showRitualEvening, onDismiss: onComplete) {
            RitualView()
        }
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

// MARK: - Morning Ritual Entry Card

struct MorningRitualEntryCard: View {
    let ritual: RitualToday
    let onComplete: () -> Void
    @State private var showRitual    = false
    @State private var dragOffset: CGFloat = 0

    private var eveningTimeLabel: String? {
        guard let iso = ritual.yesterdayEveningAt else { return nil }
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = df.date(from: iso) {
            let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
            return fmt.string(from: d)
        }
        let df2 = ISO8601DateFormatter()
        if let d = df2.date(from: iso) {
            let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
            return fmt.string(from: d)
        }
        return nil
    }

    var body: some View {
        Group {
            if let yesterday = ritual.yesterdayIntention {
                intentionCard(yesterday)
            } else {
                defaultCard
            }
        }
        .fullScreenCover(isPresented: $showRitual, onDismiss: onComplete) {
            RitualView()
        }
    }

    // Card enrichie — intention d'hier soir visible
    private func intentionCard(_ intention: String) -> some View {
        Button { showRitual = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "sunset.fill")
                        .font(.appMicro.weight(.semibold))
                        .foregroundColor(Color.forge.opacity(0.8))
                    Text("TON ENGAGEMENT")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(Color.forge.opacity(0.8))
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.bottom, 8)

                Rectangle()
                    .fill(Color.forge.opacity(0.12))
                    .frame(height: 1)
                    .padding(.bottom, 10)

                Text("«\u{202F}\(intention)\u{202F}»")
                    .font(.appCaption.weight(.medium))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                    .padding(.bottom, 10)

                HStack {
                    let timeStr = eveningTimeLabel.map { "Hier soir · \($0)" } ?? "Hier soir"
                    Text(timeStr)
                        .font(.appMicro)
                        .foregroundColor(.white.opacity(0.3))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.appMicro.weight(.semibold))
                        .foregroundColor(Color.forge.opacity(0.5))
                }
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.forge.opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // Card par défaut — comportement inchangé
    private var defaultCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: dragOffset > 20 ? "arrow.right.circle.fill" : "sunrise.fill")
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(.orange)
                    .animation(.easeInOut(duration: 0.15), value: dragOffset > 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("RITUEL DU MATIN")
                    .font(.appMicro.weight(.black))
                    .foregroundColor(.orange.opacity(0.8))
                    .tracking(0.5)
                Text("Pose ton intention avant de commencer.")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            Text("COMMENCER")
                .font(.appMicro.weight(.bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(dragOffset > 20 ? Color.orange.opacity(0.6) : Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
        .offset(x: max(0, dragOffset * 0.3))
        .gesture(
            DragGesture()
                .onChanged { v in dragOffset = v.translation.width }
                .onEnded { v in
                    if v.translation.width > 60 { showRitual = true }
                    withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                }
        )
        .onTapGesture { showRitual = true }
    }
}

// MARK: - E5: Demon Dashboard Banner

struct DemonDashboardBanner: View {
    let demon: RitualDemon
    let onComplete: () -> Void
    @State private var showRitual = false

    var body: some View {
        Button { showRitual = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.forge.opacity(AppTheme.shared.selectedTheme == .blood ? 0.18 : 0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: "moon.stars.fill")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(AppTheme.shared.selectedTheme == .blood ? Color.forge.opacity(0.7) : Color(white: 0.4))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("DÉMON · \(demon.carryCount) NUITS")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(AppTheme.shared.selectedTheme == .blood ? Color.forge.opacity(0.55) : Color(white: 0.3))
                        .tracking(0.5)
                    Text("«\(demon.intention)»")
                        .font(.appCaption)
                        .foregroundColor(Color(white: 0.55))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.forge.opacity(AppTheme.shared.selectedTheme == .blood ? 0.85 : 0.5))
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.forge.opacity(AppTheme.shared.selectedTheme == .blood ? 0.3 : 0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showRitual, onDismiss: onComplete) { RitualView() }
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
