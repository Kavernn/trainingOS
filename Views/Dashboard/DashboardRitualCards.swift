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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "E8441A"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("FERME TA JOURNÉE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(Color(hex: "E8441A").opacity(0.8))
                        .tracking(0.5)
                    if let intention = ritual.intention, !intention.isEmpty {
                        Text("« \(intention) »")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    } else {
                        Text("Tu avais posé une intention ce matin.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                Text("BURNED / SURVIVED")
                    .font(.system(size: 9, weight: .bold))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.teal)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Stress élevé détecté")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("5 min de cohérence cardiaque maintenant.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }

                Spacer()

                Button { dismissedDate = todayStr } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
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
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                            .tracking(0.8)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(contexts, id: \.rawValue) { ctx in
                                Button {
                                    withAnimation(.spring(response: 0.25)) { selectedContext = ctx }
                                } label: {
                                    Text(ctx.label)
                                        .font(.system(size: 12, weight: selectedContext == ctx ? .bold : .regular))
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
                                .font(.system(size: 10, weight: .bold))
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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Cochez si vous avez succombé à la tentation.")
                                .font(.system(size: 11))
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
                                    .font(.system(size: 15, weight: .bold))
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
                        .font(.system(size: 14))
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
    @State private var showRitual = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: dragOffset > 20 ? "arrow.right.circle.fill" : "sunrise.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.orange)
                    .animation(.easeInOut(duration: 0.15), value: dragOffset > 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("RITUEL DU MATIN")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.orange.opacity(0.8))
                    .tracking(0.5)
                Text("Pose ton intention avant de commencer.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            Text("COMMENCER")
                .font(.system(size: 9, weight: .bold))
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
        .fullScreenCover(isPresented: $showRitual, onDismiss: onComplete) {
            RitualView()
        }
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
                        .fill(Color(white: 0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(white: 0.4))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("DÉMON · \(demon.carryCount) NUITS")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(Color(white: 0.3))
                        .tracking(0.5)
                    Text("«\(demon.intention)»")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.55))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "FF2D20").opacity(0.5))
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(white: 0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showRitual, onDismiss: onComplete) { RitualView() }
    }
}

// MARK: - Season Midpoint Card (D44-D46)

struct SeasonMidpointCard: View {
    let seasonNumber: Int
    @State private var showOath = false

    var body: some View {
        Button { showOath = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "flag.2.crossed.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MI-SAISON \(seasonNumber)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.purple.opacity(0.8))
                        .tracking(0.5)
                    Text("La saison se gagne ou se perd dans les 45 prochains jours.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.purple.opacity(0.6))
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showOath) {
            OathGateView()
        }
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
                        .font(.system(size: 16, weight: .semibold))
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
                            .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 14))
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
                    .font(.system(size: 12, weight: .black))
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
