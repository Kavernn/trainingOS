import SwiftUI

// MARK: - Manual metric kind (tap-to-enter depuis Readiness)

enum ManualMetricKind: Identifiable {
    case fatigue
    case sleepQuality

    var id: String { title }

    var title: String {
        switch self {
        case .fatigue:      return "Ressenti"
        case .sleepQuality: return "Qualité du sommeil"
        }
    }

    var subtitle: String {
        switch self {
        case .fatigue:      return "Ton niveau de fatigue perçue"
        case .sleepQuality: return "Comment tu as dormi cette nuit"
        }
    }

    // 1...10 pour les deux — évite CHECK constraint (sleep_quality 1-10 strict).
    var range: ClosedRange<Double> { 1...10 }

    var lowLabel: String {
        switch self {
        case .fatigue:      return "Frais"
        case .sleepQuality: return "Mauvaise"
        }
    }

    var highLabel: String {
        switch self {
        case .fatigue:      return "Épuisé"
        case .sleepQuality: return "Excellente"
        }
    }
}

// MARK: - Compact badge (shown on TodayCard above the button)

struct ReadinessBadge: View {
    let readiness: ReadinessResponse?

    var body: some View {
        if let r = readiness {
            HStack(spacing: 6) {
                Circle()
                    .fill(verdictColor(r.verdict))
                    .frame(width: 7, height: 7)
                Text("\(r.verdictLabel) · \(r.score)")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(verdictColor(r.verdict))
                Text("—")
                    .font(.appCaption)
                    .foregroundColor(.gray)
                Text(r.why)
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(0.70))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(verdictColor(r.verdict).opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(verdictColor(r.verdict).opacity(0.20), lineWidth: 1)
            )
            .cornerRadius(8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Readiness : \(r.verdictLabel), score \(r.score). \(r.why)")
        }
    }

    private func verdictColor(_ v: String) -> Color {
        switch v {
        case "go":       return .statusGreen
        case "moderate": return Color(red: 0.98, green: 0.76, blue: 0.15)
        default:         return .statusRed
        }
    }
}

// MARK: - Pre-session gate sheet

struct ReadinessSheet: View {
    let readiness: ReadinessResponse
    let onProceed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showGymFinder = false
    @State private var pendingMetric: ManualMetricKind? = nil

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Hero verdict ───────────────────────────────────────
                    VStack(spacing: 6) {
                        HStack(alignment: .center, spacing: 14) {
                            VerdictOrb(verdict: readiness.verdict, score: readiness.score)
                                .frame(width: 72, height: 72)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(readiness.verdictEmoji + "  " + readiness.verdictLabel)
                                    .font(.system(size: 22, weight: .black, design: .rounded))
                                    .foregroundColor(verdictColor)
                                if let session = readiness.todaySession, !session.isEmpty {
                                    Text(session)
                                        .font(.appLabel.weight(.regular))
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                        }

                        Text(readiness.why)
                            .font(.appLabel.weight(.regular))
                            .foregroundColor(Color.appOnSurface.opacity(0.80))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(verdictColor.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(verdictColor.opacity(0.18), lineWidth: 1))
                    .cornerRadius(14)

                    // ── Adjustment (if moderate or rest) ──────────────────
                    if let adj = readiness.adjustment {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lightbulb.fill")
                                .font(.appLabel.weight(.regular))
                                .foregroundColor(Color.forge)
                                .padding(.top, 1)
                            Text(adj)
                                .font(.appLabel)
                                .foregroundColor(Color.appOnSurface.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(Color.forge.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.forge.opacity(0.18), lineWidth: 1))
                        .cornerRadius(10)
                    }

                    // ── 5 module pills ─────────────────────────────────────
                    VStack(spacing: 0) {
                        SectionHeader("ANALYSE")
                        let mods = modulesArray
                        ForEach(mods.indices, id: \.self) { i in
                            let m = mods[i]
                            // Tappable ssi métrique manuelle (kind != nil) ET pas encore saisie (has_manual != true).
                            // Fail-open si backend has_manual absent (== nil) — tap ouvre le sheet, sauvegarde idempotente.
                            let isTappable = (m.kind != nil) && (m.hasManual != true)
                            ModuleRow(
                                mod: (label: m.label, score: m.score, detail: m.detail),
                                onTap: isTappable ? { pendingMetric = m.kind } : nil
                            )
                            if i < mods.count - 1 {
                                Divider().background(Color.appSeparatorSubtle).padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color.appCard)
                    .cornerRadius(14)

                    // ── Muscle recovery bars ───────────────────────────────
                    if !readiness.muscleRecovery.isEmpty {
                        VStack(spacing: 0) {
                            SectionHeader("GROUPES MUSCULAIRES")
                            let groups = readiness.muscleRecovery.sorted { $0.value.pct < $1.value.pct }
                            ForEach(groups.indices, id: \.self) { i in
                                MuscleRow(key: groups[i].key, rec: groups[i].value)
                                if i < groups.count - 1 {
                                    Divider().background(Color.appSeparatorSubtle).padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color.appCard)
                        .cornerRadius(14)
                    }

                    // ── CTA buttons ────────────────────────────────────────
                    VStack(spacing: 10) {
                        Button {
                            dismiss()
                            onProceed()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text(primaryCTALabel)
                                    .font(.appBody.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(verdictColor)
                            .foregroundColor(readiness.verdict == "moderate" ? .black : .white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(SpringButtonStyle())

                        if readiness.verdict != "go" {
                            Button {
                                dismiss()
                                onProceed()
                            } label: {
                                Text("Commencer quand même")
                                    .font(.appLabel)
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }

                        Button { showGymFinder = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.appLabel.weight(.semibold))
                                Text("Trouver un gym à proximité")
                                    .font(.appLabel)
                            }
                            .foregroundColor(Color.appOnSurface.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.appCard)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    .sheet(isPresented: $showGymFinder) {
                        GymFinderView()
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Readiness Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.appTitle.weight(.regular))
                    }
                    .accessibilityLabel("Fermer")
                }
            }
            .sheet(item: $pendingMetric) { kind in
                QuickMetricSheet(kind: kind, onSaved: { })
            }
        }
    }

    // MARK: - Helpers

    private var verdictColor: Color {
        switch readiness.verdict {
        case "go":       return .statusGreen
        case "moderate": return Color(red: 0.98, green: 0.76, blue: 0.15)
        default:         return .statusRed
        }
    }

    private var primaryCTALabel: String {
        switch readiness.verdict {
        case "go":       return "C'est parti — Go hard"
        case "moderate": return "Commencer en mode modéré"
        default:         return "Repos actif recommandé"
        }
    }

    private var modulesArray: [(label: String, score: Int?, detail: String, kind: ManualMetricKind?, hasManual: Bool?)] {
        let m = readiness.modules
        return [
            (m.hrv.label,           m.hrv.score,           m.hrv.detail,           nil,            nil),
            (m.rhr.label,           m.rhr.score,           m.rhr.detail,           nil,            nil),
            (m.acwr.label,          m.acwr.score,          m.acwr.detail,          nil,            nil),
            (m.sleepQuality.label,  m.sleepQuality.score,  m.sleepQuality.detail,  .sleepQuality,  m.sleepQuality.hasManual),
            (m.sleepDuration.label, m.sleepDuration.score, m.sleepDuration.detail, nil,            nil),
            (m.subjective.label,    m.subjective.score,    m.subjective.detail,    .fatigue,       m.subjective.hasManual),
            (m.muscleRec.label,     m.muscleRec.score,     m.muscleRec.detail,     nil,            nil),
            (m.nutrition.label,     m.nutrition.score,     m.nutrition.detail,     nil,            nil),
            (m.pattern.label,       m.pattern.score,       m.pattern.detail,       nil,            nil),
        ]
    }
}

// MARK: - Verdict Orb

private struct VerdictOrb: View {
    let verdict: String
    let score: Int
    @State private var pulse: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(orbColor.opacity(0.12))
                .scaleEffect(pulse)
                .accessibilityHidden(true)
            Circle()
                .strokeBorder(orbColor.opacity(0.35), lineWidth: 2)
                .accessibilityHidden(true)
            Text("\(score)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(orbColor)
                .accessibilityLabel("Score \(score)")
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = 1.08
            }
        }
    }

    private var orbColor: Color {
        switch verdict {
        case "go":       return .statusGreen
        case "moderate": return Color(red: 0.98, green: 0.76, blue: 0.15)
        default:         return .statusRed
        }
    }
}

// MARK: - Module Row

private struct ModuleRow: View {
    let mod: (label: String, score: Int?, detail: String)
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Score circle
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.20), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(mod.score ?? 0) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(mod.score.map { "\($0)" } ?? "—")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(mod.label)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text(mod.detail)
                    .font(.appCaption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer()
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private var scoreColor: Color {
        guard let s = mod.score else { return .gray }
        switch s {
        case 75...: return .statusGreen
        case 50..<75: return Color(red: 0.98, green: 0.76, blue: 0.15)
        default:     return .statusRed
        }
    }
}

// MARK: - Muscle Recovery Row

private struct MuscleRow: View {
    let key: String
    let rec: MuscleGroupRecovery

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(rec.label)
                .font(.appLabel)
                .foregroundColor(.appTextPrimary)
                .frame(width: 130, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appSurfaceInset)
                    Capsule()
                        .fill(statusColor.opacity(0.75))
                        .frame(width: geo.size.width * CGFloat(rec.pct) / 100)
                }
            }
            .frame(height: 6)

            Group {
                if rec.hoursRemaining > 0 {
                    Text("\(rec.hoursRemaining)h")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                } else {
                    Text("Prêt")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.statusGreen)
                }
            }
            .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch rec.status {
        case "ready":   return .statusGreen
        case "almost":  return Color(red: 0.98, green: 0.76, blue: 0.15)
        default:        return .statusRed
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.appCaption.weight(.bold))
            .foregroundColor(Color(white: 0.40))
            .tracking(0.8)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// MARK: - Quick Metric Sheet (saisie ciblée depuis une ligne ANALYSE)

struct QuickMetricSheet: View {
    let kind: ManualMetricKind
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var value: Double
    @State private var isSaving = false
    @State private var apiError: String? = nil

    init(kind: ManualMetricKind, onSaved: @escaping () async -> Void) {
        self.kind = kind
        self.onSaved = onSaved
        _value = State(initialValue: kind.range.lowerBound)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(kind.title)
                            .font(.appTitle.weight(.bold))
                            .foregroundColor(.appTextPrimary)
                        Text(kind.subtitle)
                            .font(.appLabel)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 12) {
                        Text(String(format: "%.0f / 10", value))
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                            .frame(maxWidth: .infinity)
                        Slider(value: $value, in: kind.range, step: 1).tint(Color.forge)
                        HStack {
                            Text(kind.lowLabel).font(.appMicro).foregroundColor(.gray)
                            Spacer()
                            Text(kind.highLabel).font(.appMicro).foregroundColor(.gray)
                        }
                    }
                    .padding(16)
                    .background(Color.appCard)
                    .cornerRadius(12)

                    Spacer()

                    PrimaryButton(title: "Enregistrer", isLoading: isSaving, action: save)
                }
                .padding(20)
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(Color.forge)
                }
            }
            .alert("Erreur",
                   isPresented: Binding(get: { apiError != nil },
                                        set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                switch kind {
                case .fatigue:
                    try await APIService.shared.logRecovery(
                        sleepHours: nil, sleepQuality: nil, restingHr: nil,
                        hrv: nil, steps: nil, soreness: nil,
                        fatigue: value
                    )
                case .sleepQuality:
                    try await APIService.shared.logRecovery(
                        sleepHours: nil, sleepQuality: value, restingHr: nil,
                        hrv: nil, steps: nil, soreness: nil
                    )
                }
                triggerNotificationFeedback(.success)
                triggerImpact(style: .medium)
                await onSaved()
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                apiError = "Erreur réseau — réessaie"
            }
        }
    }
}
