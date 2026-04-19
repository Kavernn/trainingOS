import SwiftUI

// MARK: - Main View

struct HealthDashboardView: View {
    @State private var week: [DailyHealthSummary] = []
    @State private var lifeStress: LifeStressScore?
    @State private var lifeStressTrend: [LifeStressScore] = []
    @State private var pssDueStatus: PSSDueStatus?
    @State private var isLoading = true
    @ObservedObject private var units = UnitSettings.shared
    // Live HealthKit values — shown when backend summary has no data for today
    @StateObject private var hk = HealthKitService.shared
    @State private var hkRestingHR: Double? = nil
    @State private var hkHRV: Double? = nil

    private var today: DailyHealthSummary? { week.first }
    private var yesterday: DailyHealthSummary? { week.dropFirst().first }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .cyan)

                if isLoading {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // PSS due nudge
                            if let pss = pssDueStatus, pss.isDue, let msg = pss.message {
                                NavigationLink(destination: PSSView()) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 14)).foregroundColor(.purple)
                                        Text(msg)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11)).foregroundColor(.gray)
                                    }
                                    .padding(12)
                                    .glassCard(color: .purple, intensity: 0.07)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.02)
                            }

                            // État du jour — Recovery + LSS fusionnés
                            if let t = today {
                                DayStatusHeaderView(summary: t, lifeStress: lifeStress)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.03)
                            }

                            // KPI grid: steps, sleep, HR, HRV + deltas vs hier
                            if let t = today {
                                HealthKPIGrid(summary: t, yesterday: yesterday,
                                             hkRestingHR: hkRestingHR, hkHRV: hkHRV)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.08)
                            }

                            // Life Stress — détail contexte (après KPI)
                            if let lss = lifeStress {
                                LifeStressCard(score: lss, trend: lifeStressTrend)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.1)
                            }

                            // Body weight
                            if let t = today, t.bodyWeight != nil || t.bodyFatPct != nil {
                                BodyMetricsCard(summary: t)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.13)
                            }

                            // Cardio
                            if let t = today, t.distanceKm != nil || t.activeMinutes != nil {
                                CardioSummaryCard(summary: t)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.15)
                            }

                            // Training
                            if let t = today, t.trainingRpe != nil || !(t.trainingExercises?.isEmpty ?? true) {
                                TrainingSummaryCard(summary: t)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.17)
                            }

                            // Nutrition
                            if let t = today, t.calories != nil {
                                NutritionSummaryHealthCard(summary: t)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.19)
                            }

                            // 7-day sleep chart
                            if week.filter({ $0.sleepDuration != nil }).count >= 2 {
                                WeeklySleepChart(week: week)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.22)
                            }

                            // 7-day steps chart
                            if week.filter({ $0.steps != nil }).count >= 2 {
                                WeeklyStepsChart(week: week)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.24)
                            }

                            Spacer(minLength: 40)
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, contentBottomPadding)
                    }
                    .refreshable { await loadData() }
                }
            }
            .navigationTitle("Santé")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        async let weekTask    = APIService.shared.fetchWeeklyHealthSummary(days: 7)
        async let lssTask     = APIService.shared.fetchLifeStressScore(forceRefresh: true)
        async let trendTask   = APIService.shared.fetchLifeStressTrend(days: 7)
        async let pssDueTask  = APIService.shared.checkPSSDue(type: "full")
        week            = (try? await weekTask)   ?? []
        lifeStress      = try? await lssTask
        lifeStressTrend = (try? await trendTask)  ?? []
        pssDueStatus    = try? await pssDueTask
        isLoading = false
        // Fetch live HK data in parallel — fills gaps when recovery not yet logged
        await fetchHKLive()
    }

    private func fetchHKLive() async {
        guard await hk.requestAuthorization() else { return }
        async let hr  = hk.fetchLatestRestingHR()
        async let hrv = hk.fetchLatestHRV()
        let (h, v) = await (hr, hrv)
        hkRestingHR = h
        hkHRV = v
    }
}

// MARK: - Recovery Score Ring

struct RecoveryScoreRing: View {
    let summary: DailyHealthSummary

    private var score: Double { summary.recoveryScore ?? 0 }
    private var scoreColor: Color {
        if score >= 7 { return .green }
        if score >= 5 { return .yellow }
        return .red
    }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 12)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: CGFloat(score / 10))
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 100, height: 100)
                    .animation(.easeOut(duration: 0.8), value: score)
                VStack(spacing: 2) {
                    if let s = summary.recoveryScore {
                        Text(String(format: "%.1f", s))
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(scoreColor)
                    } else {
                        Text("—")
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(.gray)
                    }
                    Text("/ 10").font(.system(size: 10)).foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SCORE DE RÉCUPÉRATION")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Text(scoreLabel)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(scoreColor)
                Text(summary.date)
                    .font(.system(size: 12)).foregroundColor(.gray)

                if let soreness = summary.soreness {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundColor(.orange)
                        Text("Courbatures : \(Int(soreness))/10").font(.system(size: 11)).foregroundColor(.gray)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .glassCard(color: scoreColor, intensity: 0.06)
        .cornerRadius(16)
    }

    private var scoreLabel: String {
        if summary.recoveryScore == nil { return "Aucune donnée" }
        if score >= 8 { return "Excellente" }
        if score >= 6 { return "Bonne" }
        if score >= 4 { return "Moyenne" }
        return "Faible"
    }
}

// MARK: - Data Sources

struct DataSourcesRow: View {
    let sources: [String]

    private func sourceConfig(_ s: String) -> (String, Color) {
        switch s {
        case "healthkit": return ("apple.logo", .white)
        case "wearable":  return ("applewatch", .cyan)
        default:          return ("hand.point.up.fill", .orange)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("SOURCES").font(.system(size: 9, weight: .bold)).tracking(2).foregroundColor(.gray)
            ForEach(sources, id: \.self) { src in
                let (icon, color) = sourceConfig(src)
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 10))
                    Text(src.capitalized).font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(color)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.12))
                .cornerRadius(6)
            }
            Spacer()
        }
    }
}

// MARK: - KPI Grid with deltas

struct HealthKPIGrid: View {
    let summary: DailyHealthSummary
    let yesterday: DailyHealthSummary?
    var hkRestingHR: Double? = nil
    var hkHRV: Double? = nil

    // Effective values: backend first, HealthKit as live fallback
    private var effectiveHR:  Double? { summary.restingHeartRate ?? hkRestingHR }
    private var effectiveHRV: Double? { summary.hrv ?? hkHRV }
    private var hrIsLive:  Bool { summary.restingHeartRate == nil && hkRestingHR != nil }
    private var hrvIsLive: Bool { summary.hrv == nil && hkHRV != nil }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if let steps = summary.steps {
                let delta = yesterday?.steps.map { steps - $0 }
                HealthKPICard(value: "\(steps)", label: "Pas", color: .green,
                              delta: delta.map { deltaInt($0, invertGood: false) })
            }
            if let sleep = summary.sleepDuration {
                let delta = yesterday?.sleepDuration.map { sleep - $0 }
                HealthKPICard(value: String(format: "%.1fh", sleep), label: "Sommeil", color: .indigo,
                              delta: delta.map { deltaDouble($0, unit: "h", invertGood: false) })
            }
            if let hr = effectiveHR {
                let delta = hrIsLive ? nil : yesterday?.restingHeartRate.map { hr - $0 }
                HealthKPICard(value: String(format: "%.0f bpm", hr),
                              label: hrIsLive ? "FC repos ◆ live" : "FC repos", color: .red,
                              delta: delta.map { deltaDouble($0, unit: "", invertGood: true) })
            }
            if let hrv = effectiveHRV {
                let delta = hrvIsLive ? nil : yesterday?.hrv.map { hrv - $0 }
                HealthKPICard(value: String(format: "%.0f ms", hrv),
                              label: hrvIsLive ? "HRV ◆ live" : "HRV", color: .cyan,
                              delta: delta.map { deltaDouble($0, unit: " ms", invertGood: false) })
            }
        }
    }

    private func deltaInt(_ val: Int, invertGood: Bool) -> (String, Color) {
        let isGood = invertGood ? val < 0 : val >= 0
        let sign = val >= 0 ? "↑+" : "↓"
        return ("\(sign)\(val)", isGood ? .green : .red)
    }

    private func deltaDouble(_ val: Double, unit: String, invertGood: Bool) -> (String, Color) {
        let isGood = invertGood ? val < 0 : val >= 0
        let sign = val >= 0 ? "↑+" : "↓"
        return ("\(sign)\(String(format: "%.1f", val))\(unit)", isGood ? .green : .red)
    }
}

struct HealthKPICard: View {
    let value: String
    let label: String
    let color: Color
    let delta: (String, Color)?

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black)).foregroundColor(color)
                .contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
            if let (str, col) = delta {
                Text(str)
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(col)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium)).tracking(1).foregroundColor(.gray).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard(color: color, intensity: 0.05).cornerRadius(12)
    }
}

// MARK: - Body Metrics

struct BodyMetricsCard: View {
    let summary: DailyHealthSummary
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMPOSITION CORPORELLE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 20) {
                if let w = summary.bodyWeight {
                    VStack(spacing: 2) {
                        Text(units.format(w))
                            .font(.system(size: 22, weight: .black)).foregroundColor(.orange)
                        Text("Poids").font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
                if let bf = summary.bodyFatPct {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f%%", bf))
                            .font(.system(size: 22, weight: .black)).foregroundColor(.blue)
                        Text("Masse grasse").font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
                if let wc = summary.waistCm {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f cm", wc))
                            .font(.system(size: 22, weight: .black)).foregroundColor(.purple)
                        Text("Tour taille").font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
                Spacer()
            }
        }
        .padding(14).glassCard(color: .orange, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Cardio Summary

struct CardioSummaryCard: View {
    let summary: DailyHealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CARDIO").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                if let t = summary.cardioType {
                    Text(t.capitalized).font(.system(size: 10, weight: .medium))
                        .foregroundColor(.teal).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.teal.opacity(0.12)).cornerRadius(4)
                }
            }
            HStack(spacing: 20) {
                if let d = summary.distanceKm {
                    MetricPill(value: String(format: "%.2f km", d), icon: "figure.run", color: .teal)
                }
                if let m = summary.activeMinutes {
                    MetricPill(value: String(format: "%.0f min", m), icon: "timer", color: .orange)
                }
                if let p = summary.pace {
                    MetricPill(value: p, icon: "speedometer", color: .blue)
                }
                if let hr = summary.heartRateAvg {
                    MetricPill(value: String(format: "%.0f bpm", hr), icon: "heart.fill", color: .red)
                }
            }
        }
        .padding(14).glassCard(color: .teal, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Training Summary

struct TrainingSummaryCard: View {
    let summary: DailyHealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ENTRAÎNEMENT MUSCULAIRE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 16) {
                if let rpe = summary.trainingRpe {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", rpe))
                            .font(.system(size: 22, weight: .black)).foregroundColor(.orange)
                        Text("RPE").font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
                if let dur = summary.trainingDurationMin {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f min", dur))
                            .font(.system(size: 22, weight: .black)).foregroundColor(.white)
                        Text("Durée").font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
                if let e = summary.trainingEnergyPre {
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= e ? "bolt.fill" : "bolt")
                                    .font(.system(size: 12))
                                    .foregroundColor(i <= e ? .yellow : .gray.opacity(0.3))
                            }
                        }
                        Text("Énergie").font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
                Spacer()
            }
            if let exos = summary.trainingExercises, !exos.isEmpty {
                Text(exos.prefix(4).joined(separator: " · "))
                    .font(.system(size: 11)).foregroundColor(.gray)
                    .lineLimit(2)
            }
        }
        .padding(14).glassCard(color: .orange, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Nutrition Summary

struct NutritionSummaryHealthCard: View {
    let summary: DailyHealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NUTRITION").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let m = summary.meals {
                    Text("\(m) repas").font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            HStack(spacing: 12) {
                if let cal = summary.calories {
                    MacroChip(value: "\(Int(cal))", label: "kcal", color: .orange)
                }
                if let p = summary.protein {
                    MacroChip(value: "\(Int(p))g", label: "protéines", color: .red)
                }
                if let c = summary.carbs {
                    MacroChip(value: "\(Int(c))g", label: "glucides", color: .yellow)
                }
                if let f = summary.fat {
                    MacroChip(value: "\(Int(f))g", label: "lipides", color: .blue)
                }
            }
        }
        .padding(14).glassCard(color: .orange, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Weekly Sleep Chart (interactive)

struct WeeklySleepChart: View {
    let week: [DailyHealthSummary]
    @State private var selectedDay: DailyHealthSummary?

    private var data: [(String, Double, DailyHealthSummary)] {
        week.compactMap { d in
            guard let h = d.sleepDuration else { return nil }
            return (String(d.date.suffix(5)), h, d)
        }.reversed()
    }

    var maxH: Double { max(data.map(\.1).max() ?? 1, 9) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SOMMEIL — 7 DERNIERS JOURS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("Tap pour détails")
                    .font(.system(size: 9)).foregroundColor(.gray.opacity(0.6))
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.0) { i, item in
                    let pct = maxH > 0 ? item.1 / maxH : 0
                    let color: Color = item.1 >= 7 ? .indigo : (item.1 >= 5 ? .orange : .red)
                    let isLast = i == data.count - 1
                    VStack(spacing: 3) {
                        Text(String(format: "%.0fh", item.1))
                            .font(.system(size: 8)).foregroundColor(color.opacity(0.8))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(isLast ? 1 : 0.5))
                            .frame(height: max(CGFloat(pct) * 60, 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(color, lineWidth: selectedDay?.date == item.2.date ? 2 : 0)
                            )
                        Text(item.0).font(.system(size: 8)).foregroundColor(.gray).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
                    .onTapGesture { selectedDay = item.2 }
                }
            }
            .frame(height: 80)
        }
        .padding(14).glassCard(color: .indigo, intensity: 0.05).cornerRadius(14)
        .sheet(item: $selectedDay) { day in
            HealthDayDetailSheet(day: day)
        }
    }
}

// MARK: - Weekly Steps Chart (interactive)

struct WeeklyStepsChart: View {
    let week: [DailyHealthSummary]
    @State private var selectedDay: DailyHealthSummary?

    private var data: [(String, Int, DailyHealthSummary)] {
        week.compactMap { d in
            guard let s = d.steps else { return nil }
            return (String(d.date.suffix(5)), s, d)
        }.reversed()
    }

    var maxSteps: Int { max(data.map(\.1).max() ?? 1, 10000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PAS — 7 DERNIERS JOURS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("Tap pour détails")
                    .font(.system(size: 9)).foregroundColor(.gray.opacity(0.6))
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.0) { i, item in
                    let pct = Double(item.1) / Double(maxSteps)
                    let color: Color = item.1 >= 10000 ? .green : (item.1 >= 6000 ? .orange : .red)
                    let isLast = i == data.count - 1
                    VStack(spacing: 3) {
                        Text(item.1 >= 1000 ? "\(item.1 / 1000)k" : "\(item.1)")
                            .font(.system(size: 8)).foregroundColor(color.opacity(0.8))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(isLast ? 1 : 0.5))
                            .frame(height: max(CGFloat(pct) * 60, 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(color, lineWidth: selectedDay?.date == item.2.date ? 2 : 0)
                            )
                        Text(item.0).font(.system(size: 8)).foregroundColor(.gray).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
                    .onTapGesture { selectedDay = item.2 }
                }
            }
            .frame(height: 80)
        }
        .padding(14).glassCard(color: .green, intensity: 0.05).cornerRadius(14)
        .sheet(item: $selectedDay) { day in
            HealthDayDetailSheet(day: day)
        }
    }
}

// MARK: - Sub-components

struct MetricPill: View {
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color)
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1)).cornerRadius(8)
    }
}

struct MacroChip: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(color)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Life Stress Card

struct LifeStressCard: View {
    let score: LifeStressScore
    let trend: [LifeStressScore]

    private var color: Color {
        switch score.score {
        case 80...: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIFE STRESS SCORE")
                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                    Text(stressLabel)
                        .font(.system(size: 16, weight: .bold)).foregroundColor(color)
                }
                Spacer()
                // Score ring
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.15), lineWidth: 10)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: CGFloat(score.score / 100))
                        .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 72, height: 72)
                        .animation(.easeOut(duration: 0.8), value: score.score)
                    Text(String(format: "%.0f", score.score))
                        .font(.system(size: 20, weight: .black)).foregroundColor(color)
                }
            }

            // Flags
            let activeFlags = flagItems.filter(\.1)
            if !activeFlags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(activeFlags, id: \.0) { label, _ in
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(5)
                    }
                }
            }

            // Recommendations
            if !score.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(score.recommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 11)).foregroundColor(.yellow)
                            Text(rec)
                                .font(.system(size: 12)).foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // 7-day trend
            if trend.count >= 2 {
                LifeStressTrendChart(trend: trend)
            }

            // Data coverage
            if score.dataCoverage < 0.6 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10)).foregroundColor(.orange)
                    Text("Données partielles (\(Int(score.dataCoverage * 100))% de couverture)")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
            }
        }
        .padding(16)
        .glassCard(color: color, intensity: 0.06)
        .cornerRadius(16)
    }

    private var stressLabel: String {
        switch score.score {
        case 80...: return "Récupération optimale"
        case 60..<80: return "Bonne forme"
        case 40..<60: return "Fatigue modérée"
        default: return "Surmenage détecté"
        }
    }

    private var flagItems: [(String, Bool)] {
        [
            ("Chute HRV",          score.flags.hrvDrop),
            ("Manque sommeil",     score.flags.sleepDeprivation),
            ("Surcharge d'entraîn.", score.flags.trainingOverload),
        ]
    }
}

// MARK: - Life Stress Trend Chart

struct LifeStressTrendChart: View {
    let trend: [LifeStressScore]

    private var data: [(String, Double)] {
        trend.reversed().map { (String($0.date.suffix(5)), $0.score) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TENDANCE 7 JOURS")
                .font(.system(size: 9, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(data.enumerated()), id: \.0) { i, item in
                    let pct = item.1 / 100.0
                    let barColor: Color = item.1 >= 80 ? .green : (item.1 >= 60 ? .yellow : (item.1 >= 40 ? .orange : .red))
                    let isLast = i == data.count - 1
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", item.1))
                            .font(.system(size: 7)).foregroundColor(barColor.opacity(0.8))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor.opacity(isLast ? 1.0 : 0.5))
                            .frame(height: max(CGFloat(pct) * 48, 3))
                        Text(item.0).font(.system(size: 7)).foregroundColor(.gray).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 64, alignment: .bottom)
                }
            }
            .frame(height: 64)
        }
    }
}

// MARK: - Day Status Header (Fix 1: Recovery hero + LSS secondary)

struct DayStatusHeaderView: View {
    let summary: DailyHealthSummary
    let lifeStress: LifeStressScore?

    private var recoveryScore: Double { summary.recoveryScore ?? 0 }
    private var recoveryColor: Color {
        if recoveryScore >= 7 { return .green }
        if recoveryScore >= 5 { return .yellow }
        return .red
    }
    private var recoveryLabel: String {
        guard summary.recoveryScore != nil else { return "Aucune donnée" }
        if recoveryScore >= 8 { return "Excellente" }
        if recoveryScore >= 6 { return "Bonne" }
        if recoveryScore >= 4 { return "Moyenne" }
        return "Faible"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                // Recovery ring — hero
                ZStack {
                    Circle()
                        .stroke(recoveryColor.opacity(0.15), lineWidth: 12)
                        .frame(width: 90, height: 90)
                    Circle()
                        .trim(from: 0, to: CGFloat(recoveryScore / 10))
                        .stroke(recoveryColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 90)
                        .animation(.easeOut(duration: 0.8), value: recoveryScore)
                    VStack(spacing: 1) {
                        if let s = summary.recoveryScore {
                            Text(String(format: "%.1f", s))
                                .font(.system(size: 22, weight: .black)).foregroundColor(recoveryColor)
                        } else {
                            Text("—").font(.system(size: 22, weight: .black)).foregroundColor(.gray)
                        }
                        Text("/ 10").font(.system(size: 9)).foregroundColor(.gray)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ÉTAT DU JOUR")
                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                    Text(recoveryLabel)
                        .font(.system(size: 20, weight: .bold)).foregroundColor(recoveryColor)

                    // LSS — indicateur secondaire
                    if let lss = lifeStress {
                        let lssColor: Color = lss.score >= 80 ? .green : lss.score >= 60 ? .yellow : lss.score >= 40 ? .orange : .red
                        let lssLabel: String = lss.score >= 80 ? "Récup. optimale" : lss.score >= 60 ? "Bonne forme" : lss.score >= 40 ? "Fatigue modérée" : "Surmenage"
                        HStack(spacing: 4) {
                            Text("Life Stress")
                                .font(.system(size: 11)).foregroundColor(.gray)
                            Text(String(format: "%.0f", lss.score))
                                .font(.system(size: 11, weight: .bold)).foregroundColor(lssColor)
                            Text("·").font(.system(size: 11)).foregroundColor(.gray)
                            Text(lssLabel)
                                .font(.system(size: 11)).foregroundColor(lssColor)
                        }
                    }

                    if let soreness = summary.soreness {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundColor(.orange)
                            Text("Courbatures \(Int(soreness))/10")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
            }

            // Flags LSS actifs
            if let lss = lifeStress {
                let active = [("Chute HRV", lss.flags.hrvDrop),
                              ("Manque sommeil", lss.flags.sleepDeprivation),
                              ("Surcharge entraîn.", lss.flags.trainingOverload)]
                    .filter(\.1)
                if !active.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(active, id: \.0) { label, _ in
                            Text(label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(5)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .glassCard(color: recoveryColor, intensity: 0.07)
        .cornerRadius(16)
    }
}

// MARK: - Health Day Detail Sheet (Fix 5: tap on bar)

struct HealthDayDetailSheet: View {
    let day: DailyHealthSummary
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        NavigationStack {
            List {
                if let sleep = day.sleepDuration {
                    Section("Sommeil") {
                        DetailMetricRow(icon: "moon.fill", color: .indigo, label: "Durée",
                                        value: String(format: "%.1fh", sleep))
                        if let q = day.sleepQuality {
                            DetailMetricRow(icon: "star.fill", color: .yellow, label: "Qualité",
                                            value: String(format: "%.0f%%", q))
                        }
                    }
                }
                Section("Activité") {
                    if let steps = day.steps {
                        DetailMetricRow(icon: "figure.walk", color: .green, label: "Pas",
                                        value: "\(steps)" + (steps >= 10000 ? " ✓" : ""))
                    }
                    if let active = day.activeMinutes {
                        DetailMetricRow(icon: "timer", color: .orange, label: "Minutes actives",
                                        value: String(format: "%.0f min", active))
                    }
                }
                Section("Cardio") {
                    if let hr = day.restingHeartRate {
                        DetailMetricRow(icon: "heart.fill", color: .red, label: "FC repos",
                                        value: String(format: "%.0f bpm", hr))
                    }
                    if let hrv = day.hrv {
                        DetailMetricRow(icon: "waveform.path.ecg", color: .cyan, label: "HRV",
                                        value: String(format: "%.0f ms", hrv))
                    }
                }
                if day.recoveryScore != nil || day.soreness != nil {
                    Section("Récupération") {
                        if let rec = day.recoveryScore {
                            DetailMetricRow(icon: "bolt.fill", color: .orange, label: "Score",
                                            value: String(format: "%.1f / 10", rec))
                        }
                        if let soreness = day.soreness {
                            DetailMetricRow(icon: "figure.strengthtraining.traditional", color: .orange,
                                            label: "Courbatures", value: "\(Int(soreness)) / 10")
                        }
                    }
                }
                if let w = day.bodyWeight {
                    Section("Corps") {
                        DetailMetricRow(icon: "scalemass.fill", color: .orange, label: "Poids",
                                        value: units.format(w))
                        if let bf = day.bodyFatPct {
                            DetailMetricRow(icon: "chart.pie.fill", color: .blue, label: "Masse grasse",
                                            value: String(format: "%.1f%%", bf))
                        }
                    }
                }
            }
            .navigationTitle(day.date)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

private struct DetailMetricRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}
