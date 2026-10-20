import SwiftUI

// MARK: - Archetype color helpers (file-private)

private func archetypeAccent(_ key: String) -> Color { .forge }

private func pplDominantColor(_ ppl: DNAPPLBalance) -> Color {
    guard let push = ppl.pushPct, let pull = ppl.pullPct, let legs = ppl.legsPct else {
        return .forge
    }
    if push >= pull && push >= legs {
        return Color(red: 0.98, green: 0.45, blue: 0.10)  // orange – push
    }
    if pull >= push && pull >= legs {
        return Color(red: 0.20, green: 0.70, blue: 0.98)  // cyan – pull
    }
    return Color(red: 0.95, green: 0.80, blue: 0.10)       // yellow – legs
}

private func intensityColor(_ score: Int?) -> Color {
    guard let s = score else { return .forge }
    if s >= 65 { return Color(red: 0.31, green: 0.43, blue: 0.97) }  // blue – force
    if s >= 40 { return Color(red: 0.60, green: 0.30, blue: 0.97) }  // purple – mixed
    return Color(red: 0.98, green: 0.50, blue: 0.10)                   // orange – pump
}

// MARK: - Section (embedded in StatsView)

struct WorkoutDNASection: View {
    @State private var dna: WorkoutDNAResponse? = nil
    @State private var isLoading       = false
    @State private var loadError       = false
    @State private var selectedPeriod  = 90
    @State private var isReloading     = false
    @State private var showShare       = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if isLoading {
                    DNASkeleton().padding(.top, 40)
                } else if let d = dna {
                    WorkoutDNAInlineContent(dna: d, isReloading: isReloading, onShare: { showShare = true })
                } else if loadError {
                    DNAErrorState {
                        loadError = false
                        dna = nil
                        Task { await load() }
                    }
                } else {
                    DNAEmptyState { Task { await load() } }
                }
            }
        }
        .background(Color.appBg.ignoresSafeArea())
        .navigationTitle("Workout DNA")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if dna != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Picker("Période", selection: $selectedPeriod) {
                        Text("30j").tag(30)
                        Text("90j").tag(90)
                        Text("180j").tag(180)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .disabled(isReloading)
                }
            }
        }
        .task { await load() }
        .onChange(of: selectedPeriod) { _, period in
            Task { await reloadForPeriod(period) }
        }
        .sheet(isPresented: $showShare) {
            if let d = dna { WorkoutDNAShareSheet(dna: d) }
        }
    }

    private func load() async {
        guard dna == nil else { return }
        isLoading = true
        do {
            dna = try await APIService.shared.fetchWorkoutDNA()
        } catch {
            loadError = true
        }
        isLoading = false
    }

    private func reloadForPeriod(_ period: Int) async {
        isReloading = true
        if let newDNA = try? await APIService.shared.fetchWorkoutDNA(period: period) {
            dna = newDNA
        }
        isReloading = false
    }
}

// MARK: - Inline content (full detail, no sheet)

private struct WorkoutDNAInlineContent: View {
    let dna: WorkoutDNAResponse
    let isReloading: Bool
    let onShare: () -> Void

    private var accent: Color { archetypeAccent(dna.archetype.key) }

    private var scoreItems: [(String, Int?)] {
        [("Équilibre", dna.ppl.balanceScore),
         ("Intensité", dna.intensity.score),
         ("Constance", dna.consistency.score),
         ("Récup",     dna.recovery.score)]
    }

    private var archetypeAvailable: Bool {
        dna.archetype.available ?? true   // nil = backend pré-lot f, assumer disponible
    }

    private var pplAvailable: Bool {
        dna.ppl.insufficientData != true && dna.ppl.error == nil && dna.ppl.balanceScore != nil
    }

    private var intensityAvailable: Bool {
        dna.intensity.insufficientData != true && dna.intensity.error == nil && dna.intensity.score != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            heroSection
            scorePillsSection
            pplSection
            intensitySection
            if let timeline = dna.intensityTimeline,
               timeline.filter({ $0.totalSets > 0 }).count >= 2 {
                intensityTimelineSection(timeline)
            }
            if let muscles = dna.muscleDominants, !muscles.isEmpty {
                muscleDominantsSection(muscles)
            } else if dna.muscleDominantsMeta?.insufficientData == true {
                muscleDominantsInsufficientSection
            }
            if let patterns = dna.movementPatterns {
                if patterns.hasData {
                    movementPatternsSection(patterns)
                } else if patterns.insufficientData == true || patterns.error != nil {
                    insufficientSection(
                        title: "PATTERNS DE MOUVEMENT",
                        n: patterns.nSessions,
                        err: patterns.error,
                        hint: patterns.excludedNoPattern.flatMap {
                            $0 > 0 ? "\($0) exo\($0 > 1 ? "s" : "") sans pattern catalogué" : nil
                        }
                    )
                }
            }
            consistencySection
            recoverySection
            if !dna.signatureLifts.isEmpty {
                signatureLiftsSection
            }
            shareButton
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            if archetypeAvailable {
                DNAHelixCanvas(dna: dna, height: 160)
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
                    .accessibilityHidden(true)
                LinearGradient(colors: [.clear, Color.appBg], startPoint: .top, endPoint: .bottom)
                    .frame(maxWidth: .infinity, maxHeight: 60)
            } else {
                // Pas de helix fantôme sur des piliers absents.
                Color.appBg.frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
            }

            VStack(spacing: 4) {
                if isReloading {
                    ProgressView().tint(accent).padding(.bottom, 8)
                } else {
                    Text(dna.archetype.label)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                        .minimumScaleFactor(0.8)
                    Text(dna.archetype.tagline)
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(accent)
                        .italic()
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var scorePillsSection: some View {
        HStack(spacing: 8) {
            ForEach(scoreItems.indices, id: \.self) { i in
                ScorePill(label: scoreItems[i].0, score: scoreItems[i].1, accent: accent)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var pplSection: some View {
        if pplAvailable {
            DNASectionCard(title: "RÉPARTITION", accent: accent) {
                VStack(spacing: 12) {
                    PPLBalanceChart(ppl: dna.ppl, accent: accent)
                    HStack {
                        let bs = dna.ppl.balanceScore ?? 0
                        Image(systemName: bs >= 70 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(bs >= 70 ? .appSuccess : .appWarning)
                            .font(.appLabel)
                        Text(dna.ppl.verdict ?? "—")
                            .font(.appLabel)
                            .foregroundColor(Color.appOnSurface.opacity(0.85))
                        Spacer()
                        Text("Score \(bs)/100")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                }
            }
        } else {
            insufficientSection(title: "RÉPARTITION",
                                n: dna.ppl.nSessions,
                                err: dna.ppl.error)
        }
    }

    @ViewBuilder
    private var intensitySection: some View {
        if intensityAvailable {
            DNASectionCard(title: "PROFIL D'INTENSITÉ", accent: accent) {
                VStack(spacing: 12) {
                    IntensitySlider(score: dna.intensity.score ?? 50)
                    HStack {
                        IntensityZonePill(label: "Force",        pct: dna.intensity.forcePct ?? 0,       color: Color(red: 0.31, green: 0.43, blue: 0.97))
                        IntensityZonePill(label: "Hypertrophie", pct: dna.intensity.hypertrophyPct ?? 0, color: Color(red: 0.66, green: 0.33, blue: 0.97))
                        IntensityZonePill(label: "Endurance",    pct: dna.intensity.endurancePct ?? 0,   color: Color(red: 0.20, green: 0.70, blue: 0.98))
                    }
                    HStack {
                        Text(dna.intensity.label ?? "—")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        Text("Compound \(dna.intensity.compoundPct ?? 0)%")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                    if let excluded = dna.intensity.excludedNoLoadProfile, excluded > 0 {
                        Text("\(excluded) exo\(excluded > 1 ? "s" : "") sans profil de charge catalogué")
                            .font(.appMicro).foregroundColor(.gray.opacity(0.6))
                    }
                }
            }
        } else {
            insufficientSection(title: "PROFIL D'INTENSITÉ",
                                n: dna.intensity.nSessions,
                                err: dna.intensity.error,
                                hint: dna.intensity.excludedNoLoadProfile.flatMap {
                                    $0 > 0 ? "\($0) exo\($0 > 1 ? "s" : "") sans profil de charge" : nil
                                })
        }
    }

    @ViewBuilder
    private func insufficientSection(title: String, n: Int?, err: String?,
                                     hint: String? = nil) -> some View {
        DNASectionCard(title: title, accent: accent) {
            VStack(alignment: .leading, spacing: 4) {
                if let err {
                    Text("Erreur de calcul")
                        .font(.appLabel).foregroundColor(.appDanger)
                    Text(err)
                        .font(.appMicro).foregroundColor(.gray)
                        .lineLimit(2)
                } else {
                    Text("Données insuffisantes (n = \(n ?? 0))")
                        .font(.appLabel).foregroundColor(.appTextSecondary)
                    Text("Logge au moins 8 séances dans la fenêtre pour voir cette section.")
                        .font(.appMicro).foregroundColor(.gray)
                    if let hint {
                        Text(hint)
                            .font(.appMicro).foregroundColor(.gray.opacity(0.7))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func muscleDominantsSection(_ muscles: [DNAMuscleDominant]) -> some View {
        DNASectionCard(title: "MUSCLES DOMINANTS", accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text("séries effectives / sem · hors décharge")
                    .font(.appMicro).foregroundColor(.gray.opacity(0.7))
                ForEach(muscles, id: \.muscle) { m in
                    HStack(spacing: 12) {
                        Text(m.muscle.capitalized)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.gray)
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.appSurfaceInset)
                                Capsule()
                                    .fill(accent)
                                    .frame(width: geo.size.width * CGFloat(m.pct) / 100)
                            }
                        }
                        .frame(height: 8)
                        if let eff = m.effectiveSets {
                            Text(String(format: "%.1f", eff))
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(accent)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        } else {
                            Text("\(m.pct)%")
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(accent)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                if let meta = dna.muscleDominantsMeta,
                   let excluded = meta.excludedFullDeload, excluded > 0 {
                    Text("\(excluded) muscle\(excluded > 1 ? "s" : "") exclu\(excluded > 1 ? "s" : "") (fenêtre 100 % décharge)")
                        .font(.appMicro).foregroundColor(.gray.opacity(0.6))
                }
            }
        }
    }

    @ViewBuilder
    private var muscleDominantsInsufficientSection: some View {
        DNASectionCard(title: "MUSCLES DOMINANTS", accent: accent) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Données insuffisantes (n = \(dna.muscleDominantsMeta?.nSessions ?? 0))")
                    .font(.appLabel).foregroundColor(.appTextSecondary)
                Text("Logge au moins 8 séances dans la fenêtre pour voir cette section.")
                    .font(.appMicro).foregroundColor(.gray)
            }
        }
    }

    private var consistencySection: some View {
        DNASectionCard(title: "CONSTANCE", accent: accent) {
            VStack(spacing: 12) {
                ConsistencyGrid(counts: dna.consistency.weeklyCounts, accent: accent)
                HStack(spacing: 16) {
                    ConsistencyStat(label: "par semaine",   value: String(format: "%.1f", dna.consistency.sessionsPerWeek))
                    ConsistencyStat(label: "streak actuel", value: "\(dna.consistency.weeklyStreakCurrent) sem")
                    ConsistencyStat(label: "record",        value: "\(dna.consistency.weeklyStreakBest) sem")
                }
                HStack {
                    Text(dna.consistency.archetype)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(accent)
                    Spacer()
                    Text("\(dna.consistency.activeWeeksPct)% semaines actives")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var recoverySection: some View {
        DNASectionCard(title: "RÉCUPÉRATION", accent: accent) {
            VStack(spacing: 12) {
                RecoveryIndicator(recovery: dna.recovery)
                HStack {
                    Image(systemName: dna.recovery.verdict == "Optimal" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(dna.recovery.verdict == "Optimal" ? .appSuccess : .appWarning)
                        .font(.appLabel)
                    Text(dna.recovery.verdict)
                        .font(.appLabel)
                        .foregroundColor(Color.appOnSurface.opacity(0.85))
                    Spacer()
                    Text("Optimal: \(String(format: "%.1f", dna.recovery.optimalRestDays))j")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var signatureLiftsSection: some View {
        DNASectionCard(title: "SIGNATURE LIFTS", accent: accent) {
            VStack(spacing: 0) {
                ForEach(dna.signatureLifts.indices, id: \.self) { i in
                    SignatureLiftRow(lift: dna.signatureLifts[i], rank: i + 1, accent: accent)
                    if i < dna.signatureLifts.count - 1 {
                        Divider().background(Color.appSeparatorSubtle).padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    // MARK: Intensity Timeline

    @ViewBuilder
    private func intensityTimelineSection(_ timeline: [DNAIntensityMonth]) -> some View {
        DNASectionCard(title: "ÉVOLUTION DE L'INTENSITÉ — 6 MOIS", accent: accent) {
            let activeMonths = timeline.filter { $0.totalSets > 0 }
            VStack(spacing: 12) {
                // Stacked bar chart
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(timeline) { month in
                        VStack(spacing: 2) {
                            if month.totalSets > 0 {
                                IntensityTimelineBar(month: month)
                            } else {
                                RoundedRectangle(cornerRadius: 3) // shape inline
                                    .fill(Color.appSurfaceInset)
                                    .frame(height: 48)
                            }
                            Text(String(month.month.suffix(2)))
                                .font(.appMicro)
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 60)
                // Legend
                HStack(spacing: 12) {
                    IntensityTimelineLegendDot(color: Color(red: 0.31, green: 0.43, blue: 0.97), label: "Force")
                    IntensityTimelineLegendDot(color: Color(red: 0.66, green: 0.33, blue: 0.97), label: "Hypertrophie")
                    IntensityTimelineLegendDot(color: Color(red: 0.20, green: 0.70, blue: 0.98), label: "Endurance")
                    Spacer()
                    if let trend = intensityTrend(activeMonths) {
                        Text(trend)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(accent)
                    }
                }
            }
        }
    }

    private func intensityTrend(_ months: [DNAIntensityMonth]) -> String? {
        guard months.count >= 2 else { return nil }
        let first = months[0].strengthPct
        let last  = months[months.count - 1].strengthPct
        let delta = last - first
        if delta > 8  { return "↑ Plus lourd" }
        if delta < -8 { return "↓ Plus de volume" }
        return nil
    }

    // MARK: Movement Patterns

    @ViewBuilder
    private func movementPatternsSection(_ patterns: DNAMovementPatterns) -> some View {
        DNASectionCard(title: "PATTERNS DE MOUVEMENT", accent: accent) {
            VStack(spacing: 12) {
                // Top 6 patterns as bars
                let topPatterns = Array(patterns.patterns.prefix(6))
                VStack(spacing: 8) {
                    ForEach(topPatterns) { entry in
                        HStack(spacing: 8) {
                            Text(patternLabel(entry.pattern))
                                .font(.appCaption.weight(.medium))
                                .foregroundColor(.gray)
                                .frame(width: 110, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.appSurfaceInset)
                                    Capsule()
                                        .fill(patternColor(entry.pattern))
                                        .frame(width: geo.size.width * CGFloat(entry.pct) / 100)
                                }
                            }
                            .frame(height: 7)
                            Text("\(entry.pct)%")
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(patternColor(entry.pattern))
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                }
                // Ratios + diversity
                HStack(spacing: 0) {
                    if let hs = patterns.ratios.hingeSquat {
                        PatternRatioPill(label: "Hinge/Squat", value: hs,
                                        ideal: 0.75, warn: 0.5)
                        Spacer()
                    }
                    if let pv = patterns.ratios.pushHorizVert {
                        PatternRatioPill(label: "Horiz/Vert", value: pv,
                                        ideal: 1.0, warn: 0.4)
                        Spacer()
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                        Text("Diversité \(patterns.diversityScore)%")
                            .font(.appCaption)
                            .foregroundColor(patterns.diversityScore >= 40 ? accent : Color.forge)
                    }
                }
            }
        }
    }

    private func patternLabel(_ pattern: String) -> String {
        switch pattern {
        case "squat":              return "Squat"
        case "hinge":              return "Hinge"
        case "push_horizontal":    return "Push Horiz."
        case "push_vertical":      return "Push Vert."
        case "pull_horizontal":    return "Pull Horiz."
        case "pull_vertical":      return "Pull Vert."
        case "hip_thrust":         return "Hip Thrust"
        case "lunge":              return "Lunge"
        case "carry":              return "Carry"
        case "plank":              return "Gainage"
        case "anti_rotation":      return "Anti-rotation"
        case "rotation":           return "Rotation"
        case "jump":               return "Saut"
        case "sprint":             return "Sprint"
        case "isolation_upper":    return "Isolation Haut"
        case "isolation_lower":    return "Isolation Bas"
        case "cardio":             return "Cardio"
        default:                   return pattern.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func patternColor(_ pattern: String) -> Color {
        if pattern.hasPrefix("push") { return Color(red: 0.98, green: 0.45, blue: 0.10) }
        if pattern.hasPrefix("pull") { return Color(red: 0.20, green: 0.70, blue: 0.98) }
        if pattern == "squat" || pattern == "lunge" { return Color(red: 0.95, green: 0.80, blue: 0.10) }
        if pattern == "hinge" || pattern == "hip_thrust" { return Color(red: 0.13, green: 0.77, blue: 0.37) }
        if pattern.hasPrefix("isolation") { return Color(red: 0.66, green: 0.33, blue: 0.97) }
        return .gray
    }

    private var shareButton: some View {
        Button(action: onShare) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Partager mon DNA")
                    .font(.appBody.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(accent)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .buttonStyle(SpringButtonStyle())
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - Intensity Timeline Bar

private struct IntensityTimelineBar: View {
    let month: DNAIntensityMonth

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let strH  = CGFloat(month.strengthPct)    / 100 * h
            let hypH  = CGFloat(month.hypertrophyPct) / 100 * h
            let endH  = CGFloat(month.endurancePct)   / 100 * h
            VStack(spacing: 0) {
                // Endurance (top)
                RoundedRectangle(cornerRadius: 2) // shape inline
                    .fill(Color(red: 0.20, green: 0.70, blue: 0.98).opacity(0.75))
                    .frame(height: max(0, endH))
                // Hypertrophie (middle)
                Rectangle()
                    .fill(Color(red: 0.66, green: 0.33, blue: 0.97).opacity(0.75))
                    .frame(height: max(0, hypH))
                // Force (bottom)
                RoundedRectangle(cornerRadius: 2) // shape inline
                    .fill(Color(red: 0.31, green: 0.43, blue: 0.97).opacity(0.75))
                    .frame(height: max(0, strH))
            }
        }
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 3)) // shape inline
    }
}

private struct IntensityTimelineLegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.appMicro).foregroundColor(.gray)
        }
    }
}

// MARK: - Pattern Ratio Pill

private struct PatternRatioPill: View {
    let label: String
    let value: Double
    let ideal: Double
    let warn: Double

    private var pillColor: Color {
        if value < warn { return .appDanger }
        if abs(value - ideal) / max(ideal, 0.01) > 0.35 { return .appWarning }
        return .appSuccess
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(pillColor)
            Text(label)
                .font(.appMicro)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(pillColor.opacity(0.10))
        .cornerRadius(8)
    }
}

// MARK: - Score pill

private struct ScorePill: View {
    let label: String
    let score: Int?
    let accent: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(score.map { "\($0)" } ?? "—")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(score == nil ? .appTextSecondary : accent)
            Text(label)
                .font(.appMicro.weight(.semibold))
                .foregroundColor(.gray)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.appSurfaceInset)
        .cornerRadius(8)
    }
}

// MARK: - Helix Canvas

struct DNAHelixCanvas: View {
    let dna: WorkoutDNAResponse
    var height: CGFloat = 180

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let leftColor  = pplDominantColor(dna.ppl)
            let rightColor = intensityColor(dna.intensity.score)
            let spw        = max(1.0, dna.consistency.sessionsPerWeek)
            let balance    = Double(dna.ppl.balanceScore ?? 50) / 100.0
            let amplitude  = size.width * (0.14 + (1 - balance) * 0.09)
            let pitch      = max(14.0, 38.0 - spw * 3.5)
            let cx         = size.width / 2
            let totalRungs = Int(size.height / pitch) + 1
            let rotations  = 3.5  // full cycles in the card height

            var leftPath  = Path()
            var rightPath = Path()

            for i in 0...totalRungs {
                let y     = CGFloat(i) * pitch
                let frac  = Double(i) / Double(max(totalRungs, 1))
                let angle = frac * .pi * 2 * rotations

                let x1 = cx - CGFloat(amplitude * cos(angle))
                let x2 = cx + CGFloat(amplitude * cos(angle))

                if i == 0 {
                    leftPath.move(to:  CGPoint(x: x1, y: y))
                    rightPath.move(to: CGPoint(x: x2, y: y))
                } else {
                    leftPath.addLine(to:  CGPoint(x: x1, y: y))
                    rightPath.addLine(to: CGPoint(x: x2, y: y))
                }

                // Rung — fades slightly where rest days fall
                let restFreq  = max(2.0, dna.recovery.avgRestDays + 1.5)
                let isRestRung = Double(i).truncatingRemainder(dividingBy: restFreq) < 0.9
                let rungAlpha  = isRestRung ? 0.55 : 0.15

                var rung = Path()
                rung.move(to: CGPoint(x: x1, y: y))
                rung.addLine(to: CGPoint(x: x2, y: y))
                let midColor = frac < 0.5 ? leftColor : rightColor
                context.stroke(rung, with: .color(midColor.opacity(rungAlpha)), lineWidth: 1.5)

                // Strand node — draw the "front" strand over the rung
                let dotR: CGFloat = 3.0
                if cos(angle) >= 0 {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x2 - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                        with: .color(rightColor.opacity(0.90))
                    )
                } else {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x1 - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                        with: .color(leftColor.opacity(0.90))
                    )
                }
            }

            context.stroke(leftPath,  with: .color(leftColor.opacity(0.35)),  lineWidth: 1.5)
            context.stroke(rightPath, with: .color(rightColor.opacity(0.35)), lineWidth: 1.5)
        }
        .frame(height: height)
    }
}

// MARK: - Section card wrapper

private struct DNASectionCard<Content: View>: View {
    let title: String
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.appMicro)
                .foregroundColor(Color(white: 0.38))
                .tracking(0.8)
            content()
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

// MARK: - PPL Balance Chart

private struct PPLBalanceChart: View {
    let ppl: DNAPPLBalance
    let accent: Color

    private let bars: [(String, Int, Color)] = []

    var body: some View {
        let items: [(String, Int, Color)] = [
            ("Push", ppl.pushPct ?? 0, Color(red: 0.98, green: 0.45, blue: 0.10)),
            ("Pull", ppl.pullPct ?? 0, Color(red: 0.20, green: 0.70, blue: 0.98)),
            ("Legs", ppl.legsPct ?? 0, Color(red: 0.95, green: 0.80, blue: 0.10)),
        ]
        VStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 12) {
                    Text(items[i].0)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.gray)
                        .frame(width: 28, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.appSurfaceInset)
                            Capsule()
                                .fill(items[i].2)
                                .frame(width: geo.size.width * CGFloat(items[i].1) / 100)
                        }
                    }
                    .frame(height: 8)
                    Text("\(items[i].1)%")
                        .font(.appCaption.weight(.bold))
                        .foregroundColor(items[i].2)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Intensity Slider

private struct IntensitySlider: View {
    let score: Int

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.50, blue: 0.10),
                                 Color(red: 0.60, green: 0.30, blue: 0.97),
                                 Color(red: 0.31, green: 0.43, blue: 0.97)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .clipShape(Capsule())

                    // Dot
                    let dotX = geo.size.width * CGFloat(score) / 100
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .frame(width: 16, height: 16)
                        .offset(x: dotX - 8)
                }
            }
            .frame(height: 8)
            HStack {
                Text("Pump").font(.appCaption).foregroundColor(.gray)
                Spacer()
                Text("Hypertrophie").font(.appCaption).foregroundColor(.gray)
                Spacer()
                Text("Force").font(.appCaption).foregroundColor(.gray)
            }
        }
    }
}

private struct IntensityZonePill: View {
    let label: String
    let pct: Int
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(pct)%")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.appMicro)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Consistency Grid

private struct ConsistencyGrid: View {
    let counts: [Int]
    let accent: Color

    var body: some View {
        let weeks = counts.prefix(13)
        let maxCount = max(1, weeks.max() ?? 1)
        HStack(spacing: 4) {
            ForEach(weeks.indices, id: \.self) { i in
                let c     = weeks[i]
                let frac  = CGFloat(c) / CGFloat(maxCount)
                RoundedRectangle(cornerRadius: 3) // shape inline
                    .fill(c == 0 ? Color.appSurfaceInset : accent.opacity(0.25 + frac * 0.70))
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .overlay(
                        Text(c > 0 ? "\(c)" : "")
                            .font(.appMicro.weight(.bold))
                            .foregroundColor(Color.appOnSurface.opacity(0.7))
                    )
            }
        }
    }
}

private struct ConsistencyStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundColor(.appTextPrimary)
            Text(label)
                .font(.appMicro)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Recovery Indicator

private struct RecoveryIndicator: View {
    let recovery: DNARecovery

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(String(format: "%.1f j", recovery.avgRestDays))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Text("repos moyen")
                    .font(.appCaption)
                    .foregroundColor(.gray)
            }
            Spacer()
            // Ratio bar
            VStack(alignment: .trailing, spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.appSurfaceInset)
                        Capsule()
                            .fill(ratioColor)
                            .frame(width: geo.size.width * min(CGFloat(recovery.ratio), 1.5) / 1.5)
                    }
                }
                .frame(height: 6)
                Text("ratio \(String(format: "%.2f", recovery.ratio)) vs optimal")
                    .font(.appCaption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var ratioColor: Color {
        if recovery.ratio < 0.75 || recovery.ratio > 1.30 { return .appWarning }
        return .appSuccess
    }
}

// MARK: - Signature Lift Row

private struct SignatureLiftRow: View {
    let lift: DNASignatureLift
    let rank: Int
    let accent: Color
    @ObservedObject private var unitSettings = UnitSettings.shared

    private var sinceLabel: String? {
        guard !lift.firstDate.isEmpty else { return nil }
        return "depuis le \(String(lift.firstDate.prefix(10)))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(rank)")
                .font(.appCaption.weight(.black))
                .foregroundColor(accent.opacity(0.6))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(lift.name)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text("\(lift.sessionCount) séances\(sinceLabel.map { " · \($0)" } ?? "")")
                    .font(.appCaption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let e1rm = lift.prEIrmLbs {
                    Text("e1RM \(unitSettings.format(e1rm))")
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(.appTextPrimary)
                } else if let raw = lift.prLbs {
                    Text("\(unitSettings.format(raw)) × \(lift.prReps)")
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(.appTextPrimary)
                }
                if let prog = lift.progressionPct, prog > 0 {
                    Text("↑ \(Int(prog))% sur la fenêtre")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.appSuccess)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
    }
}

// MARK: - Share Sheet

private struct WorkoutDNAShareSheet: View {
    let dna: WorkoutDNAResponse
    @Environment(\.dismiss) private var dismiss
    @State private var showActivity = false
    @State private var shareImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Ton DNA Card").font(.appHeadline).foregroundColor(.appTextPrimary).padding(.top, 16)

                WorkoutDNAShareCard(dna: dna)
                    .frame(width: 300, height: 380)
                    .cornerRadius(18)
                    .shadow(color: archetypeAccent(dna.archetype.key).opacity(0.30), radius: 24)

                Button {
                    let r = ImageRenderer(content: WorkoutDNAShareCard(dna: dna).frame(width: 400, height: 506))
                    r.scale      = 3.0
                    shareImage   = r.uiImage
                    showActivity = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Exporter").font(.appBody.weight(.bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(archetypeAccent(dna.archetype.key))
                    .foregroundColor(.white).cornerRadius(8)
                }
                .buttonStyle(SpringButtonStyle()).padding(.horizontal, 24)
                Spacer()
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                    }
                }
            }
            .sheet(isPresented: $showActivity) {
                if let img = shareImage { WorkoutDNAActivitySheet(items: [img]) }
            }
        }
    }
}

// MARK: - Share Card (ImageRenderer export)

struct WorkoutDNAShareCard: View {
    let dna: WorkoutDNAResponse

    private var accent: Color { archetypeAccent(dna.archetype.key) }

    var body: some View {
        ZStack {
            // Background gradient unique per archetype
            LinearGradient(
                colors: [Color.black, accent.opacity(0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TRAININGOS").font(.system(size: 7, weight: .black)).foregroundColor(accent).tracking(2.5)
                        Text("WORKOUT DNA").font(.system(size: 6, weight: .bold)).foregroundColor(.gray).tracking(1.5)
                    }
                    Spacer()
                    Text(dna.period.to.prefix(7).description)
                        .font(.appMicro).foregroundColor(.gray)
                }
                .padding(.bottom, 12)

                // Archetype
                Text(dna.archetype.label)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Text(dna.archetype.tagline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(accent)
                    .italic()
                    .padding(.bottom, 14)

                // Mini helix
                DNAHelixCanvas(dna: dna, height: 100)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)

                // 4 scores
                HStack(spacing: 6) {
                    ForEach([("ÉQUILIBRE", dna.ppl.balanceScore),
                             ("INTENSITÉ", dna.intensity.score),
                             ("CONSTANCE", dna.consistency.score),
                             ("RÉCUP",     dna.recovery.score)], id: \.0) { item in
                        VStack(spacing: 2) {
                            Text("\(item.1)")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(accent)
                            Text(item.0)
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.gray)
                                .tracking(0.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.appSurfaceInset)
                        .cornerRadius(6)
                    }
                }
                .padding(.bottom, 14)

                // Signature lifts
                if !dna.signatureLifts.isEmpty {
                    Rectangle().fill(accent.opacity(0.25)).frame(height: 1).padding(.bottom, 10)
                    ForEach(dna.signatureLifts.prefix(3)) { lift in
                        HStack {
                            Text(lift.name).font(.appMicro.weight(.medium)).foregroundColor(Color.appTextPrimary.opacity(0.8))
                            Spacer()
                            Text(UnitSettings.shared.format(lift.prLbs))
                                .font(.appMicro.weight(.bold)).foregroundColor(.appTextPrimary)
                            if lift.progressionPct > 0 {
                                Text("+\(Int(lift.progressionPct))%")
                                    .font(.system(size: 8, weight: .semibold)).foregroundColor(.appSuccess)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }

                Spacer()

                // Footer bar
                Rectangle()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 3).cornerRadius(2)
            }
            .padding(18)
        }
    }
}

// MARK: - UIActivityViewController wrapper

private struct WorkoutDNAActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Loading / Empty states

private struct DNASkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Capsule().fill(Color.appSurfaceInset).frame(width: 72, height: 80)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(Color.appSurfaceInset).frame(width: 130, height: 16)
                    Capsule().fill(Color.appSurfaceInset).frame(width: 90, height: 11)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
}

private struct DNAEmptyState: View {
    let onLoad: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 26)).foregroundColor(.gray.opacity(0.35))
            Text("Pas encore assez de données")
                .font(.appLabel).foregroundColor(.gray)
            Button(action: onLoad) {
                Text("Générer mon DNA")
                    .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.appSurfaceInset).cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 24).padding(.horizontal, 16)
    }
}

private struct DNAErrorState: View {
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 26)).foregroundColor(Color.forge.opacity(0.7))
            Text("Erreur de chargement")
                .font(.appLabel).foregroundColor(.gray)
            Button(action: onRetry) {
                Text("Réessayer")
                    .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.appSurfaceInset).cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 24).padding(.horizontal, 16)
    }
}
