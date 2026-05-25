import SwiftUI

// MARK: - HRV Onboarding Sheet (3 écrans)

struct HRVOnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0
    private let totalPages  = 3

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle ambient glow behind icon
            Circle()
                .fill(pageAccent.opacity(0.08))
                .frame(width: 340, height: 340)
                .blur(radius: 60)
                .offset(y: -80)

            VStack(spacing: 0) {

                // Skip
                HStack {
                    Spacer()
                    Button("Passer") { finish() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                }

                Spacer()

                // Page content
                Group {
                    switch page {
                    case 0: page1
                    case 1: page2
                    default: page3
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(page)

                Spacer()

                // Dots + bouton
                VStack(spacing: 24) {
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? pageAccent : Color.white.opacity(0.2))
                                .frame(width: i == page ? 20 : 6, height: 6)
                                .animation(.spring(response: 0.3), value: page)
                        }
                    }

                    Button(action: advance) {
                        HStack(spacing: 8) {
                            Text(page < totalPages - 1 ? "Suivant" : "C'est parti")
                                .font(.system(size: 16, weight: .bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(pageAccent)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Pages

    private var page1: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(pageAccent.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 44))
                    .foregroundColor(pageAccent)
            }

            VStack(spacing: 12) {
                Text("C'est quoi le HRV ?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("La variabilité de ton rythme cardiaque révèle l'état réel de ton système nerveux — plus fiable que ton ressenti subjectif.")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Fact chips
            HStack(spacing: 10) {
                FactChip(icon: "applewatch", text: "Apple Watch", color: pageAccent)
                FactChip(icon: "chart.line.uptrend.xyaxis", text: "Score personnel", color: pageAccent)
            }
        }
        .padding(.horizontal, 32)
    }

    private var page2: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(pageAccent.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 40))
                    .foregroundColor(pageAccent)
            }

            VStack(spacing: 12) {
                Text("Le protocole du matin")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Chaque matin, avant de te lever :")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
            }

            VStack(alignment: .leading, spacing: 10) {
                ProtocolStep(number: 1, icon: "sun.rise.fill",          text: "Réveille-toi naturellement",        color: pageAccent)
                ProtocolStep(number: 2, icon: "bed.double.fill",        text: "Reste allongé — ne te lève pas encore", color: pageAccent)
                ProtocolStep(number: 3, icon: "wind",                   text: "Respire normalement",              color: pageAccent)
                ProtocolStep(number: 4, icon: "timer",                  text: "Attends environ 60 secondes",      color: pageAccent)
                ProtocolStep(number: 5, icon: "iphone",                 text: "Ouvre VinceSeven — ta mesure est prête", color: pageAccent)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 32)
    }

    private var page3: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(pageAccent.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(pageAccent)
            }

            VStack(spacing: 12) {
                Text("L'app fait le reste")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Ton Apple Watch collecte en arrière-plan pendant le sommeil. VinceSeven calcule ton score personnalisé chaque matin — rien d'autre à faire.")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // What they'll get
            VStack(spacing: 8) {
                AutoFeatureRow(icon: "circle.fill",           color: .green,  text: "Score vert — séance à 100%")
                AutoFeatureRow(icon: "circle.fill",           color: .orange, text: "Score orange — surveille la fatigue")
                AutoFeatureRow(icon: "circle.fill",           color: .red,    text: "Score rouge — récupération d'abord")
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Helpers

    private var pageAccent: Color {
        switch page {
        case 0: return .cyan
        case 1: return Color(red: 0.4, green: 0.8, blue: 0.6)
        default: return .green
        }
    }

    private func advance() {
        if page < totalPages - 1 {
            withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "hrv_onboarding_done")
        onDone()
    }
}

// MARK: - Sub-components

private struct FactChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.07))
        .cornerRadius(20)
    }
}

private struct ProtocolStep: View {
    let number: Int
    let icon:   String
    let text:   String
    let color:  Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(color)
            }

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.9))

            Spacer()
        }
    }
}

private struct AutoFeatureRow: View {
    let icon:  String
    let color: Color
    let text:  String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}
