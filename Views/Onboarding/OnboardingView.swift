import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var goal = "Prise de masse"
    @State private var isSaving = false

    // Defaults — user updates later in Profile
    private let sex      = "M"
    private let age      = 25
    private let weightKg = 75.0
    private let height   = 175
    private let level    = "Intermédiaire"

    private let goalOptions: [(label: String, subtitle: String, value: String)] = [
        ("Prendre du muscle",   "Force & hypertrophie",      "Prise de masse"),
        ("Perdre du gras",      "Composition corporelle",    "Perte de poids"),
        ("Performer",           "Force, vitesse, endurance", "Performance"),
        ("Rester consistant",   "Habitudes durables",        "Maintien"),
    ]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if step == 0 { splashStep.transition(.asymmetric(insertion: .opacity, removal: .opacity)) }
                if step == 1 { goalStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 2 { nameStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
            }
            .animation(.easeInOut(duration: 0.3), value: step)
        }
        .overlay(alignment: .topTrailing) {
            Button("Passer") { onComplete() }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(white: 0.4))
                .padding(.trailing, 20)
                .padding(.top, 56)
        }
    }

    // MARK: Step 0 — Brand

    private var splashStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Text("Ton coach.\nTon avantage.")
                    .font(.system(size: 42, weight: .black))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text("Un entraînement intelligent,\nadapté à ce que tu es aujourd'hui.")
                    .font(.system(size: 16))
                    .foregroundColor(Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button { withAnimation { step = 1 } } label: {
                Text("Commencer →")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.orange)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
    }

    // MARK: Step 1 — Goal

    private var goalStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Quel est ton\nobjectif ?")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 80)
                Text("Ton coach adapte tout à partir de là.")
                    .font(.system(size: 15))
                    .foregroundColor(Color(white: 0.45))
            }
            .padding(.bottom, 44)

            VStack(spacing: 12) {
                ForEach(goalOptions, id: \.value) { option in
                    Button {
                        goal = option.value
                        withAnimation { step = 2 }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.label)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(option.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(white: 0.45))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(white: 0.25))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(Color(white: 0.08))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: Step 2 — Name

    private var nameStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Comment\nt'appelle-tu ?")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 80)
                Text("Ton coach va te parler par ton prénom.")
                    .font(.system(size: 15))
                    .foregroundColor(Color(white: 0.45))
            }
            .padding(.bottom, 48)

            TextField("Ex: Vincent", text: $name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .tint(.orange)
                .multilineTextAlignment(.center)
                .autocorrectionDisabled()
                .padding(.vertical, 22)
                .background(Color(white: 0.08))
                .cornerRadius(14)
                .padding(.horizontal, 24)

            Spacer()

            Button(action: submit) {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView().tint(.black).scaleEffect(0.85)
                    }
                    Text(isSaving ? "Préparation…" : "Rencontrer mon coach →")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(isValid ? Color.orange : Color(white: 0.18))
                .cornerRadius(16)
            }
            .disabled(!isValid || isSaving)
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
    }

    // MARK: Submit

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
