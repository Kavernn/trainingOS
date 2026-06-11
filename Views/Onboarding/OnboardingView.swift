import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var goal = "Prise de masse"
    @State private var isSaving    = false
    @State private var hkRequesting = false
    @State private var isKgSelected: Bool = Locale.current.usesMetricSystem

    @State private var sexInput: String    = "M"
    @State private var heightInput: Int    = 175
    @State private var weightInput: Double = 75.0

    private let level = "Intermédiaire"

    private let goalOptions: [(label: String, subtitle: String, value: String)] = [
        ("Prendre du muscle",   "Force & hypertrophie",      "Prise de masse"),
        ("Perdre du gras",      "Composition corporelle",    "Perte de poids"),
        ("Performer",           "Force, vitesse, endurance", "Performance"),
        ("Rester consistant",   "Habitudes durables",        "Maintien"),
    ]

    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var weightKg: Double {
        isKgSelected ? weightInput : weightInput * 0.453592
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            Group {
                if step == 0 { splashStep.transition(.asymmetric(insertion: .opacity, removal: .opacity)) }
                if step == 1 { goalStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 2 { nameStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 3 { profileStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 4 { unitsStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if step == 5 { healthKitStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
            }
            .animation(.easeInOut(duration: 0.3), value: step)
        }
        .overlay(alignment: .topTrailing) {
            // Units step (4) is mandatory — no skip. HealthKit (5) has its own skip button.
            if step < 4 {
                Button("Passer") { onComplete() }
                    .font(.appLabel)
                    .foregroundColor(Color(white: 0.4))
                    .padding(.trailing, 20)
                    .padding(.top, 56)
            }
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
                    .font(.appBody)
                    .foregroundColor(Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button { withAnimation { step = 1 } } label: {
                Text("Commencer →")
                    .font(.appHeadline).fontWeight(.bold)
                    .foregroundColor(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.forge)
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
                    .font(.appBody)
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
                                    .font(.appHeadline)
                                    .foregroundColor(.white)
                                Text(option.subtitle)
                                    .font(.appLabel).fontWeight(.regular)
                                    .foregroundColor(Color(white: 0.45))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.appLabel).fontWeight(.semibold)
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
                    .font(.appBody)
                    .foregroundColor(Color(white: 0.45))
            }
            .padding(.bottom, 48)

            TextField("Ex: Vincent", text: $name)
                .font(.appTitle).fontWeight(.semibold)
                .foregroundColor(.white)
                .tint(Color.forge)
                .multilineTextAlignment(.center)
                .autocorrectionDisabled()
                .padding(.vertical, 22)
                .background(Color(white: 0.08))
                .cornerRadius(14)
                .padding(.horizontal, 24)

            Spacer()

            Button { withAnimation { step = 3 } } label: {
                Text("Continuer →")
                    .font(.appHeadline).fontWeight(.bold)
                    .foregroundColor(isNameValid ? Color.onAccent : Color(white: 0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(isNameValid ? Color.forge : Color(white: 0.18))
                    .cornerRadius(16)
            }
            .disabled(!isNameValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
    }

    // MARK: Step 3 — Profile

    private var profileStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Ton profil\nphysique")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 80)
                Text("Pour calibrer tes calories, readiness\net recommandations de charge.")
                    .font(.appBody)
                    .foregroundColor(Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 44)

            VStack(spacing: 14) {
                // Sex
                HStack(spacing: 12) {
                    profileToggleButton(label: "Homme", selected: sexInput == "M") { sexInput = "M" }
                    profileToggleButton(label: "Femme",  selected: sexInput == "F") { sexInput = "F" }
                }

                // Height
                VStack(alignment: .leading, spacing: 8) {
                    Text("TAILLE")
                        .font(.appCaption.weight(.bold)).tracking(2)
                        .foregroundColor(.gray)
                    HStack {
                        Text("\(heightInput) cm")
                            .font(.appTitle.weight(.black))
                            .foregroundColor(.white)
                        Spacer()
                        Stepper("", value: $heightInput, in: 140...220)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color(white: 0.08)).cornerRadius(12)
                }

                // Weight
                VStack(alignment: .leading, spacing: 8) {
                    Text("POIDS")
                        .font(.appCaption.weight(.bold)).tracking(2)
                        .foregroundColor(.gray)
                    HStack {
                        Text(String(format: "%.1f %@", weightInput, isKgSelected ? "kg" : "lbs"))
                            .font(.appTitle.weight(.black))
                            .foregroundColor(.white)
                        Spacer()
                        Stepper("", value: $weightInput, in: 30...300, step: 0.5)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color(white: 0.08)).cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: submit) {
                HStack(spacing: 10) {
                    if isSaving { ProgressView().tint(Color.onAccent).scaleEffect(0.85) }
                    Text(isSaving ? "Préparation…" : "Continuer →")
                        .font(.appHeadline).fontWeight(.bold)
                }
                .foregroundColor(Color.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.forge)
                .cornerRadius(16)
            }
            .disabled(isSaving)
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
    }

    private func profileToggleButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.appHeadline).fontWeight(.bold)
                .foregroundColor(selected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(selected ? Color.forge : Color(white: 0.1))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.forge : Color(white: 0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 4 — Units

    private var unitsStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Tu t'entraînes\nen kg ou en lbs ?")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 80)
                Text("Toutes tes charges seront affichées\ndans cette unité.")
                    .font(.appBody)
                    .foregroundColor(Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 52)

            HStack(spacing: 16) {
                unitButton(label: "KG", selected: isKgSelected) {
                    isKgSelected = true
                    UnitSettings.shared.isKg = true
                    withAnimation { step = 5 }
                }
                unitButton(label: "LBS", selected: !isKgSelected) {
                    isKgSelected = false
                    UnitSettings.shared.isKg = false
                    withAnimation { step = 5 }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func unitButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 28, weight: .black))
                .foregroundColor(selected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(selected ? Color.forge : Color(white: 0.1))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(selected ? Color.forge : Color(white: 0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 4 — HealthKit

    private var healthKitStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.12)).frame(width: 90, height: 90)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(.red)
                }
                VStack(spacing: 10) {
                    Text("Récupération auto")
                        .font(.system(size: 34, weight: .black))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text("Connecte Apple Santé pour importer\nautomatiquement ton sommeil, HRV\net tes calories brûlées.")
                        .font(.appBody)
                        .foregroundColor(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    hkRequesting = true
                    Task {
                        await HealthKitService.shared.requestAuthorization()
                        await MainActor.run { onComplete() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if hkRequesting { ProgressView().tint(.black).scaleEffect(0.85) }
                        Text(hkRequesting ? "Connexion…" : "Connecter Apple Santé →")
                            .font(.appHeadline).fontWeight(.bold)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.red)
                    .cornerRadius(16)
                }
                .disabled(hkRequesting)

                Button("Passer pour l'instant") { onComplete() }
                    .font(.appBody)
                    .foregroundColor(Color(white: 0.4))
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
    }

    // MARK: Submit

    private func submit() {
        isSaving = true
        Task {
            do {
                try await APIService.shared.updateProfile(
                    name:   name.trimmingCharacters(in: .whitespaces),
                    weight: weightKg,
                    height: Double(heightInput),
                    age:    25,
                    goal:   goal,
                    level:  level,
                    sex:    sexInput
                )
            } catch {
                // Network failure: profile syncs later via SyncManager
            }
            await MainActor.run {
                isSaving = false
                withAnimation { step = 4 }
            }
        }
    }
}

// MARK: - HRV Onboarding Sheet (3 écrans)

struct HRVOnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0
    private let totalPages  = 3

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            Circle()
                .fill(pageAccent.opacity(0.08))
                .frame(width: 340, height: 340)
                .blur(radius: 60)
                .offset(y: -80)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Passer") { finish() }
                        .font(.appLabel)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                }

                Spacer()

                Group {
                    switch page {
                    case 0: onbPage1
                    case 1: onbPage2
                    default: onbPage3
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(page)

                Spacer()

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
                                .font(.appBody).fontWeight(.bold)
                            Image(systemName: "arrow.right")
                                .font(.appLabel).fontWeight(.bold)
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

    private var onbPage1: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(pageAccent.opacity(0.12)).frame(width: 100, height: 100)
                Image(systemName: "waveform.path.ecg").font(.system(size: 44)).foregroundColor(pageAccent)
            }
            VStack(spacing: 12) {
                Text("C'est quoi le HRV ?")
                    .font(.system(size: 26, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center)
                Text("La variabilité de ton rythme cardiaque révèle l'état réel de ton système nerveux — plus fiable que ton ressenti subjectif.")
                    .font(.appBody).foregroundColor(.gray).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                HRVFactChip(icon: "applewatch",                 text: "Apple Watch",    color: pageAccent)
                HRVFactChip(icon: "chart.line.uptrend.xyaxis", text: "Score personnel", color: pageAccent)
            }
        }
        .padding(.horizontal, 32)
    }

    private var onbPage2: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(pageAccent.opacity(0.12)).frame(width: 100, height: 100)
                Image(systemName: "bed.double.fill").font(.system(size: 40)).foregroundColor(pageAccent)
            }
            VStack(spacing: 12) {
                Text("Le protocole du matin")
                    .font(.system(size: 26, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center)
                Text("Chaque matin, avant de te lever :")
                    .font(.appBody).foregroundColor(.gray)
            }
            VStack(alignment: .leading, spacing: 10) {
                HRVProtocolStep(number: 1, icon: "sun.rise.fill",   text: "Réveille-toi naturellement",         color: pageAccent)
                HRVProtocolStep(number: 2, icon: "bed.double.fill", text: "Reste allongé — ne te lève pas encore", color: pageAccent)
                HRVProtocolStep(number: 3, icon: "wind",            text: "Respire normalement",                color: pageAccent)
                HRVProtocolStep(number: 4, icon: "timer",           text: "Attends environ 60 secondes",        color: pageAccent)
                HRVProtocolStep(number: 5, icon: "iphone",          text: "Ouvre VinceSeven — ta mesure est prête", color: pageAccent)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 32)
    }

    private var onbPage3: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(pageAccent.opacity(0.12)).frame(width: 100, height: 100)
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 40)).foregroundColor(pageAccent)
            }
            VStack(spacing: 12) {
                Text("L'app fait le reste")
                    .font(.system(size: 26, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center)
                Text("Ton Apple Watch collecte en arrière-plan pendant le sommeil. VinceSeven calcule ton score personnalisé chaque matin — rien d'autre à faire.")
                    .font(.appBody).foregroundColor(.gray).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                HRVAutoFeatureRow(icon: "circle.fill", color: .green,  text: "Score vert — séance à 100%")
                HRVAutoFeatureRow(icon: "circle.fill", color: Color.forge, text: "Score orange — surveille la fatigue")
                HRVAutoFeatureRow(icon: "circle.fill", color: .red,    text: "Score rouge — récupération d'abord")
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 32)
    }

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

private struct HRVFactChip: View {
    let icon: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.appCaption).foregroundColor(color)
            Text(text).font(.appCaption).fontWeight(.medium).foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.white.opacity(0.07)).cornerRadius(20)
    }
}

private struct HRVProtocolStep: View {
    let number: Int; let icon: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.appBody).foregroundColor(color)
            }
            Text(text).font(.appBody).foregroundColor(.white.opacity(0.9))
            Spacer()
        }
    }
}

private struct HRVAutoFeatureRow: View {
    let icon: String; let color: Color; let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.appMicro).foregroundColor(color)
            Text(text).font(.appLabel).fontWeight(.regular).foregroundColor(.white.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.white.opacity(0.05)).cornerRadius(10)
    }
}
