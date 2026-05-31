import SwiftUI
import Charts

// MARK: - Container principal

struct EnergyRecoveryView: View {
    @State private var activeTab  = 0
    @State private var energy: EnergyDaily?
    @State private var history: [EnergyHistoryDay] = []
    @State private var isLoading    = true
    @State private var apiError: String?
    @State private var recoveryLog: [RecoveryEntry] = []
    @State private var dailySummary: DailySummary?
    @State private var hrvAnalysis: HRVAnalysis?
    @State private var sleepHistory: [SleepEntry] = []
    @State private var sleepStats: SleepStats?

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackground(color: .orange)

            VStack(spacing: 0) {
                ERTabPicker(activeTab: $activeTab)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                if isLoading {
                    Spacer()
                    AppLoadingView()
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            if activeTab == 0 {
                                EnergyTabContent(energy: energy, history: history,
                                                 activeEnergy: recoveryLog.first?.activeEnergy)
                                DynamicSuggestionsSection(
                                    energy: energy,
                                    recoveryToday: recoveryLog.first,
                                    sleepToday: sleepHistory.first,
                                    summary: dailySummary,
                                    hrv: hrvAnalysis
                                )
                            } else {
                                RecoverySleepTabContent(
                                    recoveryLog: recoveryLog,
                                    dailySummary: dailySummary,
                                    hrvAnalysis: hrvAnalysis,
                                    sleepHistory: sleepHistory,
                                    sleepStats: sleepStats
                                )
                            }
                            Spacer(minLength: 100)
                        }
                        .animation(.easeInOut(duration: 0.2), value: activeTab)
                    }
                    .refreshable { await loadData() }
                }
            }
        }
        .navigationTitle("Énergie & Récupération")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .alert("Erreur réseau", isPresented: Binding(
            get: { apiError != nil },
            set: { if !$0 { apiError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(apiError ?? "") }
    }

    private func loadData() async {
        // sequential — iOS 26 beta async let LIFO crash
        let e       = try? await APIService.shared.fetchEnergyDaily()
        let h       = try? await APIService.shared.fetchEnergyHistory()
        let rec     = try? await APIService.shared.fetchRecoveryData()
        let sum     = try? await APIService.shared.fetchDailySummary()
        let hrv     = try? await APIService.shared.fetchHRVAnalysis()
        let sleepPg = try? await APIService.shared.fetchSleepHistory(limit: 10)
        let sstats  = try? await APIService.shared.fetchSleepStats()
        await MainActor.run {
            energy       = e
            history      = h ?? []
            recoveryLog  = rec ?? []
            dailySummary = sum
            hrvAnalysis  = hrv
            sleepHistory = sleepPg?.items ?? []
            sleepStats   = sstats
            isLoading    = false
        }
    }
}

// MARK: - Tab picker

private struct ERTabPicker: View {
    @Binding var activeTab: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "Énergie", index: 0)
            tabButton(title: "Récup & Sommeil", index: 1)
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func tabButton(title: String, index: Int) -> some View {
        let selected = activeTab == index
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { activeTab = index }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: selected ? .bold : .medium))
                .foregroundColor(selected ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Color.orange : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 0 — Énergie

private struct EnergyTabContent: View {
    let energy: EnergyDaily?
    let history: [EnergyHistoryDay]
    var activeEnergy: Double? = nil

    var body: some View {
        VStack(spacing: 16) {
            if let e = energy {
                if e.isError {
                    EnergyErrorCard(message: e.message ?? "Complète ton profil pour calculer ton bilan.")
                } else {
                    EnergyHeaderCard(energy: e)
                    EnergyBreakdownCard(energy: e, activeEnergy: activeEnergy)
                }
            } else {
                EnergyErrorCard(message: "Impossible de charger le bilan énergétique.")
            }

            if history.count >= 2 {
                EnergyChartSection(history: history)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

// MARK: - Energy Header Card

struct EnergyHeaderCard: View {
    let energy: EnergyDaily

    var body: some View {
        let score  = energy.energyScore
        let color  = energy.statusColor
        let status = energy.statusLabel
        let bal    = energy.formattedBalance
        let balVal = energy.balance ?? 0

        VStack(spacing: 14) {
            // Score + statut
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 6)
                        .frame(width: 68, height: 68)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(-90))
                    Text("\(score)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(status)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(color)
                    if let obj = energy.objective {
                        Text("Objectif : \(obj.capitalized)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    if let target = energy.targetBalance {
                        Text("Cible : \(target)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
            }

            Divider().background(Color.white.opacity(0.08))

            // Bilan kcal
            HStack(spacing: 0) {
                energyKPI(label: "Dépenses",
                          value: energy.tdee.map { "\($0)" } ?? "—",
                          unit: "kcal", color: .blue)
                Spacer()
                energyKPI(label: "Apports",
                          value: energy.intake.map { "\($0)" } ?? "—",
                          unit: "kcal", color: .green)
                Spacer()
                energyKPI(label: "Bilan",
                          value: bal,
                          unit: "", color: energy.statusColor)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    private func energyKPI(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(color)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Breakdown Card (BMR + EAT + NEAT)

private struct EnergyBreakdownCard: View {
    let energy: EnergyDaily
    var activeEnergy: Double? = nil

    var body: some View {
        let bmrVal   = energy.bmr ?? 0
        let eatW     = energy.eatWorkouts ?? 0
        let eatC     = energy.eatCardio ?? 0
        let neatVal  = energy.neat ?? 0
        let tdee     = energy.tdee ?? 0
        let isRestDay = eatW == 0 && eatC == 0

        VStack(alignment: .leading, spacing: 12) {
            Text("DÉPENSES DU JOUR")
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundColor(.gray)

            VStack(spacing: 8) {
                breakdownRow(label: "BMR",
                             subtitle: energy.bmrFormulaLabel,
                             value: bmrVal,
                             color: .blue,
                             total: tdee)
                if eatW > 0 {
                    breakdownRow(label: "Musculation",
                                 subtitle: "\(energy.breakdown?.workouts?.count ?? 0) séance(s)",
                                 value: eatW,
                                 color: .orange,
                                 total: tdee)
                }
                if eatC > 0 {
                    breakdownRow(label: "Cardio",
                                 subtitle: "\(energy.breakdown?.cardio?.count ?? 0) session(s)",
                                 value: eatC,
                                 color: .teal,
                                 total: tdee)
                }
                if neatVal > 0 {
                    breakdownRow(label: "NEAT",
                                 subtitle: energy.breakdown?.steps.map { "\($0) pas" } ?? "Activité légère",
                                 value: neatVal,
                                 color: .green,
                                 total: tdee)
                } else if energy.breakdown?.steps == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Text("Active Apple Watch pour calculer ton NEAT")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 2)
                }

                if let ae = activeEnergy, ae > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 12))
                            .foregroundColor(isRestDay && ae > 800 ? .orange : .gray)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Dépense active (HealthKit)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                            if isRestDay && ae > 800 {
                                Text("Activité élevée malgré le repos")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        Text("\(Int(ae)) kcal")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(isRestDay && ae > 800 ? .orange : .gray)
                    }
                    .padding(.top, 2)
                }

                Divider().background(Color.white.opacity(0.08))

                HStack {
                    Text("Total TDEE")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(tdee) kcal")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func breakdownRow(label: String, subtitle: String,
                              value: Int, color: Color, total: Int) -> some View {
        let pct = total > 0 ? CGFloat(value) / CGFloat(total) : 0

        return VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
                Text("\(value) kcal")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * pct, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Error Card

private struct EnergyErrorCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Graphique 7j dépenses vs apports

private struct EnergyChartSection: View {
    let history: [EnergyHistoryDay]
    @State private var selectedDay: EnergyHistoryDay?

    private var yDomain: ClosedRange<Int> {
        let allVals = history.flatMap { day -> [Int] in
            var v = [day.tdee]
            if let i = day.intake { v.append(i) }
            return v
        }
        let lo = (allVals.min() ?? 0) - 200
        let hi = (allVals.max() ?? 3000) + 200
        return max(0, lo)...hi
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DÉPENSES VS APPORTS — 7J")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 12) {
                    legendDot(color: .blue,  label: "TDEE")
                    legendDot(color: .green, label: "Apports")
                }
            }

            Chart {
                // Zone colorée entre TDEE et intake
                ForEach(history) { day in
                    if let intake = day.intake {
                        let lo = min(intake, day.tdee)
                        let hi = max(intake, day.tdee)
                        AreaMark(
                            x: .value("Date", day.shortDate),
                            yStart: .value("Lo", lo),
                            yEnd: .value("Hi", hi)
                        )
                        .foregroundStyle(
                            (intake >= day.tdee ? Color.green : Color.red).opacity(0.14)
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }

                // Ligne TDEE (bleue)
                ForEach(history) { day in
                    LineMark(
                        x: .value("Date", day.shortDate),
                        y: .value("TDEE", day.tdee),
                        series: .value("Série", "Dépenses")
                    )
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", day.shortDate),
                        y: .value("TDEE", day.tdee)
                    )
                    .foregroundStyle(Color.blue)
                    .symbolSize(20)
                }

                // Ligne Apports (verte) — jours avec données uniquement
                ForEach(history.filter { $0.intake != nil }) { day in
                    LineMark(
                        x: .value("Date", day.shortDate),
                        y: .value("Apports", day.intake ?? 0),
                        series: .value("Série", "Apports")
                    )
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", day.shortDate),
                        y: .value("Apports", day.intake ?? 0)
                    )
                    .foregroundStyle(Color.green)
                    .symbolSize(20)
                }

                // Sélection interactive
                if let sel = selectedDay {
                    RuleMark(x: .value("Sélection", sel.shortDate))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .annotation(position: .top, alignment: .center) {
                            dayAnnotation(sel)
                        }
                }
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        if let v = val.as(Int.self) {
                            Text("\(v / 100 * 100)")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel()
                        .font(.system(size: 9))
                        .foregroundStyle(Color.gray)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = value.location.x - geo[plotFrame].origin.x
                                if let label: String = proxy.value(atX: x) {
                                    selectedDay = history.first { $0.shortDate == label }
                                }
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    selectedDay = nil
                                }
                            }
                        )
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
        }
    }

    private func dayAnnotation(_ day: EnergyHistoryDay) -> some View {
        VStack(spacing: 2) {
            Text(day.date)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
            Text("TDEE \(day.tdee) kcal")
                .font(.system(size: 9))
                .foregroundColor(.blue)
            if let i = day.intake {
                Text("Apports \(i) kcal")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
            }
            if let b = day.balance {
                Text(b >= 0 ? "+\(b) kcal" : "\(b) kcal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(b >= 0 ? .green : .red)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Tab 1 — Récupération & Sommeil

private struct RecoverySleepTabContent: View {
    let recoveryLog: [RecoveryEntry]
    let dailySummary: DailySummary?
    let hrvAnalysis: HRVAnalysis?
    let sleepHistory: [SleepEntry]
    let sleepStats: SleepStats?

    var body: some View {
        VStack(spacing: 16) {
            RecoverySectionContent(log: recoveryLog,
                                   summary: dailySummary,
                                   hrv: hrvAnalysis)
            SleepSectionContent(history: sleepHistory, stats: sleepStats)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

// MARK: - Section Récupération (Étape 6)

private struct RecoverySectionContent: View {
    let log: [RecoveryEntry]
    let summary: DailySummary?
    let hrv: HRVAnalysis?

    private var today: RecoveryEntry? { log.first }

    private var readinessScore: Double? {
        if let s = summary?.recoveryScore { return s }
        if let h = hrv?.hrvScore          { return h }
        guard let e = today else          { return nil }
        return computeReadiness(from: e)
    }

    var body: some View {
        let score = readinessScore
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RÉCUPÉRATION")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                NavigationLink(destination: RecoveryView()) {
                    HStack(spacing: 4) {
                        Text("Voir plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange.opacity(0.7))
                    }
                }
            }

            if let e = today {
                RecoveryMetricsGrid(entry: e, readiness: score, hrv: hrv)
            } else {
                Text("Aucune donnée de récupération")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }

            if log.count >= 3 {
                Recovery14dChart(log: log)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func computeReadiness(from e: RecoveryEntry) -> Double? {
        var components: [(v: Double, w: Double)] = []
        if let hrv = e.hrv       { components.append((min(100, max(0, (hrv - 20) / 60 * 100)), 2.0)) }
        if let rhr = e.restingHr { components.append((max(0, min(100, (80 - rhr) / 35 * 100)), 1.5)) }
        if let f   = e.fatigue   { components.append((max(0, (11 - f) / 10 * 100), 2.0)) }
        if let s   = e.soreness  { components.append((max(0, (11 - s) / 10 * 100), 1.0)) }
        guard !components.isEmpty else { return nil }
        let tw = components.reduce(0) { $0 + $1.w }
        return components.reduce(0) { $0 + $1.v * $1.w } / tw
    }
}

// MARK: - Grille métriques du jour

private struct RecoveryMetricsGrid: View {
    let entry: RecoveryEntry
    let readiness: Double?
    let hrv: HRVAnalysis?

    var body: some View {
        let scoreInt    = readiness.map { Int($0) }
        let scoreColor: Color = {
            guard let s = readiness else { return .gray }
            if s >= 75 { return .green }
            if s >= 50 { return .orange }
            return .red
        }()
        let statusLabel = readiness.map { $0 >= 75 ? "Bon" : $0 >= 50 ? "Moyen" : "Faible" } ?? "—"
        let hrvVal      = hrv?.todayRmssd ?? entry.hrv
        let rhr         = entry.restingHr
        let steps       = entry.steps
        let soreness    = entry.soreness
        let fatigue     = entry.fatigue
        let hrMorning   = entry.hrMorning
        let hrPost      = entry.hrPostWorkout
        let hrEvening   = entry.hrEvening
        let energyPre   = entry.energyPre
        let deltaFC: Double? = hrMorning.flatMap { m in hrPost.map { p in p - m } }
        let deltaColor: Color = deltaFC.map { d in d <= 10 ? .green : d <= 20 ? .orange : .red } ?? .gray
        let hrvSubtitle: String? = {
            guard let h = hrv else { return nil }
            if h.baselineAvailable, let score = h.hrvScore {
                let label = score >= 70 ? "au-dessus" : score >= 40 ? "dans ta norme" : "en dessous"
                return "\(Int(score))/100 — \(label) de ta baseline"
            }
            return "Baseline en cours (\(h.dataPoints7d)/7 j)"
        }()

        VStack(spacing: 10) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 5)
                        .frame(width: 56, height: 56)
                    Circle()
                        .trim(from: 0, to: CGFloat(readiness ?? 0) / 100)
                        .stroke(scoreColor,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                    if let s = scoreInt {
                        Text("\(s)")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(scoreColor)
                    } else {
                        Text("—")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Readiness")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                    Text(statusLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(scoreColor)
                    if let msg = hrv?.contextualMessage {
                        Text(msg)
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())],
                      spacing: 8) {
                metricCell(label: "HRV",
                           value: hrvVal.map { "\(Int($0)) ms" } ?? "—",
                           icon: "waveform.path.ecg", color: .blue,
                           subtitle: hrvSubtitle)
                metricCell(label: "FC Repos",
                           value: rhr.map { "\(Int($0)) bpm" } ?? "—",
                           icon: "heart.fill", color: .red)
                metricCell(label: "Pas",
                           value: steps.map { "\($0)" } ?? "—",
                           icon: "figure.walk", color: .green)
                metricCell(label: "Courbatures",
                           value: soreness.map { "\(Int($0))/10" } ?? "—",
                           icon: "bolt.fill", color: .orange)
                metricCell(label: "Fatigue",
                           value: fatigue.map { "\(Int($0))/10" } ?? "—",
                           icon: "gauge", color: .purple)
                metricCell(label: "Énergie perçue",
                           value: energyPre.map { "\(Int($0))/10" } ?? "—",
                           icon: "bolt.fill",
                           color: energyPre.map { $0 >= 7 ? Color.green : $0 >= 4 ? Color.orange : Color.red } ?? .gray,
                           valueColor: energyPre.map { $0 >= 7 ? Color.green : $0 >= 4 ? Color.orange : Color.red } ?? .white)
                metricCell(label: "FC Matin",
                           value: hrMorning.map { "\(Int($0)) bpm" } ?? "—",
                           icon: "sun.max.fill", color: .yellow)
                metricCell(label: "FC Post-Séance",
                           value: hrPost.map { "\(Int($0)) bpm" } ?? "—",
                           icon: "figure.strengthtraining.traditional", color: .orange)
                metricCell(label: "FC Soir",
                           value: hrEvening.map { "\(Int($0)) bpm" } ?? "—",
                           icon: "moon.fill", color: .indigo)
                if let d = deltaFC {
                    metricCell(label: "Delta FC",
                               value: (d >= 0 ? "+" : "") + "\(Int(d)) bpm",
                               icon: "arrow.up.arrow.down", color: deltaColor,
                               valueColor: deltaColor)
                }
            }
        }
    }

    private func metricCell(label: String, value: String,
                            icon: String, color: Color,
                            valueColor: Color = .white,
                            subtitle: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.3)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(valueColor)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Graphique Readiness 14j

private struct Recovery14dChart: View {
    let log: [RecoveryEntry]

    private struct ChartPoint: Identifiable {
        let id: String
        let label: String
        let score: Double
        let color: Color
    }

    private var ordered: [RecoveryEntry] { Array(log.prefix(14).reversed()) }

    private func readinessScore(for e: RecoveryEntry) -> Double? {
        var components: [(v: Double, w: Double)] = []
        if let h = e.hrv       { components.append((min(100, max(0, (h - 20) / 60 * 100)), 2.0)) }
        if let r = e.restingHr { components.append((max(0, min(100, (80 - r) / 35 * 100)), 1.5)) }
        if let f = e.fatigue   { components.append((max(0, (11 - f) / 10 * 100), 2.0)) }
        if let s = e.soreness  { components.append((max(0, (11 - s) / 10 * 100), 1.0)) }
        guard !components.isEmpty else { return nil }
        let tw = components.reduce(0) { $0 + $1.w }
        return components.reduce(0) { $0 + $1.v * $1.w } / tw
    }

    private func shortDate(_ e: RecoveryEntry) -> String {
        guard let d = e.date else { return "—" }
        let parts = d.split(separator: "-")
        guard parts.count == 3 else { return d }
        return "\(parts[2])/\(parts[1])"
    }

    private var chartPoints: [ChartPoint] {
        ordered.compactMap { e in
            guard let score = readinessScore(for: e) else { return nil }
            let color: Color = score >= 75 ? .green : score >= 50 ? .orange : .red
            return ChartPoint(id: e.id, label: shortDate(e), score: score, color: color)
        }
    }

    private var trend: (slope: Double, intercept: Double)? {
        let pts = chartPoints.enumerated().map { (x: Double($0.offset), y: $0.element.score) }
        guard pts.count >= 2 else { return nil }
        let n    = Double(pts.count)
        let sumX = pts.reduce(0) { $0 + $1.x }
        let sumY = pts.reduce(0) { $0 + $1.y }
        let sumXY = pts.reduce(0) { $0 + $1.x * $1.y }
        let sumX2 = pts.reduce(0) { $0 + $1.x * $1.x }
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else { return nil }
        let slope     = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return (slope, intercept)
    }

    var body: some View {
        let points      = chartPoints
        let trendResult = trend
        let trendLabel: String = {
            guard let t = trendResult else { return "Stable" }
            if t.slope > 0.5  { return "En hausse" }
            if t.slope < -0.5 { return "En baisse" }
            return "Stable"
        }()
        let trendColor: Color = {
            guard let t = trendResult else { return .orange }
            if t.slope > 0.5  { return .green }
            if t.slope < -0.5 { return .red }
            return .orange
        }()
        let trendIcon: String = {
            guard let t = trendResult else { return "arrow.right" }
            if t.slope > 0.5  { return "arrow.up.right" }
            if t.slope < -0.5 { return "arrow.down.right" }
            return "arrow.right"
        }()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("READINESS 14J")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: trendIcon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(trendColor)
                    Text(trendLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(trendColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(trendColor.opacity(0.12))
                .clipShape(Capsule())
            }

            Chart {
                ForEach(points) { p in
                    BarMark(
                        x: .value("Date", p.label),
                        y: .value("Score", p.score)
                    )
                    .foregroundStyle(p.color.opacity(0.75))
                    .cornerRadius(3)
                }

                if let t = trendResult, let first = points.first, let last = points.last {
                    let y0 = t.intercept
                    let yN = t.slope * Double(points.count - 1) + t.intercept
                    LineMark(
                        x: .value("Date", first.label),
                        y: .value("Tendance", max(0, min(100, y0))),
                        series: .value("S", "Tendance")
                    )
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                    LineMark(
                        x: .value("Date", last.label),
                        y: .value("Tendance", max(0, min(100, yN))),
                        series: .value("S", "Tendance")
                    )
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                }
            }
            .chartYScale(domain: 0.0...100.0)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel()
                        .font(.system(size: 9))
                        .foregroundStyle(Color.gray)
                }
            }
            .chartYAxis {
                AxisMarks(values: [0.0, 50.0, 75.0, 100.0]) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .frame(height: 130)
        }
    }
}

// MARK: - Section Sommeil (Étape 7)

private struct SleepSectionContent: View {
    let history: [SleepEntry]
    let stats: SleepStats?

    var body: some View {
        let todayEntry = history.first
        let avgDur     = stats?.avgDuration
        let avgQual    = stats?.avgQuality
        let streak     = stats?.streak ?? 0

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SOMMEIL")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                NavigationLink(destination: SleepView()) {
                    HStack(spacing: 4) {
                        Text("Voir plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.purple)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.purple.opacity(0.7))
                    }
                }
            }

            if let e = todayEntry {
                SleepTodayCard(entry: e)
            } else {
                Text("Aucune donnée de sommeil")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }

            if avgDur != nil || avgQual != nil || streak > 0 {
                HStack(spacing: 0) {
                    if let d = avgDur {
                        sleepStat(label: "Moy. durée",
                                  value: String(format: "%.1fh", d))
                        Spacer()
                    }
                    if let q = avgQual {
                        sleepStat(label: "Moy. qualité",
                                  value: String(format: "%.1f/5", q))
                        Spacer()
                    }
                    if streak > 0 {
                        sleepStat(label: "Streak", value: "\(streak)j")
                    }
                }
            }

            if history.count >= 2 {
                Sleep10dChart(history: history)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sleepStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Carte sommeil du jour

private struct SleepTodayCard: View {
    let entry: SleepEntry

    private func categoryLabel(_ cat: String) -> String {
        switch cat.lowercased() {
        case "optimal":                       return "Optimal"
        case "short":                         return "Court"
        case "very_short", "insufficient":   return "Insuffisant"
        case "long":                          return "Long"
        default:                              return cat.capitalized
        }
    }

    var body: some View {
        let durColor: Color = entry.durationHours >= 7 ? .green
                            : entry.durationHours >= 6 ? .orange : .red
        let qualDisplay = entry.qualityEmoji + " " + entry.qualityLabel
        let catLabel    = categoryLabel(entry.durationCategory)

        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: CGFloat(min(entry.durationHours / 10.0, 1.0)))
                    .stroke(durColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.1fh", entry.durationHours))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(durColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Cette nuit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                Text(catLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(durColor)
                Text(qualDisplay)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
    }
}

// MARK: - Graphique Sommeil 10j

private struct Sleep10dChart: View {
    let history: [SleepEntry]

    private struct SleepPoint: Identifiable {
        let id: String
        let label: String
        let duration: Double
        let quality: Int
        let durColor: Color
    }

    private func shortDate(_ d: String) -> String {
        let parts = d.split(separator: "-")
        guard parts.count == 3 else { return d }
        return "\(parts[2])/\(parts[1])"
    }

    private var chartPoints: [SleepPoint] {
        Array(history.prefix(10).reversed()).map { e in
            let color: Color = e.durationHours >= 7 ? .green
                             : e.durationHours >= 6 ? .orange : .red
            return SleepPoint(id: e.id, label: shortDate(e.date),
                              duration: e.durationHours, quality: e.quality,
                              durColor: color)
        }
    }

    var body: some View {
        let pts = chartPoints
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DURÉE & QUALITÉ — 10J")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 12) {
                    legendDot(color: .blue,   label: "Durée")
                    legendDot(color: .purple, label: "Qualité ×2")
                }
            }

            Chart {
                RuleMark(y: .value("Optimal", 7.0))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3]))
                    .foregroundStyle(Color.green.opacity(0.35))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("7h")
                            .font(.system(size: 8))
                            .foregroundColor(.green.opacity(0.6))
                    }

                ForEach(pts) { p in
                    BarMark(
                        x: .value("Date", p.label),
                        y: .value("Heures", p.duration)
                    )
                    .foregroundStyle(p.durColor.opacity(0.7))
                    .cornerRadius(3)
                }

                ForEach(pts.filter { $0.quality > 0 }) { p in
                    LineMark(
                        x: .value("Date", p.label),
                        y: .value("Qualité", Double(p.quality) * 2.0),
                        series: .value("S", "Qualité")
                    )
                    .foregroundStyle(Color.purple.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", p.label),
                        y: .value("Qualité", Double(p.quality) * 2.0)
                    )
                    .foregroundStyle(Color.purple)
                    .symbolSize(18)
                }
            }
            .chartYScale(domain: 0.0...12.0)
            .chartYAxis {
                AxisMarks(values: [0.0, 4.0, 6.0, 7.0, 8.0, 10.0]) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                        .foregroundStyle(Color.white.opacity(0.07))
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))h")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel()
                        .font(.system(size: 9))
                        .foregroundStyle(Color.gray)
                }
            }
            .frame(height: 140)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
    }
}

// MARK: - Suggestions dynamiques (Étape 8)

private struct DynamicSuggestionsSection: View {
    let energy: EnergyDaily?
    let recoveryToday: RecoveryEntry?
    let sleepToday: SleepEntry?
    let summary: DailySummary?
    let hrv: HRVAnalysis?

    private struct Suggestion: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let detail: String
        let priority: Int
    }

    private var suggestions: [Suggestion] {
        var list: [Suggestion] = []

        let balance       = energy?.balance ?? 0
        let balanceStatus = energy?.balanceStatus ?? ""
        let intake        = energy?.intake ?? 0
        let neat          = energy?.neat
        let sleepHours    = sleepToday?.durationHours ?? 0
        let fatigue       = recoveryToday?.fatigue ?? 0
        let soreness      = recoveryToday?.soreness ?? 0
        let readiness     = summary?.recoveryScore ?? hrv?.hrvScore
        let hrvZone       = hrv?.hrvZone ?? ""

        // ── Alertes prioritaires (rouge) ───────────────────────────────────
        if balance < -700 {
            list.append(Suggestion(
                icon: "exclamationmark.triangle.fill", color: .red,
                title: "Déficit sévère",
                detail: "Ton bilan est inférieur à -700 kcal — risque de perte musculaire. Augmente tes apports.",
                priority: 1
            ))
        } else if balanceStatus == "deficit_aggressive" {
            list.append(Suggestion(
                icon: "flame.fill", color: .red,
                title: "Déficit agressif",
                detail: "Déficit entre -500 et -700 kcal. Ajoute une collation protéinée pour préserver la masse musculaire.",
                priority: 2
            ))
        }

        // ── Alertes sommeil / récup (orange) ───────────────────────────────
        if sleepHours > 0 && sleepHours < 6 {
            list.append(Suggestion(
                icon: "bed.double.fill", color: .orange,
                title: "Sommeil insuffisant",
                detail: "Moins de 6h cette nuit — la récupération et la synthèse protéique sont compromises. Couche-toi plus tôt.",
                priority: 3
            ))
        }

        if fatigue >= 7 || soreness >= 7 {
            let field = fatigue >= soreness ? "fatigue" : "courbatures"
            list.append(Suggestion(
                icon: "bolt.slash.fill", color: .orange,
                title: "Récupération insuffisante",
                detail: "Score de \(field) élevé — envisage une séance légère ou un jour de repos actif aujourd'hui.",
                priority: 3
            ))
        }

        // ── Surplus trop élevé (orange) ────────────────────────────────────
        if balanceStatus == "surplus_high" {
            list.append(Suggestion(
                icon: "arrow.up.circle.fill", color: .orange,
                title: "Surplus trop élevé",
                detail: "Ton surplus dépasse +600 kcal. Ajoute 20-30 min de cardio ou réduis de ~200 kcal.",
                priority: 4
            ))
        }

        // ── Informations (bleu) ────────────────────────────────────────────
        if intake == 0 && !(energy?.isError ?? true) {
            list.append(Suggestion(
                icon: "fork.knife", color: .blue,
                title: "Nutrition non enregistrée",
                detail: "Aucun apport saisi aujourd'hui — log tes repas pour calculer ton bilan réel.",
                priority: 5
            ))
        }

        if neat == nil && !(energy?.isError ?? true) {
            list.append(Suggestion(
                icon: "applewatch", color: .blue,
                title: "NEAT non calculé",
                detail: "Porte ton Apple Watch pour mesurer tes pas et inclure le NEAT dans ton TDEE.",
                priority: 6
            ))
        }

        // ── HRV optimal (vert) ─────────────────────────────────────────────
        if hrvZone == "green" && sleepHours >= 7 {
            list.append(Suggestion(
                icon: "waveform.path.ecg.rectangle.fill", color: .green,
                title: "HRV optimal + bon sommeil",
                detail: "Système nerveux bien récupéré. Journée idéale pour une séance intense ou un record personnel.",
                priority: 7
            ))
        }

        // ── Journée optimale (vert) — affiché seulement si aucune alerte ──
        let hasAlert = list.contains { $0.priority <= 4 }
        if !hasAlert {
            let isBalanced = ["balanced", "deficit_optimal", "surplus_optimal"].contains(balanceStatus)
            let goodSleep  = sleepHours >= 7
            let goodRecov  = (readiness ?? 0) >= 65
            if isBalanced && goodSleep && goodRecov {
                list.append(Suggestion(
                    icon: "checkmark.seal.fill", color: .green,
                    title: "Journée optimale",
                    detail: "Bilan énergétique, sommeil et récupération sont tous au vert — continue sur cette lancée.",
                    priority: 8
                ))
            }
        }

        return list.sorted { $0.priority < $1.priority }.prefix(3).map { $0 }
    }

    var body: some View {
        let items = suggestions
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("SUGGESTIONS")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    ForEach(items) { s in
                        suggestionRow(s)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func suggestionRow(_ s: Suggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: s.icon)
                .font(.system(size: 16))
                .foregroundColor(s.color)
                .frame(width: 32, height: 32)
                .background(s.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(s.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(s.detail)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(s.color.opacity(0.2), lineWidth: 1)
        )
    }
}
