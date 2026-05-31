import SwiftUI
import OSLog

private let logger = Logger(subsystem: "TrainingOS", category: "Recovery")

private struct RecoveryStats {
    var avgSleep: Double = 0
    var avgSleepQuality: Double = 0
    var avgRestHR: Double = 0
    var avgSteps: Double = 0
    var avgActiveEnergy: Double = 0
    var avgHRV: Double = 0
    var avgHRMorning: Double = 0
    var avgHRPostWorkout: Double = 0
    var avgHREvening: Double = 0
    var avgFatigue: Double = 0
    var countSleep: Int = 0
    var countSleepQuality: Int = 0
    var countRestHR: Int = 0
    var countSteps: Int = 0
    var countActiveEnergy: Int = 0
    var countHRV: Int = 0

    init(log: [RecoveryEntry]) {
        func avg(_ vals: [Double]) -> Double { vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count) }
        let vSleep        = log.compactMap(\.sleepHours)
        let vSleepQuality = log.compactMap(\.sleepQuality)
        let vRestHR       = log.compactMap(\.restingHr).filter { $0 <= 100 }
        let vSteps        = log.compactMap(\.steps).map(Double.init)
        let vActiveEnergy = log.compactMap(\.activeEnergy)
        let vHRV          = log.compactMap(\.hrv)
        avgSleep         = avg(vSleep);         countSleep        = vSleep.count
        avgSleepQuality  = avg(vSleepQuality);  countSleepQuality = vSleepQuality.count
        avgRestHR        = avg(vRestHR);        countRestHR       = vRestHR.count
        avgSteps         = avg(vSteps);         countSteps        = vSteps.count
        avgActiveEnergy  = avg(vActiveEnergy);  countActiveEnergy = vActiveEnergy.count
        avgHRV           = avg(vHRV);           countHRV          = vHRV.count
        avgHRMorning     = avg(log.compactMap(\.hrMorning))
        avgHRPostWorkout = avg(log.compactMap(\.hrPostWorkout))
        avgHREvening     = avg(log.compactMap(\.hrEvening))
        avgFatigue       = avg(log.compactMap(\.fatigue))
    }
}

struct RecoveryView: View {
    var onOpenSession: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var api = APIService.shared
    @State private var log: [RecoveryEntry] = []
    @State private var isLoading = true
    @State private var showSheet = false
    @State private var editTarget: RecoveryEntry? = nil
    @State private var apiError: String? = nil
    @State private var toast: ToastMessage? = nil
    @ObservedObject private var watchSync = WatchSyncService.shared
    @State private var isBackfilling = false
    @AppStorage("hk_backfill_done_date") private var backfillDoneDate = ""
    @State private var stats = RecoveryStats(log: [])
    @State private var hrvAnalysis: HRVAnalysis? = nil
    @State private var dailySummary: DailySummary? = nil
    @AppStorage("hrv_onboarding_done") private var hrvOnboardingDone = false
    @State private var showHRVOnboarding = false

    private var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var entriesMissingHK: [RecoveryEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return log.filter {
            guard let d = $0.date, let date = Self.isoFmt.date(from: d) else { return false }
            return date >= cutoff && ($0.restingHr == nil || $0.hrv == nil)
        }
    }

    private var backfillDone: Bool { backfillDoneDate == todayStr }

    private var alreadyLoggedToday: Bool {
        log.contains { $0.date == todayStr }
    }

    // KPIs — delegates to cached stats (computed once per loadData, not per render)
    var avgSleep: Double         { stats.avgSleep }
    var avgSleepQuality: Double  { stats.avgSleepQuality }
    var avgRestHR: Double        { stats.avgRestHR }
    var avgSteps: Double         { stats.avgSteps }
    var avgActiveEnergy: Double  { stats.avgActiveEnergy }
    var avgHRV: Double           { stats.avgHRV }
    var avgHRMorning: Double     { stats.avgHRMorning }
    var avgHRPostWorkout: Double { stats.avgHRPostWorkout }
    var avgHREvening: Double     { stats.avgHREvening }
    var avgFatigue: Double       { stats.avgFatigue }
    var countSleep: Int          { stats.countSleep }
    var countSleepQuality: Int   { stats.countSleepQuality }
    var countRestHR: Int         { stats.countRestHR }
    var countSteps: Int          { stats.countSteps }
    var countActiveEnergy: Int   { stats.countActiveEnergy }
    var countHRV: Int            { stats.countHRV }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)
                if isLoading {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // Banners HealthKit — priorité : backfill > watch sync, jamais les deux
                            #if !targetEnvironment(macCatalyst)
                            if !entriesMissingHK.isEmpty && !backfillDone {
                                HStack(spacing: 10) {
                                    Image(systemName: "heart.text.square.fill")
                                        .font(.system(size: 13)).foregroundColor(.red)
                                    Text("\(entriesMissingHK.count) entrée\(entriesMissingHK.count > 1 ? "s" : "") sans FC/HRV")
                                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Button { Task { await backfillFromHealthKit() } } label: {
                                        if isBackfilling {
                                            ProgressView().tint(.red).scaleEffect(0.65)
                                        } else {
                                            Text("Sync")
                                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.red)
                                        }
                                    }
                                    .disabled(isBackfilling)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.red.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.14), lineWidth: 1))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0)
                            } else {
                                WatchSyncBannerView(sync: watchSync) {
                                    Task {
                                        await watchSync.requestAuthorizationAndSync()
                                        await loadData()
                                    }
                                }
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0)
                            }
                            #endif

                            // Banner lien récupération → performance
                            RecoveryPerformanceBanner(
                                dashboard: api.dashboard,
                                hrvAnalysis: hrvAnalysis,
                                recoveryScore: dailySummary?.recoveryScore,
                                onTap: onOpenSession
                            )
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.02)

                            // Readiness card — composite score, dominant dès l'ouverture
                            if let today = log.first(where: { $0.date == todayStr }) {
                                ReadinessCard(entry: today, backendScore: dailySummary?.recoveryScore,
                                              hrv7dBaseline: hrvAnalysis?.hrv7dAvg)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.04)
                            }

                            // KPI grid — récupération
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                KPICard(value: avgSleep > 0 ? String(format: "%.1fh", avgSleep) : "—",
                                        label: "Sommeil moy.", color: .blue,
                                        subtitle: countSleep > 0 ? "sur \(countSleep) logs" : nil)
                                KPICard(value: avgSleepQuality > 0 ? String(format: "%.1f/10", avgSleepQuality) : "—",
                                        label: "Qualité moy.", color: .purple,
                                        subtitle: countSleepQuality > 0 ? "sur \(countSleepQuality) logs" : nil)
                                KPICard(value: avgRestHR > 0 ? String(format: "%.0f bpm", avgRestHR) : "—",
                                        label: "FC repos moy.", color: .red,
                                        subtitle: countRestHR > 0 ? "sur \(countRestHR) logs" : nil)
                                KPICard(value: avgSteps > 0 ? String(format: "%.0f", avgSteps) : "—",
                                        label: "Pas moy./jour", color: .green,
                                        subtitle: countSteps > 0 ? "sur \(countSteps) logs" : nil)
                                KPICard(value: avgActiveEnergy > 0 ? String(format: "%.0f kcal", avgActiveEnergy) : "—",
                                        label: "Énergie active", color: .orange,
                                        subtitle: countActiveEnergy > 0 ? "sur \(countActiveEnergy) logs" : nil)
                                KPICard(
                                    value: avgHRV > 0 ? String(format: "%.0f ms", avgHRV) : "—",
                                    label: "HRV moy.",
                                    color: hrvAnalysis?.zoneColor ?? .green,
                                    subtitle: countHRV > 0 ? "sur \(countHRV) logs" : nil
                                )
                            }
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.05)

                            // KPI — Fatigue perçue moyenne
                            if avgFatigue > 0 {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    KPICard(value: String(format: "%.1f/10", avgFatigue),
                                            label: "Fatigue moy.", color: avgFatigue >= 7 ? .red : (avgFatigue >= 4 ? .orange : .green))
                                }
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.055)
                            }

                            // KPI grid — FC journalière
                            if avgHRMorning > 0 || avgHRPostWorkout > 0 || avgHREvening > 0 {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    KPICard(value: avgHRMorning > 0 ? String(format: "%.0f bpm", avgHRMorning) : "—",
                                            label: "FC matin moy.", color: .cyan)
                                    KPICard(value: avgHRPostWorkout > 0 ? String(format: "%.0f bpm", avgHRPostWorkout) : "—",
                                            label: "FC post séance", color: .orange)
                                    KPICard(value: avgHREvening > 0 ? String(format: "%.0f bpm", avgHREvening) : "—",
                                            label: "FC soir moy.", color: .blue)
                                }
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.06)
                            }

                            // HRV Analysis card — score normalisé personnel
                            if let hrv = hrvAnalysis, hrv.baselineAvailable || hrv.todayRmssd != nil {
                                HRVAnalysisCard(analysis: hrv)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.07)
                            }

                            // HRV baseline en construction (< 7 jours)
                            if let hrv = hrvAnalysis, hrv.dataPoints7d < 7 {
                                HRVBaselineProgressView(dataPoints: hrv.dataPoints7d)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.075)
                            }

                            // Contextual tips HRV — un seul affiché, le plus prioritaire
                            if let hrv = hrvAnalysis {
                                if hrv.streakAlert {
                                    HRVContextualTipView(
                                        tipId: "streak_alert",
                                        icon: "exclamationmark.triangle.fill",
                                        message: "Ton HRV est sous ta baseline depuis \(hrv.consecutiveLowDays) jours consécutifs. Priorité à la récupération — réduis le volume cette semaine.",
                                        accentColor: .orange
                                    )
                                    .padding(.horizontal, 16)
                                } else if hrv.hrvCv ?? 0 > 20 {
                                    HRVContextualTipView(
                                        tipId: "high_cv",
                                        icon: "waveform.path.ecg",
                                        message: "Ton HRV est très variable (\(Int(hrv.hrvCv ?? 0))% CV). C'est normal au début — continue à mesurer chaque matin pour stabiliser ta baseline."
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }

                            // HRV chart
                            let hrvEntries = Array(log.prefix(14).reversed())
                            if hrvEntries.filter({ $0.hrv != nil }).count >= 2 {
                                HRVChart(entries: hrvEntries,
                                         baseline: hrvAnalysis?.hrv7dAvg,
                                         zoneColor: hrvAnalysis?.zoneColor ?? .green)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.1)
                            }

                            // RHR chart
                            if hrvEntries.filter({ $0.restingHr != nil }).count >= 2 {
                                RHRChart(entries: hrvEntries)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.12)
                            }

                            // HR moments chart
                            if hrvEntries.filter({ $0.hrMorning != nil || $0.hrPostWorkout != nil || $0.hrEvening != nil }).count >= 2 {
                                HRMomentsChart(entries: hrvEntries)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.13)
                            }

                            // Sleep chart
                            if log.filter({ $0.sleepHours != nil }).count >= 2 {
                                SleepChart(entries: Array(log.prefix(10).reversed()))
                                    .padding(.horizontal, 16)
                            } else {
                                EmptyChartPlaceholder(message: "Logge au moins 2 nuits pour voir l'évolution du sommeil")
                                    .padding(.horizontal, 16)
                            }

                            // Steps chart
                            if log.filter({ $0.steps != nil }).count >= 2 {
                                StepsChart(entries: Array(log.prefix(10).reversed()))
                                    .padding(.horizontal, 16)
                            } else {
                                EmptyChartPlaceholder(message: "Logge au moins 2 jours de pas pour voir la tendance")
                                    .padding(.horizontal, 16)
                            }

                            // History
                            if log.isEmpty {
                                RecoveryEmptyState(onAddTap: { showSheet = true })
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("HISTORIQUE")
                                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 8)
                                    ForEach(Array(log.enumerated()), id: \.1.id) { i, entry in
                                        RecoveryRow(
                                            entry: entry,
                                            onEdit: { editTarget = entry },
                                            onDelete: {
                                                Task {
                                                    do {
                                                        try await APIService.shared.deleteRecovery(date: entry.date ?? "")
                                                        await MainActor.run { toast = ToastMessage(message: "Entrée supprimée", style: .success) }
                                                    } catch {
                                                        await MainActor.run { apiError = "Erreur réseau — réessaie" }
                                                    }
                                                    await loadData()
                                                }
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                        if i < log.count - 1 {
                                            Rectangle()
                                                .fill(Color.white.opacity(0.06))
                                                .frame(height: 0.5)
                                                .padding(.horizontal, 24)
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 32)
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, contentBottomPadding)
                    }
                    .refreshable { await loadData() }
                }
            }
            .navigationTitle("Récupération")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSheet) {
                LogRecoverySheet(onSaved: { await loadData() })
            }
            .sheet(item: $editTarget) { entry in
                LogRecoverySheet(prefillEntry: entry, onSaved: { await loadData() })
            }
            .sheet(isPresented: $showHRVOnboarding) {
                HRVOnboardingView(onDone: { showHRVOnboarding = false })
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: alreadyLoggedToday ? "pencil" : "plus") {
                    if alreadyLoggedToday, let todayEntry = log.first(where: { $0.date == todayStr }) {
                        editTarget = todayEntry
                    } else {
                        showSheet = true
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, fabBottomPadding + 16)
            }
        }
        .task {
            await watchSync.syncIfNeeded()
            await loadData()
            if !hrvOnboardingDone {
                showHRVOnboarding = true
            }
        }
        .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(apiError ?? "") }
        .toast($toast)
        .onChange(of: watchSync.lastSyncCompleted) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        log = (try? await APIService.shared.fetchRecoveryData()) ?? []
        stats = RecoveryStats(log: log)
        // sequential — async let LIFO crash on iOS 26 beta
        let analysis = try? await APIService.shared.fetchHRVAnalysis()
        let summary  = try? await APIService.shared.fetchDailySummary()
        await MainActor.run {
            hrvAnalysis  = analysis
            dailySummary = summary
        }
        isLoading = false
    }

    private func backfillFromHealthKit() async {
        let hk = HealthKitService.shared
        let authorized = await hk.requestAuthorization()
        guard authorized else { return }

        isBackfilling = true
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var updated = 0

        for entry in entriesMissingHK {
            guard let dateStr = entry.date,
                  let date    = fmt.date(from: dateStr) else { continue }

            // sequential — async let LIFO crash on iOS 26 beta
            let newRHR = await (entry.restingHr == nil ? hk.fetchRestingHR(for: date) : nil)
            let newHRV = await (entry.hrv       == nil ? hk.fetchHRV(for: date)       : nil)

            guard newRHR != nil || newHRV != nil else { continue }

            do {
                try await APIService.shared.logRecovery(
                    sleepHours:    entry.sleepHours,
                    sleepQuality:  entry.sleepQuality,
                    restingHr:     newRHR ?? entry.restingHr,
                    hrv:           newHRV ?? entry.hrv,
                    steps:         entry.steps,
                    soreness:      entry.soreness,
                    activeEnergy:  entry.activeEnergy,
                    hrMorning:     entry.hrMorning,
                    hrPostWorkout: entry.hrPostWorkout,
                    hrEvening:     entry.hrEvening,
                    notes:         entry.notes ?? "",
                    date:          dateStr
                )
                updated += 1
            } catch {
                logger.error("backfill failed for \(dateStr): \(error)")
            }
        }

        await loadData()
        await MainActor.run {
            isBackfilling   = false
            backfillDoneDate = todayStr
            if updated > 0 {
                toast = ToastMessage(
                    message: "\(updated) entrée\(updated > 1 ? "s" : "") mise\(updated > 1 ? "s" : "") à jour depuis Santé",
                    style: .success
                )
            } else {
                toast = ToastMessage(message: "Aucune donnée HealthKit trouvée pour ces dates", style: .success)
            }
        }
    }
}
