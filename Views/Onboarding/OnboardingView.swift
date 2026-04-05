import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var name = ""
    @State private var sex = "M"
    @State private var age = 25
    @State private var weightKg = 75.0
    @State private var height = 175
    @State private var goal = "Prise de masse"
    @State private var level = "Intermédiaire"
    @State private var isSaving = false

    @ObservedObject private var units = UnitSettings.shared

    private let goals  = ["Prise de masse", "Perte de poids", "Performance", "Maintien"]
    private let levels = ["Débutant", "Intermédiaire", "Avancé"]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var displayWeight: String {
        units.isKg
            ? String(format: "%.1f kg",  weightKg)
            : String(format: "%.1f lbs", weightKg * 2.20462)
    }

    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Header ─────────────────────────────────────────────
                    VStack(spacing: 10) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 56))
                            .foregroundColor(.orange)
                            .padding(.top, 64)

                        Text("Bienvenue sur\nTrainingOS")
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Text("2 minutes pour personnaliser\nton expérience d'entraînement.")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 40)

                    // ── Identité ───────────────────────────────────────────
                    OnboardingCard(title: "IDENTITÉ") {
                        OnboardingRow(label: "Prénom") {
                            TextField("Ex: Vincent", text: $name)
                                .foregroundColor(.white)
                                .tint(.orange)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                        }
                        OBDivider()
                        OnboardingRow(label: "Sexe") {
                            Picker("", selection: $sex) {
                                Text("Homme").tag("M")
                                Text("Femme").tag("F")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        OBDivider()
                        OnboardingRow(label: "Âge") {
                            OBStepper(value: $age, unit: "ans", min: 10, max: 100)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    // ── Mesures ────────────────────────────────────────────
                    OnboardingCard(title: "MESURES") {
                        OnboardingRow(label: "Poids (\(units.label))") {
                            HStack(spacing: 16) {
                                Button {
                                    let step = units.isKg ? 0.5 : 1.0
                                    let minW  = units.isKg ? 30.0 : 30.0 * 2.20462
                                    let cur   = units.isKg ? weightKg : weightKg * 2.20462
                                    if cur - step >= minW {
                                        weightKg = units.isKg
                                            ? weightKg - step
                                            : (cur - step) / 2.20462
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill").font(.system(size: 28)).foregroundColor(.orange)
                                }
                                Text(displayWeight)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 90, alignment: .center)
                                Button {
                                    let step = units.isKg ? 0.5 : 1.0
                                    let maxW  = units.isKg ? 300.0 : 300.0 * 2.20462
                                    let cur   = units.isKg ? weightKg : weightKg * 2.20462
                                    if cur + step <= maxW {
                                        weightKg = units.isKg
                                            ? weightKg + step
                                            : (cur + step) / 2.20462
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 28)).foregroundColor(.orange)
                                }
                            }
                        }
                        OBDivider()
                        OnboardingRow(label: "Taille (cm)") {
                            OBStepper(value: $height, unit: "cm", min: 100, max: 250)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    // ── Programme ──────────────────────────────────────────
                    OnboardingCard(title: "PROGRAMME") {
                        OnboardingRow(label: "Objectif") {
                            Menu {
                                ForEach(goals, id: \.self) { g in
                                    Button(g) { goal = g }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(goal)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.orange)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        OBDivider()
                        OnboardingRow(label: "Niveau") {
                            Menu {
                                ForEach(levels, id: \.self) { l in
                                    Button(l) { level = l }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(level)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.orange)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)

                    // ── Validation hint ────────────────────────────────────
                    if !isValid {
                        Text("Entre ton prénom pour continuer")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .padding(.bottom, 10)
                    }

                    // ── CTA ────────────────────────────────────────────────
                    Button(action: submit) {
                        HStack(spacing: 10) {
                            if isSaving {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            }
                            Text(isSaving ? "Enregistrement…" : "Commencer →")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(isValid ? Color.orange : Color.gray.opacity(0.3))
                        .cornerRadius(16)
                    }
                    .disabled(!isValid || isSaving)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 56)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // ── Submit ─────────────────────────────────────────────────────────────────

    private func submit() {
        guard isValid else { return }
        isSaving = true
        Task {
            do {
                try await APIService.shared.updateProfile(
                    name:   name.trimmingCharacters(in: .whitespaces),
                    weight: weightKg,
                    height: Double(height),
                    age:    age,
                    goal:   goal,
                    level:  level,
                    sex:    sex
                )
            } catch {
                // Network failure: profile syncs later via SyncManager
            }
            await MainActor.run { onComplete() }
        }
    }
}

// MARK: - Sub-components

private struct OnboardingCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)
                .padding(.leading, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content
            }
            .background(Color(hex: "11111c"))
            .cornerRadius(14)
        }
    }
}

private struct OnboardingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.white)
            Spacer()
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct OBDivider: View {
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.06))
            .padding(.horizontal, 16)
    }
}

private struct OBStepper: View {
    @Binding var value: Int
    let unit: String
    let min: Int
    let max: Int

    var body: some View {
        HStack(spacing: 16) {
            Button {
                if value > min { value -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
            }
            Text("\(value) \(unit)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 80, alignment: .center)
            Button {
                if value < max { value += 1 }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
            }
        }
    }
}
