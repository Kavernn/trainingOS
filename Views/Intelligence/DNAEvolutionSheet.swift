import SwiftUI

// MARK: - Event model

struct DNAEvolutionEvent: Identifiable {
    let id = UUID()
    let oldArchetypeKey: String
    let dna: WorkoutDNAResponse  // current (new) DNA — used for canvas + archetype data
}

// MARK: - Sheet

struct DNAEvolutionSheet: View {
    let event: DNAEvolutionEvent
    let onDismiss: () -> Void

    @ObservedObject private var appState = AppState.shared
    @State private var showHelix = false

    private var newKey: String   { event.dna.archetype.key }
    private var newAccent: Color { _archetypeAccent(newKey) }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray.opacity(0.45))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                // Badge
                Text("TON DNA A ÉVOLUÉ")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2.5)
                    .foregroundColor(newAccent)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(newAccent.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.bottom, 20)

                // Helix canvas (fades in on appear)
                DNAHelixCanvas(dna: event.dna, height: 100)
                    .frame(maxWidth: .infinity)
                    .opacity(showHelix ? 1 : 0)
                    .animation(.easeIn(duration: 0.8), value: showHelix)
                    .padding(.bottom, 24)

                // Old archetype → New archetype
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(_archetypeLabel(event.oldArchetypeKey))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Text(_archetypeTagline(event.oldArchetypeKey))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray.opacity(0.55))
                            .italic()
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .font(.title2.weight(.black))
                        .foregroundColor(newAccent)
                        .layoutPriority(1)

                    VStack(spacing: 4) {
                        Text(event.dna.archetype.label)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                            .multilineTextAlignment(.center)
                        Text(event.dna.archetype.tagline)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(newAccent)
                            .italic()
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)

                // Why explanation
                Text(_whyExplanation(for: newKey))
                    .font(.appBody)
                    .foregroundColor(Color.appTextPrimary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Spacer()

                // CTAs
                VStack(spacing: 12) {
                    Button {
                        appState.pendingDeepLink = "intelligence"
                        onDismiss()
                    } label: {
                        Text("Voir mon DNA complet")
                            .font(.appBody.weight(.bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(newAccent)
                            .cornerRadius(14)
                    }
                    .buttonStyle(SpringButtonStyle())

                    Button(action: onDismiss) {
                        Text("Fermer")
                            .font(.appBody)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear { showHelix = true }
    }
}

// MARK: - Helpers (mirrors workout_dna.py:479-488)

// Prefixed with _ to avoid collision with file-private func in WorkoutDNAView.swift
private func _archetypeAccent(_ key: String) -> Color {
    switch key {
    case "powerlifter": return Color(red: 0.31, green: 0.43, blue: 0.97)
    case "bodybuilder":  return Color(red: 0.98, green: 0.45, blue: 0.09)
    case "grinder":      return Color(red: 0.13, green: 0.77, blue: 0.37)
    case "warrior":      return Color(red: 0.66, green: 0.33, blue: 0.97)
    case "athlete":      return Color(red: 0.08, green: 0.72, blue: 0.64)
    default:             return Color(red: 0.37, green: 0.63, blue: 0.98)
    }
}

private func _archetypeLabel(_ key: String) -> String {
    switch key {
    case "powerlifter": return "The Powerlifter"
    case "bodybuilder":  return "The Bodybuilder"
    case "grinder":      return "The Grinder"
    case "warrior":      return "Weekend Warrior"
    case "athlete":      return "The Athlete"
    default:             return "The Builder"
    }
}

private func _archetypeTagline(_ key: String) -> String {
    switch key {
    case "powerlifter": return "Compound. Heavy. Consistent."
    case "bodybuilder":  return "Volume. Symmetry. Discipline."
    case "grinder":      return "Never misses. Never quits."
    case "warrior":      return "Rare but fierce."
    case "athlete":      return "Balanced. Efficient. Sharp."
    default:             return "Building, day by day."
    }
}

private func _whyExplanation(for key: String) -> String {
    switch key {
    case "powerlifter":
        return "Tes séances composées lourdes et ta régularité ont basculé ton profil."
    case "bodybuilder":
        return "Ton volume de jambes et ta constance définissent maintenant ton entraînement."
    case "grinder":
        return "4+ séances par semaine sans jamais dérailler. La constance est devenue ta signature."
    case "warrior":
        return "Rare mais intense — tes séances peu fréquentes mais lourdes parlent d'elles-mêmes."
    case "athlete":
        return "Équilibre push/pull/legs, intensité modérée, constance solide : profil d'athlète fonctionnel."
    default:
        return "Ton DNA se précise. Les bases sont en place — la suite se construit sur elles."
    }
}
