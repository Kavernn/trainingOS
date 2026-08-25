import SwiftUI
import Charts

// MARK: - Main View

struct HealthDashboardView: View {
    // Shell
    @State private var activeTab: Int = 0
    @State private var isLoading = true
    @ObservedObject private var units = UnitSettings.shared
    @ObservedObject private var hk = HealthKitService.shared
    @ObservedObject private var watchSync = WatchSyncService.shared

    // Data — backend
    @State private var week: [DailyHealthSummary] = []
    @State private var lifeStress: LifeStressScore?
    @State private var lifeStressTrend: [LifeStressScore] = []
    @State private var pssDueStatus: PSSDueStatus?
    @State private var readiness: ReadinessResponse?
    @State private var recoveryLog: [RecoveryEntry] = []
    @State private var sleepStats: SleepStats?
    @State private var energy: EnergyDaily?
    @State private var energyHistory: [EnergyHistoryDay] = []
    @State private var hrvAnalysis: HRVAnalysis?
    @State private var sleepHistory: [SleepEntry] = []
    @State private var readinessHistory: [ReadinessHistoryPoint] = []
    @State private var editTarget: RecoveryEntry?

    // Data — live HealthKit
    @State private var hkRestingHR: Double? = nil
    @State private var hkHRV: Double? = nil
    @State private var hkSpO2: Double? = nil
    @State private var hkWristTemp: Double? = nil
    @State private var hkActiveEnergy: Double? = nil

    // Sync + sheet
    @State private var syncError: String? = nil
    @State private var isSyncing: Bool = false
    @State private var showLogSheet: Bool = false

    private var today: DailyHealthSummary? { week.first }
    private var yesterday: DailyHealthSummary? { week.dropFirst().first }
    private var todayRecovery: RecoveryEntry? { recoveryLog.first }
    private var dailySummary: DailySummary? {
        readiness.map { DailySummary(recoveryScore: Double($0.score)) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .statusCyan)

                VStack(spacing: 0) {
                    HealthTabPicker(activeTab: $activeTab)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                    if isLoading {
                        Spacer()
                        AppLoadingView()
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                switch activeTab {
                                case 0: todayTab
                                case 1: energyTab
                                default: historyTab
                                }
                                Spacer(minLength: 40)
                            }
                            .padding(.vertical, 16)
                            .padding(.bottom, contentBottomPadding)
                            .animation(.easeInOut(duration: 0.2), value: activeTab)
                        }
                        .refreshable { await loadData() }
                    }
                }
            }
            .navigationTitle("Santé")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showLogSheet) {
                LogRecoverySheet(prefillEntry: todayRecovery, onSaved: { await loadData() })
            }
        }
        .task { await loadData() }
    }

    // MARK: - Tab 0 — Aujourd'hui

    @ViewBuilder
    private var todayTab: some View {
        HKSyncHeader(watchSync: watchSync, isSyncing: isSyncing, syncError: syncError,
                     onSync: { Task { await syncNow() } })
            .padding(.horizontal, 16)
            .appearAnimation(delay: 0.02)

        if let pss = pssDueStatus, pss.isDue, let msg = pss.message {
            NavigationLink(destination: PSSView()) {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.appLabel.weight(.regular)).foregroundColor(.statusPurple)
                    Text(msg)
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(.appTextPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appCaption).foregroundColor(.gray)
                }
                .padding(12)
                .glassCard(color: .statusPurple, intensity: 0.07)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .appearAnimation(delay: 0.03)
        }

        ReadinessHero(score: readiness?.score)
            .padding(.horizontal, 16)
            .appearAnimation(delay: 0.04)

        if let t = today {
            HealthKPIGrid(summary: t, yesterday: yesterday,
                          hkRestingHR: hkRestingHR, hkHRV: hkHRV,
                          hkSpO2: hkSpO2, hkWristTemp: hkWristTemp,
                          hkActiveEnergy: hkActiveEnergy)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.06)
        }

        if let t = today, t.bodyWeight != nil || t.bodyFatPct != nil {
            BodyMetricsCard(summary: t)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.08)
        }

        if let lss = lifeStress {
            LifeStressCard(score: lss, trend: lifeStressTrend)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.10)
        }

        if let stats = sleepStats {
            SleepStatsRow(stats: stats)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.12)
        }

        if let entry = todayRecovery {
            SecondaryMetricsGrid(entry: entry)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.14)
            DeltaFCCard(entry: entry)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.16)
        }

        Button { showLogSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "pencil.line").font(.appCaption)
                Text("Compléter ma récup").font(.appCaption.weight(.semibold))
            }
            .foregroundColor(Color.appOnSurface.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.appSurfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .appearAnimation(delay: 0.18)
    }

    // MARK: - Tab 1 — Énergie

    @ViewBuilder
    private var energyTab: some View {
        VStack(spacing: 16) {
            if let e = energy {
                if e.isError {
                    EnergyErrorCard(message: e.message ?? "Complète ton profil pour calculer ton bilan.")
                } else {
                    EnergyHeaderCard(energy: e)
                    EnergyBreakdownCard(energy: e, activeEnergy: todayRecovery?.activeEnergy)
                }
            } else {
                EnergyErrorCard(message: "Impossible de charger le bilan énergétique.")
            }

            if energyHistory.count >= 2 {
                EnergyChartSection(history: energyHistory, targetBalance: energy?.targetBalance)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)

        DynamicSuggestionsSection(
            energy: energy,
            recoveryToday: todayRecovery,
            sleepToday: sleepHistory.first,
            summary: dailySummary,
            hrv: hrvAnalysis
        )
    }

    // MARK: - Tab 2 — Historique

    @ViewBuilder
    private var historyTab: some View {
        VStack(spacing: 16) {
            if !readinessHistory.isEmpty {
                Recovery14dChart(history: readinessHistory)
                    .padding(14)
                    .glassCard()
                    .padding(.horizontal, 16)
            }

            let entries30 = Array(recoveryLog.prefix(30))
            let sleepPts  = Array(entries30.filter { $0.sleepHours != nil }.prefix(30))
            if sleepPts.count >= 2 {
                RecoverySleepBarChart(entries: sleepPts, goalHours: 8.0)
                    .padding(.horizontal, 16)
            }

            if week.filter({ $0.steps != nil }).count >= 2 {
                WeeklyStepsChart(week: week)
                    .padding(.horizontal, 16)
            }

            if !entries30.isEmpty {
                VStack(spacing: 0) {
                    ForEach(entries30) { entry in
                        AccordionRow(entry: entry, onEdit: { editTarget = entry })
                        if entry.id != entries30.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            } else {
                Text("Aucun log de récupération pour le moment.")
                    .font(.appCaption)
                    .foregroundColor(.gray)
                    .padding(.top, 40)
            }
        }
        .sheet(item: $editTarget) { entry in
            LogRecoverySheet(prefillEntry: entry, onSaved: { await loadData() })
        }
    }

    // MARK: - Data

    private func loadData() async {
        isLoading = true
        // sequential — async let LIFO crash on iOS 26 beta
        week            = (try? await APIService.shared.fetchWeeklyHealthSummary(days: 7)) ?? []
        lifeStress      = try? await APIService.shared.fetchLifeStressScore(forceRefresh: true)
        lifeStressTrend = (try? await APIService.shared.fetchLifeStressTrend(days: 7)) ?? []
        pssDueStatus    = try? await APIService.shared.checkPSSDue(type: "full")
        readiness       = try? await APIService.shared.fetchReadiness()
        recoveryLog     = (try? await APIService.shared.fetchRecoveryData()) ?? []
        sleepStats      = try? await APIService.shared.fetchSleepStats()
        energy          = try? await APIService.shared.fetchEnergyDaily()
        energyHistory   = (try? await APIService.shared.fetchEnergyHistory()) ?? []
        hrvAnalysis     = try? await APIService.shared.fetchHRVAnalysis()
        let sleepPg     = try? await APIService.shared.fetchSleepHistory(limit: 10)
        sleepHistory    = sleepPg?.items ?? []
        readinessHistory = (try? await APIService.shared.fetchReadinessHistory(days: 14)) ?? []
        isLoading = false
        await fetchHKLive()
    }

    private func fetchHKLive() async {
        guard await hk.requestAuthorization() else { return }
        // sequential — async let LIFO crash on iOS 26 beta
        hkRestingHR    = await hk.fetchLatestRestingHR()
        hkHRV          = await hk.fetchLatestHRV()
        hkSpO2         = await hk.fetchLatestSpO2()
        hkWristTemp    = await hk.fetchLatestWristTemperature()
        hkActiveEnergy = await hk.fetchTodayActiveEnergy()
    }

    // MARK: - HK sync (copié en local depuis EnergyRecoveryView post Lot 2)
#if !targetEnvironment(macCatalyst)
    private func syncNow() async {
        syncError = nil
        isSyncing = true
        defer { isSyncing = false }
        let authorized = await hk.requestAuthorization()
        guard authorized else {
            syncError = "Accès refusé — activer dans Réglages > Confidentialité > Santé"
            return
        }
        let snapshot = await hk.fetchTodayHealthSnapshot()
        do {
            try await APIService.shared.syncWearableData(snapshot)
        } catch {
            syncError = "Erreur sync — réessaie"
        }
        await loadData()
    }
#else
    private func syncNow() async {}
#endif
}

// MARK: - Tab Picker

private struct HealthTabPicker: View {
    @Binding var activeTab: Int
    private let titles = ["Aujourd'hui", "Énergie", "Historique"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { i in
                let selected = activeTab == i
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { activeTab = i }
                } label: {
                    Text(titles[i])
                        .font(.appLabel.weight(selected ? .bold : .medium))
                        .foregroundColor(selected ? Color.onAccent : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? Color.statusCyan : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(3)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Recovery Score Ring

struct RecoveryScoreRing: View {
    let summary: DailyHealthSummary

    private var score: Double { summary.recoveryScore ?? 0 }
    private var scoreColor: Color {
        if score >= 70 { return .statusGreen }
        if score >= 50 { return .statusYellow }
        return .statusRed
    }

    var body: some View {
        HStack(spacing: 20) {
            ProgressRing(progress: score / 100, color: scoreColor, size: 100, lineWidth: 12,
                         backgroundColor: scoreColor.opacity(0.15), animation: .easeOut(duration: 0.8)) {
                VStack(spacing: 2) {
                    // KPI hero — .black volontaire (override displayWeight), densité > variance thème
                    if let s = summary.recoveryScore {
                        Text("\(Int(s))")
                            .font(.appTitle.weight(.black))
                            .foregroundColor(scoreColor)
                    } else {
                        Text("—")
                            .font(.appTitle.weight(.black))
                            .foregroundColor(.gray)
                    }
                    Text("/ 100").font(.appCaption).foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SCORE DE RÉCUPÉRATION")
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Text(scoreLabel)
                    .font(.appHeadline.weight(.bold))
                    .foregroundColor(scoreColor)
                Text(summary.date)
                    .font(.appCaption).foregroundColor(.gray)

                if let soreness = summary.soreness {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.appCaption).foregroundColor(Color.forge)
                        Text("Courbatures : \(Int(soreness))/10").font(.appCaption).foregroundColor(.gray)
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
        if score >= 80 { return "Excellente" }
        if score >= 60 { return "Bonne" }
        if score >= 40 { return "Moyenne" }
        return "Faible"
    }
}

// MARK: - Data Sources

struct DataSourcesRow: View {
    let sources: [String]

    private func sourceConfig(_ s: String) -> (String, Color) {
        switch s {
        case "healthkit": return ("apple.logo", .white)
        case "wearable":  return ("applewatch", .statusCyan)
        default:          return ("hand.point.up.fill", Color.forge)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("SOURCES").font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
            ForEach(sources, id: \.self) { src in
                let (icon, color) = sourceConfig(src)
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.appCaption)
                    Text(src.capitalized).font(.appCaption.weight(.medium))
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
    var hkSpO2: Double? = nil
    var hkWristTemp: Double? = nil
    var hkActiveEnergy: Double? = nil

    @AppStorage("steps_daily_goal") private var stepsGoal: Int = 10000

    // Effective values: backend first, HealthKit as live fallback
    private var effectiveHR:  Double? { summary.restingHeartRate ?? hkRestingHR }
    private var effectiveHRV: Double? { summary.hrv ?? hkHRV }
    private var hrIsLive:  Bool { summary.restingHeartRate == nil && hkRestingHR != nil }
    private var hrvIsLive: Bool { summary.hrv == nil && hkHRV != nil }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if let steps = summary.steps {
                let delta = yesterday?.steps.map { steps - $0 }
                let goalPct = stepsGoal > 0 ? "\(min(100, steps * 100 / stepsGoal))%" : nil
                StatCard(value: "\(steps)", label: "Pas", color: .statusGreen,
                         subtitle: goalPct.map { steps >= stepsGoal ? "✓ objectif" : "\($0) de l'objectif" },
                         delta: delta.map { deltaInt($0, invertGood: false) })
            }
            if let sleep = summary.sleepDuration {
                let delta = yesterday?.sleepDuration.map { sleep - $0 }
                StatCard(value: String(format: "%.1fh", sleep), label: "Sommeil", color: .statusBlue,
                         delta: delta.map { deltaDouble($0, unit: "h", invertGood: false) })
            }
            if let hr = effectiveHR {
                let delta = hrIsLive ? nil : yesterday?.restingHeartRate.map { hr - $0 }
                StatCard(value: String(format: "%.0f bpm", hr),
                         label: hrIsLive ? "FC repos ◆ live" : "FC repos", color: .statusRed,
                         delta: delta.map { deltaDouble($0, unit: "", invertGood: true) })
            }
            if let hrv = effectiveHRV {
                let delta = hrvIsLive ? nil : yesterday?.hrv.map { hrv - $0 }
                StatCard(value: String(format: "%.0f ms", hrv),
                         label: hrvIsLive ? "HRV ◆ live" : "HRV", color: .statusCyan,
                         delta: delta.map { deltaDouble($0, unit: " ms", invertGood: false) })
            }
            if let sp = hkSpO2 {
                StatCard(value: String(format: "%.0f%%", sp), label: "SpO₂ ◆ live", color: .statusCyan)
            }
            if let wt = hkWristTemp {
                StatCard(value: String(format: "%+.1f°C", wt), label: "Temp. poignet ◆ live", color: .statusPurple)
            }
            if let ae = hkActiveEnergy {
                StatCard(value: String(format: "%.0f kcal", ae), label: "Énergie active ◆ live", color: Color.forge)
            }
        }
    }

    private func deltaInt(_ val: Int, invertGood: Bool) -> (String, Color) {
        let isGood = invertGood ? val < 0 : val >= 0
        let sign = val >= 0 ? "↑+" : "↓"
        return ("\(sign)\(val)", isGood ? .statusGreen : .statusRed)
    }

    private func deltaDouble(_ val: Double, unit: String, invertGood: Bool) -> (String, Color) {
        let isGood = invertGood ? val < 0 : val >= 0
        let sign = val >= 0 ? "↑+" : "↓"
        return ("\(sign)\(String(format: "%.1f", val))\(unit)", isGood ? .statusGreen : .statusRed)
    }
}

// MARK: - Body Metrics

struct BodyMetricsCard: View {
    let summary: DailyHealthSummary
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMPOSITION CORPORELLE")
                .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 20) {
                if let w = summary.bodyWeight {
                    VStack(spacing: 2) {
                        Text(units.format(w))
                            .font(.appTitle.weight(.black)).foregroundColor(Color.forge)
                        Text("Poids").font(.appCaption).foregroundColor(.gray)
                    }
                }
                if let bf = summary.bodyFatPct {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f%%", bf))
                            .font(.appTitle.weight(.black)).foregroundColor(.statusBlue)
                        Text("Masse grasse").font(.appCaption).foregroundColor(.gray)
                    }
                }
                if let wc = summary.waistCm {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f cm", wc))
                            .font(.appTitle.weight(.black)).foregroundColor(.statusPurple)
                        Text("Tour taille").font(.appCaption).foregroundColor(.gray)
                    }
                }
                Spacer()
            }
        }
        .padding(14).glassCard(color: Color.forge, intensity: 0.05)
    }
}

// MARK: - Cardio Summary

struct CardioSummaryCard: View {
    let summary: DailyHealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CARDIO").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                if let t = summary.cardioType {
                    Text(t.capitalized).font(.appCaption.weight(.medium))
                        .foregroundColor(.statusCyan).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.statusCyan.opacity(0.12)).cornerRadius(4)
                }
            }
            HStack(spacing: 20) {
                if let d = summary.distanceKm {
                    MetricPill(value: String(format: "%.2f km", d), icon: "figure.run", color: .teal)
                }
                if let m = summary.activeMinutes {
                    MetricPill(value: String(format: "%.0f min", m), icon: "timer", color: Color.forge)
                }
                if let p = summary.pace {
                    MetricPill(value: p, icon: "speedometer", color: .statusBlue)
                }
                if let hr = summary.heartRateAvg {
                    MetricPill(value: String(format: "%.0f bpm", hr), icon: "heart.fill", color: .statusRed)
                }
            }
        }
        .padding(14).glassCard(color: .teal, intensity: 0.05)
    }
}

// MARK: - Training Summary

struct TrainingSummaryCard: View {
    let summary: DailyHealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ENTRAÎNEMENT MUSCULAIRE")
                .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 16) {
                if let rpe = summary.trainingRpe {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", rpe))
                            .font(.appTitle.weight(.black)).foregroundColor(Color.forge)
                        Text("RPE").font(.appCaption).foregroundColor(.gray)
                    }
                }
                if let dur = summary.trainingDurationMin {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f min", dur))
                            .font(.appTitle.weight(.black)).foregroundColor(.appTextPrimary)
                        Text("Durée").font(.appCaption).foregroundColor(.gray)
                    }
                }
                if let e = summary.trainingEnergyPre {
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= e ? "bolt.fill" : "bolt")
                                    .font(.appCaption)
                                    .foregroundColor(i <= e ? .statusYellow : .gray.opacity(0.3))
                            }
                        }
                        Text("Énergie").font(.appCaption).foregroundColor(.gray)
                    }
                }
                Spacer()
            }
            if let exos = summary.trainingExercises, !exos.isEmpty {
                Text(exos.prefix(4).joined(separator: " · "))
                    .font(.appCaption).foregroundColor(.gray)
                    .lineLimit(2)
            }
        }
        .padding(14).glassCard(color: Color.forge, intensity: 0.05)
    }
}

// MARK: - Nutrition Summary

struct NutritionSummaryHealthCard: View {
    let summary: DailyHealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NUTRITION").font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let m = summary.meals {
                    Text("\(m) repas").font(.appCaption).foregroundColor(.gray)
                }
            }
            HStack(spacing: 12) {
                if let cal = summary.calories {
                    MacroChip(value: "\(Int(cal))", label: "kcal", color: Color.forge)
                }
                if let p = summary.protein {
                    MacroChip(value: "\(Int(p))g", label: "protéines", color: .statusRed)
                }
                if let c = summary.carbs {
                    MacroChip(value: "\(Int(c))g", label: "glucides", color: .statusYellow)
                }
                if let f = summary.fat {
                    MacroChip(value: "\(Int(f))g", label: "lipides", color: .statusBlue)
                }
            }
        }
        .padding(14).glassCard(color: Color.forge, intensity: 0.05)
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
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("Tap pour détails")
                    .font(.appMicro).foregroundColor(.gray.opacity(0.6))
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.0) { i, item in
                    let pct = maxH > 0 ? item.1 / maxH : 0
                    let color: Color = item.1 >= 7 ? .statusBlue : (item.1 >= 5 ? Color.forge : .statusRed)
                    let isLast = i == data.count - 1
                    VStack(spacing: 3) {
                        Text(String(format: "%.0fh", item.1))
                            .font(.system(size: 10)).foregroundColor(color.opacity(0.8))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(isLast ? 1 : 0.5))
                            .frame(height: max(CGFloat(pct) * 60, 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(color, lineWidth: selectedDay?.date == item.2.date ? 2 : 0)
                            )
                        Text(item.0).font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
                    .onTapGesture { selectedDay = item.2 }
                }
            }
            .frame(height: 80)
        }
        .padding(14).glassCard(color: .statusBlue, intensity: 0.05)
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
                    .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("Tap pour détails")
                    .font(.appMicro).foregroundColor(.gray.opacity(0.6))
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.0) { i, item in
                    let pct = Double(item.1) / Double(maxSteps)
                    let color: Color = item.1 >= 10000 ? .statusGreen : (item.1 >= 6000 ? .statusOrange : .statusRed)
                    let isLast = i == data.count - 1
                    VStack(spacing: 3) {
                        Text(item.1 >= 1000 ? "\(item.1 / 1000)k" : "\(item.1)")
                            .font(.system(size: 10)).foregroundColor(color.opacity(0.8))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(isLast ? 1 : 0.5))
                            .frame(height: max(CGFloat(pct) * 60, 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(color, lineWidth: selectedDay?.date == item.2.date ? 2 : 0)
                            )
                        Text(item.0).font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
                    .onTapGesture { selectedDay = item.2 }
                }
            }
            .frame(height: 80)
        }
        .padding(14).glassCard(color: .statusGreen, intensity: 0.05)
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
            Image(systemName: icon).font(.appCaption).foregroundColor(color)
            Text(value).font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
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
            Text(value).font(.appLabel.weight(.bold)).foregroundColor(color)
            Text(label).font(.appMicro).foregroundColor(.gray)
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
        case 80...: return .statusGreen
        case 60..<80: return .statusYellow
        case 40..<60: return .statusOrange
        default: return .statusRed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIFE STRESS SCORE")
                        .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                    Text(stressLabel)
                        .font(.appBody.weight(.bold)).foregroundColor(color)
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
                        .font(.appTitle.weight(.black)).foregroundColor(color)
                }
            }

            // Flags
            let activeFlags = flagItems.filter(\.1)
            if !activeFlags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(activeFlags, id: \.0) { label, _ in
                        Text(label)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.statusRed)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.statusRed.opacity(0.12))
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
                                .font(.appCaption).foregroundColor(.statusYellow)
                            Text(rec)
                                .font(.appCaption).foregroundColor(.gray)
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
                        .font(.appCaption).foregroundColor(Color.forge)
                    Text("Données partielles (\(Int(score.dataCoverage * 100))% de couverture)")
                        .font(.appCaption).foregroundColor(.gray)
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
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(data.enumerated()), id: \.0) { i, item in
                    let pct = item.1 / 100.0
                    let barColor: Color = item.1 >= 80 ? .statusGreen : (item.1 >= 60 ? .statusYellow : (item.1 >= 40 ? .statusOrange : .statusRed))
                    let isLast = i == data.count - 1
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", item.1))
                            .font(.system(size: 10)).foregroundColor(barColor.opacity(0.8))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor.opacity(isLast ? 1.0 : 0.5))
                            .frame(height: max(CGFloat(pct) * 48, 3))
                        Text(item.0).font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
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
    let readinessScore: Int?

    private var recoveryColor: Color {
        guard let s = readinessScore else { return .gray }
        if s >= 70 { return .statusGreen }
        if s >= 50 { return .statusYellow }
        return .statusRed
    }
    private var recoveryLabel: String {
        guard let s = readinessScore else { return "Aucune donnée" }
        if s >= 80 { return "Excellente" }
        if s >= 60 { return "Bonne" }
        if s >= 40 { return "Moyenne" }
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
                        .trim(from: 0, to: readinessScore.map { CGFloat($0) / 100 } ?? 0)
                        .stroke(recoveryColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 90)
                        .animation(.easeOut(duration: 0.8), value: readinessScore)
                    VStack(spacing: 1) {
                        if let s = readinessScore {
                            Text("\(s)")
                                .font(.appTitle.weight(.black)).foregroundColor(recoveryColor)
                        } else {
                            Text("—").font(.appTitle.weight(.black)).foregroundColor(.gray)
                        }
                        Text("/ 100").font(.appMicro).foregroundColor(.gray)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ÉTAT DU JOUR")
                        .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
                    Text(recoveryLabel)
                        .font(.appTitle.weight(.bold)).foregroundColor(recoveryColor)

                    // LSS — indicateur secondaire
                    if let lss = lifeStress {
                        let lssColor: Color = lss.score >= 80 ? .statusGreen : lss.score >= 60 ? .statusYellow : lss.score >= 40 ? .statusOrange : .statusRed
                        let lssLabel: String = lss.score >= 80 ? "Récup. optimale" : lss.score >= 60 ? "Bonne forme" : lss.score >= 40 ? "Fatigue modérée" : "Surmenage"
                        HStack(spacing: 4) {
                            Text("Life Stress")
                                .font(.appCaption).foregroundColor(.gray)
                            Text(String(format: "%.0f", lss.score))
                                .font(.appCaption.weight(.bold)).foregroundColor(lssColor)
                            Text("·").font(.appCaption).foregroundColor(.gray)
                            Text(lssLabel)
                                .font(.appCaption).foregroundColor(lssColor)
                        }
                    }

                    if let soreness = summary.soreness {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill").font(.appCaption).foregroundColor(Color.forge)
                            Text("Courbatures \(Int(soreness))/10")
                                .font(.appCaption).foregroundColor(.gray)
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
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(.statusRed)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.statusRed.opacity(0.12))
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
    @AppStorage("steps_daily_goal") private var stepsGoal: Int = 10000

    var body: some View {
        NavigationStack {
            List {
                if let sleep = day.sleepDuration {
                    Section("Sommeil") {
                        DetailMetricRow(icon: "moon.fill", color: .statusBlue, label: "Durée",
                                        value: String(format: "%.1fh", sleep))
                        if let q = day.sleepQuality {
                            DetailMetricRow(icon: "star.fill", color: .statusYellow, label: "Qualité",
                                            value: String(format: "%.0f%%", q))
                        }
                    }
                }
                Section("Activité") {
                    if let steps = day.steps {
                        DetailMetricRow(icon: "figure.walk", color: .statusGreen, label: "Pas",
                                        value: "\(steps)" + (steps >= stepsGoal ? " ✓" : ""))
                    }
                    if let active = day.activeMinutes {
                        DetailMetricRow(icon: "timer", color: Color.forge, label: "Minutes actives",
                                        value: String(format: "%.0f min", active))
                    }
                }
                Section("Cardio") {
                    if let hr = day.restingHeartRate {
                        DetailMetricRow(icon: "heart.fill", color: .statusRed, label: "FC repos",
                                        value: String(format: "%.0f bpm", hr))
                    }
                    if let hrv = day.hrv {
                        DetailMetricRow(icon: "waveform.path.ecg", color: .statusCyan, label: "HRV",
                                        value: String(format: "%.0f ms", hrv))
                    }
                }
                if day.recoveryScore != nil || day.soreness != nil {
                    Section("Récupération") {
                        if let rec = day.recoveryScore {
                            DetailMetricRow(icon: "bolt.fill", color: Color.forge, label: "Score",
                                            value: "\(Int(rec)) / 100")
                        }
                        if let soreness = day.soreness {
                            DetailMetricRow(icon: "figure.strengthtraining.traditional", color: Color.forge,
                                            label: "Courbatures", value: "\(Int(soreness)) / 10")
                        }
                    }
                }
                if let w = day.bodyWeight {
                    Section("Corps") {
                        DetailMetricRow(icon: "scalemass.fill", color: Color.forge, label: "Poids",
                                        value: units.format(w))
                        if let bf = day.bodyFatPct {
                            DetailMetricRow(icon: "chart.pie.fill", color: .statusBlue, label: "Masse grasse",
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

// MARK: - HK Sync Header (copié de EnergyRecoveryView.sectionHeader, NavigationLink RecoveryView retiré)

private struct HKSyncHeader: View {
    @ObservedObject var watchSync: WatchSyncService
    let isSyncing: Bool
    let syncError: String?
    let onSync: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("APPLE HEALTH")
                        .font(.appCaption.weight(.black))
                        .tracking(2)
                        .foregroundColor(.gray)
                    if let last = watchSync.lastSyncDate {
                        Text("Sync \(last.formatted(.relative(presentation: .numeric)))")
                            .font(.appMicro)
                            .foregroundColor(.gray.opacity(0.7))
                    } else {
                        Text("Jamais synchronisé")
                            .font(.appMicro)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                Spacer()
#if !targetEnvironment(macCatalyst)
                Button(action: onSync) {
                    HStack(spacing: 4) {
                        if isSyncing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                                .tint(.statusCyan)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(.statusCyan)
                        }
                    }
                    .padding(8)
                    .background(Color.statusCyan.opacity(0.12))
                    .clipShape(Circle())
                }
                .disabled(isSyncing)
#endif
            }
            if let err = syncError ?? watchSync.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.appCaption)
                        .foregroundColor(Color.appDanger)
                    Text(err)
                        .font(.appCaption)
                        .foregroundColor(Color.appDanger.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(10)
                .background(Color.appDanger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Readiness Hero (copié de EnergyRecoveryView.readinessHero, lit readiness.score Int? directement)

private struct ReadinessHero: View {
    let score: Int?

    private var scoreColor: Color {
        guard let s = score else { return .gray }
        if s >= 75 { return .statusGreen }
        if s >= 50 { return .statusOrange }
        return .statusRed
    }
    private var statusLabel: String {
        guard let s = score else { return "Aucune donnée" }
        if s >= 75 { return "Bon" }
        if s >= 50 { return "Moyen" }
        return "Faible"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.appSurfaceInset, lineWidth: 6)
                    .frame(width: 64, height: 64)
                Circle()
                    .trim(from: 0, to: score.map { CGFloat($0) / 100 } ?? 0)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: score)
                Text(score.map { "\($0)" } ?? "—")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(scoreColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("READINESS")
                    .font(.appCaption.weight(.bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Text(statusLabel)
                    .font(.appHeadline.weight(.bold))
                    .foregroundColor(scoreColor)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(color: scoreColor, intensity: 0.07)
        .cornerRadius(16)
        .overlay {
            TappableMetricOverlay(entry: InfoEntry.readinessMetric, title: "Readiness")
        }
    }
}

// MARK: - Tappable helpers (copiés de EnergyRecoveryView)

private struct TappableMetricOverlay: View {
    let entry: InfoEntry
    let title: String
    @State private var showInfo = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { showInfo = true }
            .sheet(isPresented: $showInfo) {
                InfoSheetView(title: title, entries: [entry])
            }
    }
}

private struct TappableSleepStat: View {
    let label: String
    let value: String
    @State private var showInfo = false

    var body: some View {
        Button { showInfo = true } label: {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                HStack(spacing: 2) {
                    Text(label)
                        .font(.appMicro.weight(.medium))
                        .foregroundColor(.gray)
                    Image(systemName: "info.circle")
                        .font(.system(size: 7))
                        .foregroundColor(.gray.opacity(0.4))
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showInfo) {
            InfoSheetView(title: label, entries: [InfoEntry.sleepStreakMetric])
        }
    }
}

// MARK: - Sleep Stats Row (copié de EnergyRecoveryView.sleepStatsRow)

private struct SleepStatsRow: View {
    let stats: SleepStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOMMEIL — MOYENNES")
                .font(.appCaption.weight(.bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 0) {
                if let d = stats.avgDuration {
                    sleepStat(label: "Moy. durée", value: String(format: "%.1fh", d))
                    Spacer()
                }
                if let q = stats.avgQuality {
                    sleepStat(label: "Moy. qualité", value: String(format: "%.1f/5", q))
                    Spacer()
                }
                if stats.streak > 0 {
                    TappableSleepStat(label: "Streak", value: "\(stats.streak)j")
                }
            }
            .padding(.vertical, 4)
        }
        .padding(14)
        .glassCard(color: .statusBlue, intensity: 0.05)
    }

    private func sleepStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(.appTextPrimary)
            Text(label)
                .font(.appMicro.weight(.medium))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Secondary Metrics Grid (copié de EnergyRecoveryView.secondaryMetricsGrid)

private struct SecondaryMetricsGrid: View {
    let entry: RecoveryEntry

    var body: some View {
        let deltaFC: Double? = entry.hrMorning.flatMap { m in entry.hrPostWorkout.map { p in p - m } }
        let deltaColor: Color = deltaFC.map { d in d <= 10 ? .statusGreen : d <= 20 ? .statusOrange : .statusRed } ?? .gray

        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 8
        ) {
            TappableMetricCell(label: "FC Matin", value: entry.hrMorning.map { "\(Int($0)) bpm" } ?? "—",
                               icon: "sun.max.fill", color: .statusYellow, infoEntry: InfoEntry.hrMorningMetric)
            TappableMetricCell(label: "FC Post-Séance", value: entry.hrPostWorkout.map { "\(Int($0)) bpm" } ?? "—",
                               icon: "figure.strengthtraining.traditional", color: Color.forge,
                               infoEntry: InfoEntry.hrPostWorkoutMetric)
            TappableMetricCell(label: "FC Soir", value: entry.hrEvening.map { "\(Int($0)) bpm" } ?? "—",
                               icon: "moon.fill", color: .indigo, infoEntry: InfoEntry.hrEveningMetric)
            if let d = deltaFC {
                TappableMetricCell(
                    label: "Delta FC",
                    value: (d >= 0 ? "+" : "") + "\(Int(d)) bpm",
                    icon: "arrow.up.arrow.down", color: deltaColor, valueColor: deltaColor,
                    infoEntry: InfoEntry.deltaFcMetric
                )
            }
        }
    }
}

// MARK: - Delta FC Card (copié de RecoveryView.deltaFCCard — matin vs repos)

private struct DeltaFCCard: View {
    let entry: RecoveryEntry

    var body: some View {
        Group {
            if let hrM = entry.hrMorning, let rhr = entry.restingHr {
                let delta = hrM - rhr
                let dColor: Color = delta < 10 ? Color.appSuccess : (delta < 20 ? Color.statusOrange : Color.appDanger)
                HStack(spacing: 0) {
                    VStack(spacing: 3) {
                        Text("FC MATIN").font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                        Text(String(format: "%.0f bpm", hrM))
                            .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(Color.statusCyan)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 3) {
                        Text("DELTA").font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                        Text(String(format: "%+.0f", delta))
                            .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(dColor)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 3) {
                        Text("FC REPOS").font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                        Text(String(format: "%.0f bpm", rhr))
                            .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(Color.appDanger)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 14)
                .glassCard()
            }
        }
    }
}

// MARK: - Energy Header Card (copié de EnergyRecoveryView.EnergyHeaderCard L174)

private struct EnergyHeaderCard: View {
    let energy: EnergyDaily

    var body: some View {
        let score  = energy.energyScore
        let color  = energy.statusColor
        let status = energy.statusLabel
        let bal    = energy.formattedBalance

        VStack(spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.appSurfaceInset, lineWidth: 6)
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
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(color)
                    if let obj = energy.objective {
                        Text("Objectif : \(obj.capitalized)")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                    if let target = energy.targetBalance {
                        Text("Cible : \(target)")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
            }

            Divider().background(Color.appSeparatorStrong)

            HStack(spacing: 0) {
                energyKPI(label: "Dépenses",
                          value: energy.tdee.map { "\($0)" } ?? "—",
                          unit: "kcal", color: .statusBlue)
                Spacer()
                energyKPI(label: "Apports",
                          value: energy.intake.map { "\($0)" } ?? "—",
                          unit: "kcal", color: .statusGreen)
                Spacer()
                energyKPI(label: "Bilan",
                          value: bal,
                          unit: "", color: energy.statusColor)
            }

            if energy.isTooEarly == true {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                    Text("Bilan partiel — BMR proraté au temps écoulé")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
                .padding(.top, 2)
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
                .font(.appCaption.weight(.semibold))
                .tracking(0.5)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(color)
            if !unit.isEmpty {
                Text(unit)
                    .font(.appCaption)
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Energy Breakdown Card (copié de EnergyRecoveryView.EnergyBreakdownCard L279)

private struct EnergyBreakdownCard: View {
    let energy: EnergyDaily
    var activeEnergy: Double? = nil

    var body: some View {
        let bmrVal   = energy.bmrElapsed ?? energy.bmr ?? 0
        let eatW     = energy.eatWorkouts ?? 0
        let eatC     = energy.eatCardio ?? 0
        let neatVal  = energy.neat ?? 0
        let tdee     = energy.tdee ?? 0
        let isRestDay = eatW == 0 && eatC == 0

        VStack(alignment: .leading, spacing: 12) {
            Text("DÉPENSES DU JOUR")
                .font(.appCaption.weight(.black))
                .tracking(2)
                .foregroundColor(.gray)

            VStack(spacing: 8) {
                breakdownRow(label: "BMR",
                             subtitle: energy.bmrFormulaProgressLabel,
                             value: bmrVal,
                             color: .statusBlue,
                             total: tdee)
                if eatW > 0 {
                    breakdownRow(label: "Musculation",
                                 subtitle: "\(energy.breakdown?.workouts?.count ?? 0) séance(s)",
                                 value: eatW,
                                 color: Color.forge,
                                 total: tdee)
                }
                if eatC > 0 {
                    breakdownRow(label: "Cardio",
                                 subtitle: "\(energy.breakdown?.cardio?.count ?? 0) session(s)",
                                 value: eatC,
                                 color: Color.statusCyan,
                                 total: tdee)
                }
                if neatVal > 0 {
                    let stepsLabel: String = {
                        if let net = energy.breakdown?.stepsNet, let total = energy.breakdown?.steps, net < total {
                            return "\(net) pas nets (\(total) bruts)"
                        }
                        return energy.breakdown?.stepsNet.map { "\($0) pas" }
                            ?? energy.breakdown?.steps.map { "\($0) pas" }
                            ?? "Activité légère"
                    }()
                    breakdownRow(label: "NEAT",
                                 subtitle: stepsLabel,
                                 value: neatVal,
                                 color: .statusGreen,
                                 total: tdee)
                } else if energy.breakdown?.steps == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                        Text("Active Apple Watch pour calculer ton NEAT")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 2)
                }

                if let ae = activeEnergy, ae > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "applewatch")
                            .font(.appCaption)
                            .foregroundColor(isRestDay && ae > 800 ? Color.forge : .gray)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Dépense active (HealthKit)")
                                .font(.appCaption.weight(.medium))
                                .foregroundColor(Color.appOnSurface.opacity(0.75))
                            if isRestDay && ae > 800 {
                                Text("Activité élevée malgré le repos")
                                    .font(.appCaption)
                                    .foregroundColor(Color.forge)
                            }
                        }
                        Spacer()
                        Text("\(Int(ae)) kcal")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(isRestDay && ae > 800 ? Color.forge : .gray)
                    }
                    .padding(.top, 2)
                }

                Divider().background(Color.appSeparatorStrong)

                HStack {
                    Text("Total TDEE")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Text("\(tdee) kcal")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Color.forge)
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
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    Text(subtitle)
                        .font(.appCaption)
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
                        .fill(Color.appSurfaceInset)
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

// MARK: - Energy Error Card (copié de EnergyRecoveryView.EnergyErrorCard L421)

private struct EnergyErrorCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.appTitle.weight(.regular))
                .foregroundColor(Color.forge)
            Text(message)
                .font(.appLabel.weight(.regular))
                .foregroundColor(Color.appOnSurface.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.forge.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Energy Chart Section (copié de EnergyRecoveryView.EnergyChartSection L448)

private struct EnergyChartSection: View {
    let history: [EnergyHistoryDay]
    var targetBalance: String? = nil
    @State private var selectedDay: EnergyHistoryDay?

    private func targetMidpoint(_ s: String?) -> Int? {
        guard let s = s else { return nil }
        if s.contains("±") { return 0 }
        var nums: [Int] = []
        var cur = ""
        var sign = 1
        for ch in s {
            if ch == "+" { sign = 1; cur = "" }
            else if ch == "-" { sign = -1; cur = "" }
            else if ch.isNumber { cur.append(ch) }
            else if !cur.isEmpty, let n = Int(cur) { nums.append(n * sign); cur = "" }
        }
        if !cur.isEmpty, let n = Int(cur) { nums.append(n * sign) }
        guard !nums.isEmpty else { return nil }
        return nums.reduce(0, +) / nums.count
    }

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
                    .font(.appCaption.weight(.black))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 12) {
                    legendDot(color: .statusBlue,   label: "TDEE")
                    legendDot(color: .statusGreen,  label: "Apports")
                    if targetBalance != nil {
                        legendDot(color: .statusYellow, label: "Cible")
                    }
                }
            }

            Chart {
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
                            (intake >= day.tdee ? Color.statusGreen : Color.statusRed).opacity(0.14)
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }

                ForEach(history) { day in
                    LineMark(
                        x: .value("Date", day.shortDate),
                        y: .value("TDEE", day.tdee),
                        series: .value("Série", "Dépenses")
                    )
                    .foregroundStyle(Color.statusBlue)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", day.shortDate),
                        y: .value("TDEE", day.tdee)
                    )
                    .foregroundStyle(Color.statusBlue)
                    .symbolSize(20)
                }

                ForEach(history.filter { $0.intake != nil }) { day in
                    LineMark(
                        x: .value("Date", day.shortDate),
                        y: .value("Apports", day.intake ?? 0),
                        series: .value("Série", "Apports")
                    )
                    .foregroundStyle(Color.statusGreen)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", day.shortDate),
                        y: .value("Apports", day.intake ?? 0)
                    )
                    .foregroundStyle(Color.statusGreen)
                    .symbolSize(20)
                }

                let avgTDEE = history.reduce(0) { $0 + $1.tdee } / history.count
                if let mid = targetMidpoint(targetBalance) {
                    let target = avgTDEE + mid
                    RuleMark(y: .value("Cible", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(Color.statusYellow.opacity(0.5))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Cible \(target) kcal")
                                .font(.system(size: 8))
                                .foregroundColor(Color.statusYellow.opacity(0.7))
                        }
                }

                if let sel = selectedDay {
                    RuleMark(x: .value("Sélection", sel.shortDate))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(Color.appOnSurface.opacity(0.3))
                        .annotation(position: .top, alignment: .center) {
                            dayAnnotation(sel)
                        }
                }
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                        .foregroundStyle(Color.appSurfaceInset)
                    AxisValueLabel {
                        if let v = val.as(Int.self) {
                            Text("\(v / 100 * 100)")
                                .font(.appMicro)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel()
                        .font(.appMicro)
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
            Text(label).font(.appCaption).foregroundColor(.gray)
        }
    }

    private func dayAnnotation(_ day: EnergyHistoryDay) -> some View {
        VStack(spacing: 2) {
            Text(day.date)
                .font(.appMicro.weight(.semibold))
                .foregroundColor(.appTextPrimary)
            Text("TDEE \(day.tdee) kcal")
                .font(.appMicro)
                .foregroundColor(.statusBlue)
            if let i = day.intake {
                Text("Apports \(i) kcal")
                    .font(.appMicro)
                    .foregroundColor(.statusGreen)
            }
            if let b = day.balance {
                Text(b >= 0 ? "+\(b) kcal" : "\(b) kcal")
                    .font(.appMicro.weight(.bold))
                    .foregroundColor(b >= 0 ? .statusGreen : .statusRed)
            }
        }
        .padding(6)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Dynamic Suggestions Section (copié de EnergyRecoveryView.DynamicSuggestionsSection L1303)

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

        let tooEarly = energy?.isTooEarly == true

        if let r = readiness, r < 40 {
            list.append(Suggestion(
                icon: "moon.zzz.fill", color: .statusRed,
                title: "Récupération critique",
                detail: "Score de récupération très bas — journée de repos total recommandée.",
                priority: 2
            ))
        }

        if !tooEarly && balance <= -700 {
            list.append(Suggestion(
                icon: "exclamationmark.triangle.fill", color: .statusRed,
                title: "Déficit sévère",
                detail: "Ton bilan est inférieur à -700 kcal — risque de perte musculaire. Augmente tes apports.",
                priority: 1
            ))
        } else if !tooEarly && balanceStatus == "deficit_aggressive" {
            list.append(Suggestion(
                icon: "flame.fill", color: .statusRed,
                title: "Déficit agressif",
                detail: "Déficit entre -500 et -700 kcal. Ajoute une collation protéinée pour préserver la masse musculaire.",
                priority: 2
            ))
        }

        if sleepHours > 0 && sleepHours < 6 {
            list.append(Suggestion(
                icon: "bed.double.fill", color: Color.forge,
                title: "Sommeil insuffisant",
                detail: "Moins de 6h cette nuit — la récupération et la synthèse protéique sont compromises. Couche-toi plus tôt.",
                priority: 3
            ))
        }

        if fatigue >= 7 || soreness >= 7 {
            let field = fatigue >= soreness ? "fatigue" : "courbatures"
            list.append(Suggestion(
                icon: "bolt.slash.fill", color: Color.forge,
                title: "Récupération insuffisante",
                detail: "Score de \(field) élevé — envisage une séance légère ou un jour de repos actif aujourd'hui.",
                priority: 3
            ))
        }

        if !tooEarly && balanceStatus == "surplus_high" {
            list.append(Suggestion(
                icon: "arrow.up.circle.fill", color: Color.forge,
                title: "Surplus trop élevé",
                detail: "Ton surplus dépasse +600 kcal. Ajoute 20-30 min de cardio ou réduis de ~200 kcal.",
                priority: 4
            ))
        }

        if !tooEarly && intake == 0 && !(energy?.isError ?? true) {
            list.append(Suggestion(
                icon: "fork.knife", color: .statusBlue,
                title: "Nutrition non enregistrée",
                detail: "Aucun apport saisi aujourd'hui — log tes repas pour calculer ton bilan réel.",
                priority: 5
            ))
        }

        if neat == nil && !(energy?.isError ?? true) {
            list.append(Suggestion(
                icon: "applewatch", color: .statusBlue,
                title: "NEAT non calculé",
                detail: "Porte ton Apple Watch pour mesurer tes pas et inclure le NEAT dans ton TDEE.",
                priority: 6
            ))
        }

        if hrvZone == "green" && sleepHours >= 7 {
            list.append(Suggestion(
                icon: "waveform.path.ecg.rectangle.fill", color: .statusGreen,
                title: "HRV optimal + bon sommeil",
                detail: "Système nerveux bien récupéré. Journée idéale pour une séance intense ou un record personnel.",
                priority: 7
            ))
        }

        let hasAlert = list.contains { $0.priority <= 4 }
        if !hasAlert {
            let isBalanced = ["balanced", "deficit_optimal", "surplus_optimal"].contains(balanceStatus)
            let goodSleep  = sleepHours >= 7
            let goodRecov  = (readiness ?? 0) >= 65
            if isBalanced && goodSleep && goodRecov {
                list.append(Suggestion(
                    icon: "checkmark.seal.fill", color: .statusGreen,
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
                    .font(.appCaption.weight(.black))
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
                .font(.appBody)
                .foregroundColor(s.color)
                .frame(width: 32, height: 32)
                .background(s.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(s.title)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text(s.detail)
                    .font(.appCaption)
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

// MARK: - Accordion Row (copié de RecoveryView.AccordionRow L422)

private struct AccordionRow: View {
    let entry: RecoveryEntry
    var onEdit: () -> Void

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private var formattedDate: String {
        guard let d = entry.date,
              let date = Self.isoFmt.date(from: d) else { return entry.date ?? "—" }
        return Self.displayFmt.string(from: date).capitalized
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(Color.appOnSurface.opacity(0.9))
                    if let src = entry.source {
                        Text(src == "manual" ? "Manuel" : "Apple Santé")
                            .font(.appMicro)
                            .foregroundColor(.gray.opacity(0.55))
                    }
                }
                Spacer()
                Group {
                    metricChip(icon: "moon.zzz.fill",
                               value: entry.sleepHours.map { String(format: "%.1fh", $0) },
                               color: Color.statusBlue)
                    metricChip(icon: "waveform.path.ecg",
                               value: entry.hrv.map { String(format: "%.0f", $0) },
                               color: Color.appSuccess)
                    metricChip(icon: "heart.fill",
                               value: entry.restingHr.map { String(format: "%.0f", $0) },
                               color: Color.appDanger)
                }
                Image(systemName: "pencil")
                    .font(.appMicro)
                    .foregroundColor(.gray.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func metricChip(icon: String, value: String?, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.appMicro)
                .foregroundColor(value != nil ? color : .gray.opacity(0.3))
            Text(value ?? "—")
                .font(.appCaption.weight(.semibold))
                .foregroundColor(value != nil ? Color.appOnSurface.opacity(0.85) : .gray.opacity(0.35))
        }
    }
}

// MARK: - Recovery Sleep Bar Chart (copié de RecoveryView.RecoverySleepBarChart L331)

private struct RecoverySleepBarChart: View {
    let entries: [RecoveryEntry]
    let goalHours: Double

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "EEE"; return f
    }()

    private func barColor(_ h: Double) -> Color {
        if h < 5 { return Color.appDanger }
        if h < goalHours * 0.85 { return Color.statusOrange }
        if h <= goalHours * 1.15 { return Color.appSuccess }
        return Color.statusBlue
    }

    private func dayLabel(_ iso: String) -> String {
        guard let d = Self.dateFmt.date(from: iso) else { return "" }
        return Self.dayFmt.string(from: d).prefix(3).lowercased()
    }

    var body: some View {
        let yMax = max((entries.compactMap(\.sleepHours).max() ?? 9) + 0.5, goalHours + 0.5)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "moon.zzz.fill").font(.appMicro).foregroundColor(Color.statusBlue)
                Text("SOMMEIL — \(entries.count) JOURS").font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text(String(format: "Obj. %.0fh", goalHours))
                    .font(.appMicro.weight(.semibold)).foregroundColor(Color.appSuccess.opacity(0.7))
            }
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let barW = w / CGFloat(entries.count) - 4
                let goalY = h - CGFloat(goalHours / yMax) * h

                ZStack(alignment: .topLeading) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: goalY))
                        p.addLine(to: CGPoint(x: w, y: goalY))
                    }
                    .stroke(Color.appSuccess.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    ForEach(Array(entries.enumerated()), id: \.1.id) { i, entry in
                        let x = CGFloat(i) * (w / CGFloat(entries.count)) + 2
                        let bh = entry.sleepHours.map { CGFloat($0 / yMax) * h } ?? 0
                        let color = barColor(entry.sleepHours ?? 0)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.75))
                            .frame(width: barW, height: bh)
                            .position(x: x + barW / 2, y: h - bh / 2)

                        if let q = entry.sleepQuality {
                            let qColor: Color = q >= 7 ? Color.appSuccess : (q >= 4 ? Color.statusYellow : Color.appDanger)
                            Circle()
                                .fill(qColor)
                                .frame(width: 5, height: 5)
                                .position(x: x + barW / 2, y: h - bh - 6)
                        }
                    }
                }
            }
            .frame(height: 90)

            HStack(spacing: 0) {
                ForEach(entries, id: \.id) { entry in
                    Text(dayLabel(entry.date ?? ""))
                        .font(.appMicro)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Recovery 14d Chart (copié de EnergyRecoveryView.Recovery14dChart L1149)

private struct Recovery14dChart: View {
    let history: [ReadinessHistoryPoint]

    private struct ChartPoint: Identifiable {
        let id: String
        let label: String
        let score: Double
        let color: Color
    }

    private static let mtl = TimeZone(identifier: "America/Toronto")!
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar   = Calendar(identifier: .iso8601)
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = mtl
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var chartPoints: [ChartPoint] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = Self.mtl
        let today = cal.startOfDay(for: Date())
        let byDate: [String: Int] = Dictionary(uniqueKeysWithValues: history.map { ($0.date, $0.score) })
        return (0..<14).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Self.ymd.string(from: day)
            guard let s = byDate[key] else { return nil }
            let score = Double(s)
            let parts = key.split(separator: "-")
            let label = parts.count == 3 ? "\(parts[2])/\(parts[1])" : key
            let color: Color = score >= 75 ? .statusGreen : score >= 50 ? .statusOrange : .statusRed
            return ChartPoint(id: key, label: label, score: score, color: color)
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
            guard let t = trendResult else { return .statusOrange }
            if t.slope > 0.5  { return .statusGreen }
            if t.slope < -0.5 { return .statusRed }
            return .statusOrange
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
                    .font(.appCaption.weight(.black))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: trendIcon)
                        .font(.appMicro.weight(.bold))
                        .foregroundColor(trendColor)
                    Text(trendLabel)
                        .font(.appCaption.weight(.semibold))
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
                    .foregroundStyle(Color.appOnSurface.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                    LineMark(
                        x: .value("Date", last.label),
                        y: .value("Tendance", max(0, min(100, yN))),
                        series: .value("S", "Tendance")
                    )
                    .foregroundStyle(Color.appOnSurface.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                }
            }
            .chartYScale(domain: 0.0...100.0)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel()
                        .font(.appMicro)
                        .foregroundStyle(Color.gray)
                }
            }
            .chartYAxis {
                AxisMarks(values: [0.0, 50.0, 75.0, 100.0]) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                        .foregroundStyle(Color.appSurfaceInset)
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))")
                                .font(.appMicro)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .frame(height: 130)
        }
    }
}
