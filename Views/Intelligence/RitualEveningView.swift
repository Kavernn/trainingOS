import SwiftUI

struct RitualEveningView: View {
    let ritual: RitualToday
    let onSaved: (RitualToday) -> Void

    private enum EveningStep { case judgment, intention }

    @State private var step             : EveningStep = .judgment
    @State private var pendingOutcome   : String?     = nil
    @State private var isSaving         = false
    @State private var showResult       = false
    @State private var result           : RitualEveningResult? = nil
    @State private var flashOpacity     : Double = 0
    @State private var reflection       = ""
    @State private var tomorrowIntention = ""
    @FocusState private var reflectionFocused: Bool
    @FocusState private var intentionFocused : Bool
    @State private var winddownDone     = false
    @State private var coldDone         = false

    private let red   = Color(hex: "FF2D20")

    // E7: format morning_at time
    private var morningTimeLabel: String? {
        guard let iso = ritual.morningAt else { return nil }
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

    private var tomorrowDateLabel: String {
        let cal  = Calendar.current
        let tmrw = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let fmt  = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.dateFormat = "EEEE d MMMM"
        return fmt.string(from: tmrw).capitalized
    }

    var body: some View {
        ZStack {
            // Fond qui change entre les deux étapes
            Group {
                if step == .judgment {
                    Color(hex: "0A0A0A")
                } else {
                    Color(hex: "0D0906")   // légèrement plus chaud pour l'étape 2
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: step)

            Color(hex: "FF2D20")
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)

            if showResult, let r = result {
                resultView(r)
                    .transition(.opacity)
            } else if step == .intention {
                intentionView
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .opacity
                    ))
            } else {
                choiceView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showResult)
        .animation(.easeInOut(duration: 0.45), value: step)
        .onTapGesture {
            reflectionFocused = false
            intentionFocused  = false
        }
    }

    // MARK: - Étape 1 : Jugement

    private var choiceView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 40)

                if let t = morningTimeLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.2))
                        Text("Déclaré ce matin à \(t)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.2))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                VStack(alignment: .leading, spacing: 24) {
                    // Intention reminder
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CE MATIN TU AVAIS DIT")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(3)
                            .foregroundColor(Color(white: 0.28))

                        Text("«\u{202F}\(ritual.intention ?? "")\u{202F}»")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("— \(ritual.truth)")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.28))
                            .padding(.top, 2)
                    }

                    Rectangle()
                        .fill(Color(white: 0.08))
                        .frame(height: 1)

                    // E6: reflection field
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CE QUI A FAIT LA DIFFÉRENCE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(3)
                            .foregroundColor(Color(white: 0.28))

                        TextField("Optionnel — une phrase, une observation...", text: $reflection, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundColor(Color(white: 0.65))
                            .tint(red)
                            .lineLimit(3)
                            .focused($reflectionFocused)

                        Rectangle()
                            .fill(Color(white: 0.10))
                            .frame(height: 1)
                    }

                    // Evening micro-rituals (D)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SOIR")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(3)
                            .foregroundColor(Color(white: 0.28))

                        HStack(spacing: 10) {
                            MicroCheckButton(
                                label: "Wind-down",
                                icon: "moon.zzz.fill",
                                isOn: winddownDone
                            ) { winddownDone.toggle() }

                            MicroCheckButton(
                                label: "Cold",
                                icon: "thermometer.snowflake",
                                isOn: coldDone
                            ) { coldDone.toggle() }
                        }
                    }

                    Rectangle()
                        .fill(Color(white: 0.08))
                        .frame(height: 1)

                    // Verdict
                    VStack(alignment: .leading, spacing: 20) {
                        Text("EST-CE QUE TU L'AS TUÉ ?")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(3)
                            .foregroundColor(Color(white: 0.28))

                        HStack(spacing: 12) {
                            choiceButton(emoji: "🔥", label: "BURNED\nIT", outcome: "burned")
                            choiceButton(emoji: "💀", label: "SURVIVED", outcome: "survived")
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func choiceButton(emoji: String, label: String, outcome: String) -> some View {
        let isSelected = pendingOutcome == outcome
        return Button(action: { advanceToIntention(outcome: outcome) }) {
            VStack(spacing: 10) {
                Text(emoji).font(.system(size: 40))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundColor(isSelected ? .white : Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Color(white: isSelected ? 0.12 : 0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color(white: 0.3) : Color(white: 0.1), lineWidth: 1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    // MARK: - Étape 2 : Intention pour demain

    private var intentionView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 48)

                VStack(alignment: .leading, spacing: 28) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MAINTENANT")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(3)
                            .foregroundColor(Color.forge.opacity(0.7))

                        Text("Ton intention pour demain")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Pour \(tomorrowDateLabel)")
                            .font(.system(size: 13))
                            .foregroundColor(Color(white: 0.38))
                    }

                    Rectangle()
                        .fill(Color.forge.opacity(0.15))
                        .frame(height: 1)

                    // Champ intention
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Demain, je m'engage à...", text: $tomorrowIntention, axis: .vertical)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.white)
                            .tint(Color.forge)
                            .lineLimit(5)
                            .focused($intentionFocused)
                            .onAppear { intentionFocused = true }

                        Rectangle()
                            .fill(tomorrowIntention.isEmpty ? Color(white: 0.12) : Color.forge.opacity(0.4))
                            .frame(height: 1)
                            .animation(.easeInOut(duration: 0.2), value: tomorrowIntention.isEmpty)
                    }

                    // CTA
                    VStack(spacing: 12) {
                        Button(action: { commitWithIntention() }) {
                            HStack {
                                Text("Prendre cet engagement")
                                    .font(.system(size: 15, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                tomorrowIntention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.forge.opacity(0.35)
                                    : Color.forge
                            )
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)

                        Button(action: { commitWithoutIntention() }) {
                            Text("Passer pour ce soir")
                                .font(.system(size: 13))
                                .foregroundColor(Color(white: 0.35))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Result view

    private func resultView(_ r: RitualEveningResult) -> some View {
        VStack(spacing: 0) {
            Spacer()
            if r.outcome == "burned" {
                burnedResultContent(r)
            } else {
                survivedResultContent
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func burnedResultContent(_ r: RitualEveningResult) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "flame.fill")
                .font(.system(size: 48))
                .foregroundColor(Color.forge)

            VStack(spacing: 6) {
                Text("\(r.phoenixStreak)")
                    .font(.system(size: 72, weight: .black))
                    .foregroundColor(.white)
                Text("PHOENIX STREAK")
                    .font(.system(size: 12, weight: .black))
                    .tracking(4)
                    .foregroundColor(Color(white: 0.3))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.08)).frame(height: 3)
                    Capsule()
                        .fill(Color.forge)
                        .frame(width: geo.size.width, height: 3)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading),
                            removal: .opacity
                        ))
                }
            }
            .frame(height: 3)

            Text("\(r.phoenixTotalBurned) intentions tuées au total")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.28))

            if r.intentionMatchedSession {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("Intention honorée en séance")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.35))
                }
            }
        }
    }

    private var survivedResultContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "moon.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.3))

            VStack(spacing: 8) {
                Text("It's still there.")
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(.white)
                Text("Tomorrow you go again.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.3))
            }

            if result?.phoenixStreak == 0 && (result?.outcome == "survived") == true {
                Text("Streak remis à zéro.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.2))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Actions

    private func advanceToIntention(outcome: String) {
        guard !isSaving else { return }
        reflectionFocused = false
        pendingOutcome    = outcome
        withAnimation { step = .intention }
    }

    private func commitWithIntention() {
        let text = tomorrowIntention.trimmingCharacters(in: .whitespacesAndNewlines)
        commit(tomorrowIntention: text.isEmpty ? nil : text)
    }

    private func commitWithoutIntention() {
        commit(tomorrowIntention: nil)
    }

    private func commit(tomorrowIntention: String?) {
        guard let outcome = pendingOutcome, !isSaving else { return }
        isSaving         = true
        intentionFocused = false

        Task {
            do {
                let r = try await APIService.shared.saveRitualEveningFull(
                    outcome:           outcome,
                    reflection:        reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reflection,
                    winddownDone:      winddownDone ? true : nil,
                    coldDone:          coldDone ? true : nil,
                    tomorrowIntention: tomorrowIntention
                )
                await showEveningResult(r, outcome: outcome)
            } catch APIError.queuedOffline {
                let synthetic = RitualEveningResult(
                    ok: true, outcome: outcome,
                    phoenixStreak: 0, phoenixBest: 0, phoenixTotalBurned: 0,
                    intentionMatchedSession: false
                )
                await showEveningResult(synthetic, outcome: outcome)
            } catch {
                await MainActor.run {
                    pendingOutcome = nil
                    isSaving       = false
                }
            }
        }
    }

    private func showEveningResult(_ r: RitualEveningResult, outcome: String) async {
        if outcome == "burned" {
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.15)) { flashOpacity = 0.6 }
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        } else {
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) { flashOpacity = 0.0 }
            }
        }
        await MainActor.run {
            result     = r
            showResult = true
            isSaving   = false
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if let updated = try? await APIService.shared.fetchRitualToday() {
            await MainActor.run { onSaved(updated) }
        }
    }
}

// MARK: - Micro Check Button

private struct MicroCheckButton: View {
    let label: String
    let icon: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "\(icon)" : icon)
                    .font(.system(size: 12))
                    .foregroundColor(isOn ? .white : Color(white: 0.35))
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(isOn ? .white : Color(white: 0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn ? Color(white: 0.15) : Color(white: 0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? Color(white: 0.3) : Color(white: 0.1), lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
