import SwiftUI

// MARK: - Main View

struct HealthDashboardView: View {
    @State private var week: [DailyHealthSummary] = []
    @State private var lifeStress: LifeStressScore?
    @State private var lifeStressTrend: [LifeStressScore] = []
    @State private var pssDueStatus: PSSDueStatus?
    @State private var isLoading = true
    @ObservedObject private var units = UnitSettings.shared

    private var today: DailyHealthSummary? { week.first }

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

                            // Life Stress Score
                            if let lss = lifeStress {
                                LifeStressCard(score: lss, trend: lifeStressTrend)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.03)
                            }

                            // Recovery score ring
                            if let t = today {
                                RecoveryScoreRing(summary: t)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.05)
                            }

                            // Sources badge row
                            if let sources = today?.dataSources, !sources.isEmpty {
                                DataSourcesRow(sources: sources)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.08)
                            }

                            // KPI grid: steps, sleep, HR, HRV
                            if let t = today {
                                HealthKPIGrid(summary: t)
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

// MARK: - KPI Grid

struct HealthKPIGrid: View {
    let summary: DailyHealthSummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if let steps = summary.steps {
                KPICard(value: "\(steps)", label: "Pas", color: .green)
            }
            if let sleep = summary.sleepDuration {
                KPICard(value: String(format: "%.1fh", sleep), label: "Sommeil", color: .indigo)
            }
            if let hr = summary.restingHeartRate {
                KPICard(value: String(format: "%.0f bpm", hr), label: "FC repos", color: .red)
            }
            if let hrv = summary.hrv {
                KPICard(value: String(format: "%.0f ms", hrv), label: "HRV", color: .cyan)
            }
        }
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

// MARK: - Weekly Sleep Chart

struct WeeklySleepChart: View {
    let week: [DailyHealthSummary]

    private var data: [(String, Double)] {
        week.compactMap { d in
            guard let h = d.sleepDuration else { return nil }
            let label = String(d.date.suffix(5))
            return (label, h)
        }.reversed()
    }

    var maxH: Double { max(data.map(\.1).max() ?? 1, 9) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOMMEIL — 7 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
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
                        Text(item.0).font(.system(size: 8)).foregroundColor(.gray).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
                }
            }
            .frame(height: 80)
        }
        .padding(14).glassCard(color: .indigo, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Weekly Steps Chart

struct WeeklyStepsChart: View {
    let week: [DailyHealthSummary]

    private var data: [(String, Int)] {
        week.compactMap { d in
            guard let s = d.steps else { return nil }
            return (String(d.date.suffix(5)), s)
        }.reversed()
    }

    var maxSteps: Int { max(data.map(\.1).max() ?? 1, 10000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAS — 7 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
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
                        Text(item.0).font(.system(size: 8)).foregroundColor(.gray).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
                }
            }
            .frame(height: 80)
        }
        .padding(14).glassCard(color: .green, intensity: 0.05).cornerRadius(14)
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
