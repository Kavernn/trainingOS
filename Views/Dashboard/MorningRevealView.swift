import SwiftUI

// MARK: - Morning Reveal View
// Shown once per day on first app open before 14h.
// Theatrically reveals LSS / SmartDay recommendation à la Whoop.
struct MorningRevealView: View {
    let morningBrief: MorningBriefData
    let onDismiss: () -> Void

    @State private var showReveal = false
    @State private var showDetails = false
    @State private var showButton = false
    @State private var pulse = false

    private var accentColor: Color {
        switch morningBrief.recommendation {
        case "go":         return .green
        case "go_caution": return Color(hex: "F5C518")
        case "reduce":     return .orange
        default:           return .red
        }
    }

    private var icon: String {
        switch morningBrief.recommendation {
        case "go":         return "bolt.fill"
        case "go_caution": return "tortoise.fill"
        case "reduce":     return "arrow.down.circle.fill"
        default:           return "moon.zzz.fill"
        }
    }

    private var title: String {
        switch morningBrief.recommendation {
        case "go":         return "Journée optimale"
        case "go_caution": return "Forme correcte"
        case "reduce":     return "Intensité réduite"
        default:           return "Journée de repos"
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()

            RadialGradient(
                colors: [accentColor.opacity(showReveal ? 0.18 : 0), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: showReveal)

            VStack(spacing: 0) {
                Spacer()

                // Suspense indicator — fades out when reveal starts
                if !showReveal {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.white.opacity(0.4))
                            .scaleEffect(1.1)
                        Text("Analyse de ta forme du jour...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .transition(.opacity)
                }

                // Score reveal
                if showReveal {
                    VStack(spacing: 28) {
                        // Big ring + icon
                        ZStack {
                            Circle()
                                .stroke(accentColor.opacity(0.15), lineWidth: 1)
                                .frame(width: 160, height: 160)
                                .scaleEffect(pulse ? 1.06 : 1)
                                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)

                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [accentColor.opacity(0.22), accentColor.opacity(0.04)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 80
                                    )
                                )
                                .frame(width: 140, height: 140)

                            Image(systemName: icon)
                                .font(.system(size: 56, weight: .bold))
                                .foregroundColor(accentColor)
                        }

                        // Title + message
                        VStack(spacing: 10) {
                            Text(title.uppercased())
                                .font(.system(size: 11, weight: .black))
                                .tracking(3)
                                .foregroundColor(accentColor.opacity(0.75))

                            Text(morningBrief.sessionToday.isEmpty ? title : morningBrief.sessionToday)
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundColor(.white)

                            Text(morningBrief.message)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.horizontal, 36)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                Spacer().frame(height: 48)

                // Components + flags + dismiss
                if showDetails {
                    VStack(spacing: 20) {
                        if let components = morningBrief.components {
                            RevealComponentsRow(components: components)
                        }

                        let activeFlags = activeFlagChips
                        if !activeFlags.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(activeFlags, id: \.text) { chip in
                                    RevealFlagChip(icon: chip.icon, text: chip.text, color: chip.color)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 32)

                if showButton {
                    Button(action: onDismiss) {
                        Text("Commencer la journée")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "080810"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(SpringButtonStyle())
                    .padding(.horizontal, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 48)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { runRevealSequence() }
    }

    private var activeFlagChips: [(icon: String, text: String, color: Color)] {
        var chips: [(icon: String, text: String, color: Color)] = []
        if morningBrief.flags.sleepDeprivation {
            chips.append((icon: "moon.zzz.fill", text: "Manque de sommeil", color: .indigo))
        }
        if morningBrief.flags.hrvDrop {
            chips.append((icon: "waveform.path.ecg", text: "HRV en baisse", color: .orange))
        }
        if morningBrief.flags.trainingOverload {
            chips.append((icon: "flame.fill", text: "Surcharge", color: .red))
        }
        return chips
    }

    private func runRevealSequence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                showReveal = true
            }
            pulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.45)) {
                showDetails = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.easeOut(duration: 0.35)) {
                showButton = true
            }
        }
    }
}

// MARK: - Component chips row
private struct RevealComponentsRow: View {
    let components: MorningBriefComponents

    var body: some View {
        HStack(spacing: 10) {
            if let v = components.sleepQuality {
                RevealComponentChip(icon: "moon.fill", label: "Sommeil", quality: v, color: v > 0.6 ? .indigo : .orange)
            }
            if let v = components.hrvTrend {
                RevealComponentChip(icon: "waveform.path.ecg", label: "HRV", quality: v, color: v > 0.6 ? .green : .orange)
            }
            if let v = components.rhrTrend {
                RevealComponentChip(icon: "heart.fill", label: "FC repos", quality: v, color: v > 0.6 ? .green : .red)
            }
            if let v = components.trainingFatigue {
                RevealComponentChip(icon: "flame.fill", label: "Fatigue", quality: v, color: v > 0.6 ? .green : .orange)
            }
        }
    }
}

private struct RevealComponentChip: View {
    let icon: String
    let label: String
    let quality: Double
    let color: Color

    private var qualityLabel: String {
        switch quality {
        case 0.8...: return "Excellent"
        case 0.6..<0.8: return "Bon"
        case 0.4..<0.6: return "Moyen"
        default: return "Faible"
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(color)
            Text(qualityLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct RevealFlagChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
        .clipShape(Capsule())
    }
}
