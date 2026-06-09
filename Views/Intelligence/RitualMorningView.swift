import SwiftUI

struct RitualMorningView: View {
    let ritual: RitualToday
    let onSaved: (RitualToday) -> Void

    @State private var intention       = ""
    @State private var isSaving        = false
    @State private var useCarried      = false
    @FocusState private var focused: Bool

    // D: micro-ritual checklist local state (mirrors ritual values on appear)
    @State private var hydrationDone   = false
    @State private var mobilityDone    = false
    @State private var proteinDone     = false
    @State private var showSpirit      = false
    @State private var isKillingDemon  = false

    // Phase 1 matin — jugement de l'intention d'hier soir
    @State private var morningAck      : Bool? = nil
    @State private var ackFeedbackDone = false

    private let red   = Color(hex: "FF2D20")

    private var hasDemon: Bool { ritual.carriedIntention != nil }

    private var yesterdayEveningTimeLabel: String? {
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
        ZStack {
            Color(hex: "0A0A0A").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    timeLabel
                        .padding(.top, 60)
                        .padding(.horizontal, 24)

                    if let intention = ritual.yesterdayIntention {
                        yesterdayIntentionCard(intention: intention)
                            .padding(.top, 20)
                            .padding(.horizontal, 24)

                        if !ackFeedbackDone {
                            morningAckBlock
                                .padding(.top, 16)
                                .padding(.horizontal, 24)
                        }
                    }

                    truthBlock
                        .padding(.top, 32)
                        .padding(.horizontal, 24)

                    if let demon = ritual.carriedIntention, !useCarried {
                        demonBanner(demon)
                            .padding(.top, 20)
                            .padding(.horizontal, 24)
                    }

                    // D: morning micro-ritual checklist
                    checklistSection
                        .padding(.top, 24)

                    intentionSection
                        .padding(.top, 28)
                        .padding(.horizontal, 24)

                    // G4: Void shortcut — subtle link before declaring war
                    voidShortcut
                        .padding(.top, 20)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 120)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            VStack {
                Spacer()
                declareWarButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showSpirit) { SpiritView() }
        .onAppear {
            if let demon = ritual.carriedIntention {
                intention  = demon
                useCarried = true
            }
            // Mirror saved checklist state
            hydrationDone = ritual.hydrationDone
            mobilityDone  = ritual.mobilityDone
            proteinDone   = ritual.proteinDone
            // Restore morningAck from API — si déjà répondu, cacher le bloc
            if let saved = ritual.morningAck {
                morningAck      = saved
                ackFeedbackDone = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true }
            // B3: schedule streak at risk if applicable
            NotificationService.scheduleRitualStreakAtRisk(
                morningDone: ritual.morningDone,
                phoenixStreak: ritual.phoenixStreak
            )
        }
    }

    // MARK: - Components

    private func yesterdayIntentionCard(intention: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sunset.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color.forge.opacity(0.7))
                Text("TON ENGAGEMENT D'HIER SOIR")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(Color.forge.opacity(0.7))
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)

            Text("«\u{202F}\(intention)\u{202F}»")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 14)

            HStack(spacing: 6) {
                let timeStr = yesterdayEveningTimeLabel.map { "Hier soir · \($0)" } ?? "Hier soir"
                Text(timeStr)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.28))

                Spacer()

                if let outcome = ritual.yesterdayOutcome {
                    if outcome == "burned" {
                        Label("Tu as brûlé hier", systemImage: "flame.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.forge)
                    } else {
                        Label("Tu as survécu hier", systemImage: "shield.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.35))
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Color(hex: "0E0B08"))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.forge.opacity(0.18), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private var timeLabel: some View {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return Text(fmt.string(from: Date()))
            .font(.system(size: 13))
            .foregroundColor(Color(white: 0.25))
    }

    private var truthBlock: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(red)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(ritual.truth)
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if !ritual.date.isEmpty {
                    Text(ritual.date)
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.28))
                }
            }
            .padding(.leading, 16)
            .padding(.vertical, 12)
        }
    }

    private func demonBanner(_ demon: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.4))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Il est encore là depuis \(ritual.carryCount) jour\(ritual.carryCount > 1 ? "s" : "")")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.3))
                    Text("\"\(demon)\"")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color(white: 0.1))
                .frame(height: 1)
                .padding(.horizontal, 14)

            HStack(spacing: 0) {
                Button(action: {
                    intention  = demon
                    useCarried = true
                }) {
                    Text("Reprendre →")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(white: 0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(Color(white: 0.1))
                    .frame(width: 1, height: 36)

                Button(action: { killCarriedDemon() }) {
                    Group {
                        if isKillingDemon {
                            ProgressView().tint(red).scaleEffect(0.7)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 11))
                                Text("Tuer")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(red.opacity(0.75))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(isKillingDemon)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        .background(Color(white: 0.06))
        .cornerRadius(10)
    }

    private func killCarriedDemon() {
        guard let demonDate = ritual.carriedFrom, !isKillingDemon else { return }
        isKillingDemon = true
        Task {
            do {
                try await APIService.shared.killDemon(date: demonDate)
                if let updated = try? await APIService.shared.fetchRitualToday() {
                    await MainActor.run { onSaved(updated) }
                }
            } catch { }
            await MainActor.run { isKillingDemon = false }
        }
    }

    // D: Morning micro-ritual checklist
    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CE MATIN")
                .font(.system(size: 10, weight: .bold))
                .tracking(3)
                .foregroundColor(Color(white: 0.28))
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChecklistChip(
                        label: "Hydratation",
                        icon: "drop.fill",
                        isOn: hydrationDone
                    ) { toggle in
                        hydrationDone = toggle
                        Task { try? await APIService.shared.saveRitualChecklist(hydrationDone: toggle) }
                    }

                    ChecklistChip(
                        label: "Mobilité",
                        icon: "figure.flexibility",
                        isOn: mobilityDone
                    ) { toggle in
                        mobilityDone = toggle
                        Task { try? await APIService.shared.saveRitualChecklist(mobilityDone: toggle) }
                    }

                    ChecklistChip(
                        label: "Protéines",
                        icon: "fork.knife",
                        isOn: proteinDone
                    ) { toggle in
                        proteinDone = toggle
                        Task { try? await APIService.shared.saveRitualChecklist(proteinDone: toggle) }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var intentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DÉCLARE TA GUERRE")
                .font(.system(size: 10, weight: .bold))
                .tracking(3)
                .foregroundColor(Color(white: 0.28))

            TextField("Aujourd'hui je...", text: $intention, axis: .vertical)
                .font(.system(size: 18))
                .foregroundColor(.white)
                .tint(red)
                .lineLimit(3)
                .focused($focused)
                .onChange(of: intention) { if useCarried && intention != ritual.carriedIntention { useCarried = false } }

            Rectangle()
                .fill(Color(white: 0.12))
                .frame(height: 1)
        }
    }

    // G4: optional Void session before declaring war
    private var voidShortcut: some View {
        Button { showSpirit = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "wind")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.25))
                Text("Se préparer dans The Void d'abord")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.25))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.18))
            }
        }
        .buttonStyle(.plain)
    }

    private var declareWarButton: some View {
        Button(action: save) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSaving ? red.opacity(0.5) : red)
                    .frame(height: 54)
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("DECLARE WAR  →")
                        .font(.system(size: 15, weight: .black))
                        .tracking(2)
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(intention.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
        .buttonStyle(.plain)
    }

    // MARK: - Phase 1 matin : jugement intention d'hier

    @ViewBuilder
    private var morningAckBlock: some View {
        if let ack = morningAck {
            Text(ack ? "Bien." : "Noté.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(ack ? Color.forge : Color(white: 0.32))
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("L'AS-TU ACCOMPLI ?")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(Color(white: 0.28))

                    if let yi = ritual.yesterdayIntention {
                        let truncated = yi.count > 55 ? String(yi.prefix(55)) + "…" : yi
                        Text("«\u{202F}\(truncated)\u{202F}»")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.28))
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 10) {
                    ackChoiceButton(label: "OUI  ✓", value: true)
                    ackChoiceButton(label: "NON  ✗", value: false)
                }
            }
            .transition(.opacity)
        }
    }

    private func ackChoiceButton(label: String, value: Bool) -> some View {
        Button(action: { recordMorningAck(value) }) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(Color(white: 0.55))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(white: 0.12), lineWidth: 1)
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func recordMorningAck(_ value: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.25)) { morningAck = value }
        Task { try? await APIService.shared.saveRitualChecklist(morningAck: value) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { ackFeedbackDone = true }
        }
    }

    // MARK: - Save

    private func save() {
        let clean = intention.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        isSaving = true
        focused  = false
        Task {
            do {
                try await APIService.shared.saveRitualMorning(
                    intention:   clean,
                    carryCount:  useCarried ? ritual.carryCount : 0,
                    carriedFrom: useCarried ? ritual.carriedFrom : nil
                )
                CacheService.shared.clear(for: "ritual_today")
                if let updated = try? await APIService.shared.fetchRitualToday() {
                    await MainActor.run { onSaved(updated) }
                }
            } catch {
                // silent retry — button re-enables
            }
            await MainActor.run { isSaving = false }
        }
    }
}

// MARK: - Checklist Chip

private struct ChecklistChip: View {
    let label: String
    let icon: String
    let isOn: Bool
    let onToggle: (Bool) -> Void

    private let red = Color(hex: "FF2D20")

    var body: some View {
        Button(action: { onToggle(!isOn) }) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 12))
                    .foregroundColor(isOn ? red : Color(white: 0.4))
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(isOn ? .white : Color(white: 0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn ? Color(white: 0.1) : Color(white: 0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? red.opacity(0.4) : Color(white: 0.1), lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
