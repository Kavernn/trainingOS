import SwiftUI

// MARK: - Archetype color helpers (file-private)

private func archetypeAccent(_ key: String) -> Color {
    switch key {
    case "powerlifter": return Color(red: 0.31, green: 0.43, blue: 0.97)
    case "bodybuilder": return Color(red: 0.98, green: 0.45, blue: 0.09)
    case "grinder":     return Color(red: 0.13, green: 0.77, blue: 0.37)
    case "warrior":     return Color(red: 0.66, green: 0.33, blue: 0.97)
    case "athlete":     return Color(red: 0.08, green: 0.72, blue: 0.64)
    default:            return Color(red: 0.37, green: 0.63, blue: 0.98)
    }
}

private func pplDominantColor(_ ppl: DNAPPLBalance) -> Color {
    if ppl.pushPct >= ppl.pullPct && ppl.pushPct >= ppl.legsPct {
        return Color(red: 0.98, green: 0.45, blue: 0.10)  // orange – push
    }
    if ppl.pullPct >= ppl.pushPct && ppl.pullPct >= ppl.legsPct {
        return Color(red: 0.20, green: 0.70, blue: 0.98)  // cyan – pull
    }
    return Color(red: 0.95, green: 0.80, blue: 0.10)       // yellow – legs
}

private func intensityColor(_ score: Int) -> Color {
    if score >= 65 { return Color(red: 0.31, green: 0.43, blue: 0.97) }  // blue – force
    if score >= 40 { return Color(red: 0.60, green: 0.30, blue: 0.97) }  // purple – mixed
    return Color(red: 0.98, green: 0.50, blue: 0.10)                       // orange – pump
}

// MARK: - Section (embedded in MoreView / IntelligenceView)

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

    private var scoreItems: [(String, Int)] {
        [("Équilibre", dna.ppl.balanceScore),
         ("Intensité", dna.intensity.score),
         ("Constance", dna.consistency.score),
         ("Récup",     dna.recovery.score)]
    }

    var body: some View {
        VStack(spacing: 16) {
            heroSection
            scorePillsSection
            pplSection
            intensitySection
            if let muscles = dna.muscleDominants, !muscles.isEmpty {
                muscleDominantsSection(muscles)
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
            DNAHelixCanvas(dna: dna, height: 160)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            LinearGradient(colors: [.clear, Color.appBg], startPoint: .top, endPoint: .bottom)
                .frame(height: 60)

            VStack(spacing: 4) {
                if isReloading {
                    ProgressView().tint(accent).padding(.bottom, 8)
                } else {
                    Text(dna.archetype.label)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.8)
                    Text(dna.archetype.tagline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accent)
                        .italic()
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var scorePillsSection: some View {
        HStack(spacing: 8) {
            ForEach(scoreItems.indices, id: \.self) { i in
                ScorePill(label: scoreItems[i].0, score: scoreItems[i].1, accent: accent)
            }
        }
        .padding(.horizontal, 16)
    }

    private var pplSection: some View {
        DNASectionCard(title: "RÉPARTITION", accent: accent) {
            VStack(spacing: 10) {
                PPLBalanceChart(ppl: dna.ppl, accent: accent)
                HStack {
                    Image(systemName: dna.ppl.balanceScore >= 70 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(dna.ppl.balanceScore >= 70 ? .green : .orange)
                        .font(.system(size: 13))
                    Text(dna.ppl.verdict)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text("Score \(dna.ppl.balanceScore)/100")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var intensitySection: some View {
        DNASectionCard(title: "PROFIL D'INTENSITÉ", accent: accent) {
            VStack(spacing: 12) {
                IntensitySlider(score: dna.intensity.score)
                HStack {
                    IntensityZonePill(label: "Force",        pct: dna.intensity.forcePct,       color: Color(red: 0.31, green: 0.43, blue: 0.97))
                    IntensityZonePill(label: "Hypertrophie", pct: dna.intensity.hypertrophyPct, color: Color(red: 0.66, green: 0.33, blue: 0.97))
                    IntensityZonePill(label: "Endurance",    pct: dna.intensity.endurancePct,   color: Color(red: 0.20, green: 0.70, blue: 0.98))
                }
                HStack {
                    Text(dna.intensity.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Compound \(dna.intensity.compoundPct)%")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    @ViewBuilder
    private func muscleDominantsSection(_ muscles: [DNAMuscleDominant]) -> some View {
        DNASectionCard(title: "MUSCLES DOMINANTS", accent: accent) {
            VStack(spacing: 7) {
                ForEach(muscles, id: \.muscle) { m in
                    HStack(spacing: 10) {
                        Text(m.muscle.capitalized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                            .frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06))
                                Capsule()
                                    .fill(accent)
                                    .frame(width: geo.size.width * CGFloat(m.pct) / 100)
                            }
                        }
                        .frame(height: 8)
                        Text("\(m.pct)%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(accent)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var consistencySection: some View {
        DNASectionCard(title: "CONSTANCE", accent: accent) {
            VStack(spacing: 12) {
                ConsistencyGrid(counts: dna.consistency.weeklyCounts, accent: accent)
                HStack(spacing: 16) {
                    ConsistencyStat(label: "par semaine",   value: String(format: "%.1f", dna.consistency.sessionsPerWeek))
                    ConsistencyStat(label: "streak actuel", value: "\(dna.consistency.currentStreak)j")
                    ConsistencyStat(label: "record",        value: "\(dna.consistency.longestStreak)j")
                }
                HStack {
                    Text(dna.consistency.archetype)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(accent)
                    Spacer()
                    Text("\(dna.consistency.activeWeeksPct)% semaines actives")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var recoverySection: some View {
        DNASectionCard(title: "RÉCUPÉRATION", accent: accent) {
            VStack(spacing: 10) {
                RecoveryIndicator(recovery: dna.recovery)
                HStack {
                    Image(systemName: dna.recovery.verdict == "Optimal" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(dna.recovery.verdict == "Optimal" ? .green : .orange)
                        .font(.system(size: 13))
                    Text(dna.recovery.verdict)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text("Optimal: \(String(format: "%.1f", dna.recovery.optimalRestDays))j")
                        .font(.system(size: 11))
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
                        Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    private var shareButton: some View {
        Button(action: onShare) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Partager mon DNA")
                    .font(.system(size: 15, weight: .bold))
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

// MARK: - Score pill

private struct ScorePill: View {
    let label: String
    let score: Int
    let accent: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(accent)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.gray)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Helix Canvas

struct DNAHelixCanvas: View {
    let dna: WorkoutDNAResponse
    var height: CGFloat = 180

    var body: some View {
        Canvas { context, size in
            let leftColor  = pplDominantColor(dna.ppl)
            let rightColor = intensityColor(dna.intensity.score)
            let spw        = max(1.0, dna.consistency.sessionsPerWeek)
            let balance    = Double(dna.ppl.balanceScore) / 100.0
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
                .font(.system(size: 10, weight: .bold))
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
            ("Push", ppl.pushPct, Color(red: 0.98, green: 0.45, blue: 0.10)),
            ("Pull", ppl.pullPct, Color(red: 0.20, green: 0.70, blue: 0.98)),
            ("Legs", ppl.legsPct, Color(red: 0.95, green: 0.80, blue: 0.10)),
        ]
        VStack(spacing: 7) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Text(items[i].0)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 28, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.06))
                            Capsule()
                                .fill(items[i].2)
                                .frame(width: geo.size.width * CGFloat(items[i].1) / 100)
                        }
                    }
                    .frame(height: 8)
                    Text("\(items[i].1)%")
                        .font(.system(size: 12, weight: .bold))
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
        VStack(spacing: 6) {
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
                Text("Pump").font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                Text("Hypertrophie").font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                Text("Force").font(.system(size: 10)).foregroundColor(.gray)
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
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
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
                RoundedRectangle(cornerRadius: 3)
                    .fill(c == 0 ? Color.white.opacity(0.06) : accent.opacity(0.25 + frac * 0.70))
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .overlay(
                        Text(c > 0 ? "\(c)" : "")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
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
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
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
                    .foregroundColor(.white)
                Text("repos moyen")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            Spacer()
            // Ratio bar
            VStack(alignment: .trailing, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule()
                            .fill(ratioColor)
                            .frame(width: geo.size.width * min(CGFloat(recovery.ratio), 1.5) / 1.5)
                    }
                }
                .frame(height: 6)
                Text("ratio \(String(format: "%.2f", recovery.ratio)) vs optimal")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var ratioColor: Color {
        if recovery.ratio < 0.75 || recovery.ratio > 1.30 { return .orange }
        return .green
    }
}

// MARK: - Signature Lift Row

private struct SignatureLiftRow: View {
    let lift: DNASignatureLift
    let rank: Int
    let accent: Color
    @ObservedObject private var unitSettings = UnitSettings.shared

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(rank)")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(accent.opacity(0.6))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(lift.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(lift.sessionCount) séances")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(unitSettings.format(lift.prKg)) × \(lift.prReps)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                if lift.progressionPct > 0 {
                    Text("↑ \(Int(lift.progressionPct))% sur l'ancienne limite")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 10)
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
                Text("Ton DNA Card").font(.system(size: 16, weight: .semibold)).foregroundColor(.white).padding(.top, 16)

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
                        Text("Exporter").font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(archetypeAccent(dna.archetype.key))
                    .foregroundColor(.white).cornerRadius(12)
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
                        .font(.system(size: 9)).foregroundColor(.gray)
                }
                .padding(.bottom, 12)

                // Archetype
                Text(dna.archetype.label)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(dna.archetype.tagline)
                    .font(.system(size: 10, weight: .medium))
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
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
                .padding(.bottom, 14)

                // Signature lifts
                if !dna.signatureLifts.isEmpty {
                    Rectangle().fill(accent.opacity(0.25)).frame(height: 1).padding(.bottom, 10)
                    ForEach(dna.signatureLifts.prefix(3)) { lift in
                        HStack {
                            Text(lift.name).font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text(UnitSettings.shared.format(lift.prKg))
                                .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                            if lift.progressionPct > 0 {
                                Text("+\(Int(lift.progressionPct))%")
                                    .font(.system(size: 8, weight: .semibold)).foregroundColor(.green)
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
            HStack(spacing: 14) {
                Capsule().fill(Color.white.opacity(0.05)).frame(width: 72, height: 80)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(width: 130, height: 16)
                    Capsule().fill(Color.white.opacity(0.04)).frame(width: 90, height: 11)
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
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 26)).foregroundColor(.gray.opacity(0.35))
            Text("Pas encore assez de données")
                .font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
            Button(action: onLoad) {
                Text("Générer mon DNA")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.white.opacity(0.08)).cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 20).padding(.horizontal, 16)
    }
}

private struct DNAErrorState: View {
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 26)).foregroundColor(.orange.opacity(0.7))
            Text("Erreur de chargement")
                .font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
            Button(action: onRetry) {
                Text("Réessayer")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.white.opacity(0.08)).cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 20).padding(.horizontal, 16)
    }
}
