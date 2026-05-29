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

// MARK: - Row
struct RecoveryRow: View {
    let entry: RecoveryEntry
    var onEdit: (() -> Void)? = nil
    let onDelete: () -> Void

    @State private var expanded      = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Always-visible header ─────────────────────────────────────
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(entry.date ?? "")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        if entry.isFromWatch {
                            Label("Watch", systemImage: "applewatch")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                    // 3 primary KPIs
                    HStack(spacing: 10) {
                        kpiPill("moon.fill",
                                entry.sleepHours.map { String(format: "%.1fh", $0) } ?? "—",
                                sleepColor(entry.sleepHours))
                        kpiPill("bolt.fill",
                                entry.energyPre.map { String(format: "%.0f/10", $0) } ?? "—",
                                energyColor(entry.energyPre))
                        kpiPill("flame.fill",
                                entry.soreness.map { String(format: "%.0f/10", $0) } ?? "—",
                                sorenessColor(entry.soreness))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        if let onEdit {
                            Button(action: onEdit) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                                    .frame(width: 26, height: 26)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundColor(.orange.opacity(0.8))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                        Button { confirmDelete = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .frame(width: 26, height: 26)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray.opacity(0.45))
                            .frame(width: 26, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            // ── Expanded secondary section ────────────────────────────────
            if expanded {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let q = entry.sleepQuality {
                            secChip("star.fill", String(format: "%.0f/10", q), "qualité", .purple)
                        }
                        if let f = entry.fatigue {
                            secChip("bolt.slash.fill", String(format: "%.0f/10", f), "fatigue", .orange)
                        }
                        if let hr = entry.restingHr {
                            secChip("heart.fill", String(format: "%.0f bpm", hr), "FC repos", .red)
                        }
                        if let hrv = entry.hrv {
                            secChip("waveform.path.ecg", String(format: "%.0f ms", hrv), "HRV", .cyan)
                        }
                        if let s = entry.steps {
                            let sLabel = s >= 1_000 ? String(format: "%.1fk", Double(s) / 1_000) : "\(s)"
                            secChip("figure.walk", sLabel, "pas", .green)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 10)

                if let n = entry.notes, !n.isEmpty {
                    Text(n)
                        .font(.system(size: 11)).foregroundColor(.gray.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
            }
        }
        .background(Color.appCard).cornerRadius(12)
        .animation(.easeInOut(duration: 0.2), value: expanded)
        .confirmationDialog("Supprimer cette entrée ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func kpiPill(_ icon: String, _ value: String, _ color: Color) -> some View {
        let isNil = value == "—"
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(isNil ? .gray.opacity(0.3) : color)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isNil ? .gray.opacity(0.35) : .white.opacity(0.9))
        }
    }

    private func secChip(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                Text(label).font(.system(size: 8)).foregroundColor(.gray.opacity(0.55))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }

    private func sorenessColor(_ v: Double?) -> Color {
        guard let v else { return .gray }
        return v >= 7 ? .red : (v >= 4 ? .orange : .green)
    }
    private func energyColor(_ v: Double?) -> Color {
        guard let v else { return .gray }
        return v >= 7 ? .green : (v >= 4 ? .orange : .red)
    }
    private func sleepColor(_ v: Double?) -> Color {
        guard let v else { return .gray }
        return v >= 7 ? .green : (v >= 6 ? .orange : .red)
    }
}

// MARK: - Readiness Card

struct ReadinessCard: View {
    let entry: RecoveryEntry
    var backendScore: Double? = nil
    var hrv7dBaseline: Double? = nil

    private var localScore: Double? {
        var total = 0.0; var weight = 0.0
        if let q   = entry.sleepQuality { total += q * 1.5;                                      weight += 1.5 }
        if let s   = entry.soreness     { total += max(0, 10 - s) * 1.5;                         weight += 1.5 }
        if let h   = entry.sleepHours   { total += min(10, h / 8 * 10) * 1.5;                    weight += 1.5 }
        if let hrv = entry.hrv          { let ref = hrv7dBaseline ?? 60.0; total += min(10, hrv / ref * 10) * 4.0; weight += 4.0 }
        if let hr  = entry.restingHr, hr <= 100 { total += min(10, max(0, (85 - hr) / 45 * 10)) * 1.5;   weight += 1.5 }
        if let f   = entry.fatigue      { total += max(0, 10 - f) * 1.0;                         weight += 1.0 }
        if let ep  = entry.energyPre    { total += min(10, ep / 5 * 10) * 0.5;                   weight += 0.5 }
        return weight >= 2.0 ? round(total / weight * 10) / 10 : nil
    }

    private var score: Double? { backendScore ?? localScore }

    private var scoreColor: Color {
        guard let s = score else { return .gray }
        return s >= 7 ? .green : (s >= 5 ? .orange : .red)
    }

    private var scoreLabel: String {
        guard let s = score else { return "—" }
        return s >= 7 ? "Prêt" : (s >= 5 ? "Modéré" : "Fatigué")
    }

    private var presentCount: Int {
        [entry.hrv.map { _ in () }, entry.restingHr.map { _ in () },
         entry.sleepHours.map { _ in () }, entry.soreness.map { _ in () },
         entry.sleepQuality.map { _ in () }, entry.fatigue.map { _ in () },
         entry.energyPre.map { _ in () }]
            .compactMap { $0 }.count
    }

    private var missingMetrics: [String] {
        var m: [String] = []
        if entry.hrv == nil        { m.append("HRV") }
        if entry.restingHr == nil  { m.append("Fréq. cardiaque") }
        if entry.sleepHours == nil { m.append("Sommeil") }
        if entry.soreness == nil   { m.append("Courbatures") }
        return m
    }

    private var reliabilityLabel: String {
        switch presentCount {
        case 6...: return "Fiabilité élevée"
        case 4...: return "Fiabilité partielle"
        case 2...: return "Données limitées"
        default:   return "Données insuffisantes"
        }
    }

    private var reliabilityColor: Color {
        switch presentCount {
        case 6...: return .green
        case 4...: return .orange
        default:   return .red
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 6)
                    .frame(width: 62, height: 62)
                if let s = score {
                    Circle()
                        .trim(from: 0, to: CGFloat(s / 10))
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 62, height: 62)
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 1) {
                    Text(score.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                    Text("/10")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("READINESS DU JOUR")
                        .font(.system(size: 10, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    Text(scoreLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(scoreColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(scoreColor.opacity(0.15))
                        .cornerRadius(4)
                }
                HStack(spacing: 12) {
                    if let hrv = entry.hrv {
                        metricPill("HRV", String(format: "%.0f ms", hrv),
                                   hrv >= 50 ? .green : (hrv >= 30 ? .orange : .red))
                    }
                    if let hr = entry.restingHr {
                        metricPill("RHR", String(format: "%.0f bpm", hr),
                                   hr <= 55 ? .green : (hr <= 65 ? .orange : .red))
                    }
                    if let s = entry.soreness {
                        metricPill("Courbatures", String(format: "%.0f/10", s),
                                   s <= 3 ? .green : (s <= 6 ? .orange : .red))
                    }
                }
                if !missingMetrics.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 9))
                            .foregroundColor(reliabilityColor)
                        Text("\(reliabilityLabel) · manque : \(missingMetrics.joined(separator: ", "))")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .glassCard(color: scoreColor, intensity: 0.06)
        .cornerRadius(14)
    }

    private func metricPill(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - HRV Chart

struct HRVChart: View {
    let entries: [RecoveryEntry]
    var baseline: Double? = nil
    var zoneColor: Color = .green

    @State private var trim: CGFloat = 0
    @State private var selectedPt: Int? = nil

    private let kL: CGFloat = 28  // leading space for Y labels

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var pts: [(idx: Int, val: Double)] {
        entries.enumerated().compactMap { i, e in
            guard let v = e.hrv, v > 0 else { return nil }
            return (i, v)
        }
    }
    private var yMax: Double { max((pts.map(\.val).max() ?? 60) * 1.1, 60) }
    private var yMin: Double { max((pts.map(\.val).min() ?? 0) - 15, 0) }
    private var yRng: Double { max(yMax - yMin, 1) }

    private func xAt(_ idx: Int, w: CGFloat) -> CGFloat {
        guard entries.count > 1 else { return kL + (w - kL) / 2 }
        return kL + CGFloat(idx) / CGFloat(entries.count - 1) * (w - kL)
    }
    private func yAt(_ val: Double, h: CGFloat) -> CGFloat {
        h - CGFloat((val - yMin) / yRng) * h
    }

    private func linePath(w: CGFloat, h: CGFloat) -> Path {
        var path = Path(); var moved = false
        for pt in pts {
            let cp = CGPoint(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))
            if !moved { path.move(to: cp); moved = true } else { path.addLine(to: cp) }
        }
        return path
    }
    private func areaPath(w: CGFloat, h: CGFloat) -> Path {
        guard let first = pts.first, let last = pts.last else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: xAt(first.idx, w: w), y: h))
        path.addLine(to: CGPoint(x: xAt(first.idx, w: w), y: yAt(first.val, h: h)))
        for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))) }
        path.addLine(to: CGPoint(x: xAt(last.idx, w: w), y: h))
        path.closeSubpath()
        return path
    }

    @ViewBuilder
    private func gridLine(step: Int, w: CGFloat, h: CGFloat) -> some View {
        let frac = Double(step) / 4.0
        let yy   = CGFloat(1.0 - frac) * h
        let val  = yMin + frac * yRng
        Path { p in p.move(to: CGPoint(x: kL, y: yy)); p.addLine(to: CGPoint(x: w, y: yy)) }
            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        Text(String(format: "%.0f", val))
            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.45))
            .frame(width: kL - 4, alignment: .trailing)
            .position(x: (kL - 4) / 2, y: yy)
    }

    private func dayAbbrev(_ e: RecoveryEntry) -> String {
        guard let d = e.date, let date = Self.dateFmt.date(from: d) else { return "" }
        return ["D","L","M","M","J","V","S"][Calendar.current.component(.weekday, from: date) - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HRV — 14 DERNIERS JOURS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let b = baseline {
                    Text("baseline \(Int(b)) ms")
                        .font(.system(size: 9)).foregroundColor(.gray.opacity(0.6))
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { step in gridLine(step: step, w: w, h: h) }

                    if let b = baseline, b > yMin, b < yMax {
                        let by = yAt(b, h: h)
                        Path { p in p.move(to: CGPoint(x: kL, y: by)); p.addLine(to: CGPoint(x: w, y: by)) }
                            .stroke(zoneColor.opacity(0.45),
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    areaPath(w: w, h: h).fill(zoneColor.opacity(0.07))

                    linePath(w: w, h: h)
                        .trim(from: 0, to: trim)
                        .stroke(zoneColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    ForEach(Array(pts.enumerated()), id: \.0) { j, pt in
                        Circle()
                            .fill(zoneColor)
                            .frame(width: selectedPt == j ? 8 : 4,
                                   height: selectedPt == j ? 8 : 4)
                            .position(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))
                            .animation(.easeInOut(duration: 0.15), value: selectedPt)
                    }

                    if let j = selectedPt, j < pts.count {
                        let pt = pts[j]
                        let tx = xAt(pt.idx, w: w)
                        let ty = yAt(pt.val, h: h)
                        let lbl = entries.indices.contains(pt.idx) ? (entries[pt.idx].date ?? "") : ""
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f ms", pt.val))
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            Text(lbl).font(.system(size: 9)).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.appCard.opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(zoneColor.opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .position(x: min(max(tx, 55), w - 55), y: max(ty - 36, 22))
                    }

                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard !pts.isEmpty else { return }
                                let tx = v.location.x
                                let j = pts.indices.min(by: {
                                    abs(xAt(pts[$0].idx, w: w) - tx) <
                                    abs(xAt(pts[$1].idx, w: w) - tx)
                                }) ?? 0
                                selectedPt = j
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { selectedPt = nil }
                                }
                            }
                        )
                }
            }
            .frame(height: 90)
            .onAppear { withAnimation(.easeInOut(duration: 0.5)) { trim = 1 } }

            HStack(spacing: 0) {
                Spacer().frame(width: kL)
                ForEach(Array(entries.enumerated()), id: \.0) { _, e in
                    Text(dayAbbrev(e))
                        .font(.system(size: 8)).foregroundColor(.gray.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Circle().fill(zoneColor).frame(width: 6, height: 6)
                    Text("HRV personnelle").font(.system(size: 9)).foregroundColor(.gray)
                }
                if baseline != nil {
                    HStack(spacing: 4) {
                        HStack(spacing: 1) {
                            Rectangle().fill(zoneColor.opacity(0.5)).frame(width: 3, height: 1)
                            Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                            Rectangle().fill(zoneColor.opacity(0.5)).frame(width: 3, height: 1)
                            Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                            Rectangle().fill(zoneColor.opacity(0.5)).frame(width: 2, height: 1)
                        }
                        Text("Baseline 7j").font(.system(size: 9)).foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(16).glassCard(color: .green, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - RHR Chart

struct RHRChart: View {
    let entries: [RecoveryEntry]

    @State private var trim: CGFloat = 0
    @State private var selectedPt: Int? = nil

    private let kL: CGFloat = 28
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var pts: [(idx: Int, val: Double)] {
        entries.enumerated().compactMap { i, e in
            guard let v = e.restingHr, v > 0 else { return nil }
            return (i, v)
        }
    }
    private var lineColor: Color {
        let avg = pts.isEmpty ? 0 : pts.map(\.val).reduce(0, +) / Double(pts.count)
        return avg <= 55 ? .green : (avg <= 65 ? .orange : .red)
    }
    // Ensure 40–60 reference band is always visible
    private var yMax: Double { max((pts.map(\.val).max() ?? 60) + 5, 70) }
    private var yMin: Double { min((pts.map(\.val).min() ?? 50) - 5, 35) }
    private var yRng: Double { max(yMax - yMin, 1) }

    private func xAt(_ idx: Int, w: CGFloat) -> CGFloat {
        guard entries.count > 1 else { return kL + (w - kL) / 2 }
        return kL + CGFloat(idx) / CGFloat(entries.count - 1) * (w - kL)
    }
    private func yAt(_ val: Double, h: CGFloat) -> CGFloat {
        h - CGFloat((val - yMin) / yRng) * h
    }

    private func linePath(w: CGFloat, h: CGFloat) -> Path {
        var path = Path(); var moved = false
        for pt in pts {
            let cp = CGPoint(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))
            if !moved { path.move(to: cp); moved = true } else { path.addLine(to: cp) }
        }
        return path
    }
    private func areaPath(w: CGFloat, h: CGFloat) -> Path {
        guard let first = pts.first, let last = pts.last else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: xAt(first.idx, w: w), y: h))
        path.addLine(to: CGPoint(x: xAt(first.idx, w: w), y: yAt(first.val, h: h)))
        for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))) }
        path.addLine(to: CGPoint(x: xAt(last.idx, w: w), y: h))
        path.closeSubpath()
        return path
    }

    @ViewBuilder
    private func gridLine(step: Int, w: CGFloat, h: CGFloat) -> some View {
        let frac = Double(step) / 4.0
        let yy   = CGFloat(1.0 - frac) * h
        let val  = yMin + frac * yRng
        Path { p in p.move(to: CGPoint(x: kL, y: yy)); p.addLine(to: CGPoint(x: w, y: yy)) }
            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        Text(String(format: "%.0f", val))
            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.45))
            .frame(width: kL - 4, alignment: .trailing)
            .position(x: (kL - 4) / 2, y: yy)
    }

    private func dayAbbrev(_ e: RecoveryEntry) -> String {
        guard let d = e.date, let date = Self.dateFmt.date(from: d) else { return "" }
        return ["D","L","M","M","J","V","S"][Calendar.current.component(.weekday, from: date) - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FC REPOS — 14 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { step in gridLine(step: step, w: w, h: h) }

                    // Optimal zone band fill (40–60 bpm)
                    let y40 = yAt(40, h: h)
                    let y60 = yAt(60, h: h)
                    Rectangle()
                        .fill(Color.green.opacity(0.05))
                        .frame(width: w - kL, height: abs(y40 - y60))
                        .position(x: kL + (w - kL) / 2, y: min(y40, y60) + abs(y40 - y60) / 2)

                    // 60 bpm dashed reference
                    Path { p in p.move(to: CGPoint(x: kL, y: y60)); p.addLine(to: CGPoint(x: w, y: y60)) }
                        .stroke(Color.green.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    // 40 bpm dashed reference
                    Path { p in p.move(to: CGPoint(x: kL, y: y40)); p.addLine(to: CGPoint(x: w, y: y40)) }
                        .stroke(Color.green.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    areaPath(w: w, h: h).fill(lineColor.opacity(0.07))

                    linePath(w: w, h: h)
                        .trim(from: 0, to: trim)
                        .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    ForEach(Array(pts.enumerated()), id: \.0) { j, pt in
                        Circle()
                            .fill(lineColor)
                            .frame(width: selectedPt == j ? 8 : 4,
                                   height: selectedPt == j ? 8 : 4)
                            .position(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))
                            .animation(.easeInOut(duration: 0.15), value: selectedPt)
                    }

                    if let j = selectedPt, j < pts.count {
                        let pt  = pts[j]
                        let tx  = xAt(pt.idx, w: w)
                        let ty  = yAt(pt.val, h: h)
                        let lbl = entries.indices.contains(pt.idx) ? (entries[pt.idx].date ?? "") : ""
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f bpm", pt.val))
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            Text(lbl).font(.system(size: 9)).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.appCard.opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(lineColor.opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .position(x: min(max(tx, 55), w - 55), y: max(ty - 36, 22))
                    }

                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard !pts.isEmpty else { return }
                                let tx = v.location.x
                                let j = pts.indices.min(by: {
                                    abs(xAt(pts[$0].idx, w: w) - tx) <
                                    abs(xAt(pts[$1].idx, w: w) - tx)
                                }) ?? 0
                                selectedPt = j
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { selectedPt = nil }
                                }
                            }
                        )
                }
            }
            .frame(height: 90)
            .onAppear { withAnimation(.easeInOut(duration: 0.5)) { trim = 1 } }

            HStack(spacing: 0) {
                Spacer().frame(width: kL)
                ForEach(Array(entries.enumerated()), id: \.0) { _, e in
                    Text(dayAbbrev(e))
                        .font(.system(size: 8)).foregroundColor(.gray.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Circle().fill(lineColor).frame(width: 6, height: 6)
                    Text("FC repos").font(.system(size: 9)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    HStack(spacing: 1) {
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 2, height: 1)
                    }
                    Text("Zone optimale 40–60 bpm").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .red, intensity: 0.04).cornerRadius(14)
    }
}

// MARK: - HR Moments Chart

struct HRMomentsChart: View {
    let entries: [RecoveryEntry]

    private var maxHR: Double {
        let all = entries.flatMap { [$0.hrMorning, $0.hrPostWorkout, $0.hrEvening].compactMap { $0 } }
        return max(all.max() ?? 1, 100)
    }
    private var minHR: Double {
        let all = entries.flatMap { [$0.hrMorning, $0.hrPostWorkout, $0.hrEvening].compactMap { $0 } }
        return max((all.min() ?? 50) - 10, 40)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FC JOURNALIÈRE — 14 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let isLast = i == entries.count - 1
                    VStack(spacing: 1) {
                        if let m = e.hrMorning {
                            dot(.cyan, m, maxHR, minHR, isLast)
                        }
                        if let pw = e.hrPostWorkout {
                            dot(.orange, pw, maxHR, minHR, isLast)
                        }
                        if let ev = e.hrEvening {
                            dot(.blue, ev, maxHR, minHR, isLast)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)

            HStack(spacing: 12) {
                legendDot(.cyan,   "Matin")
                legendDot(.orange, "Post séance")
                legendDot(.blue,   "Soir")
            }
        }
        .padding(16).glassCard(color: .cyan, intensity: 0.04).cornerRadius(14)
    }

    @ViewBuilder
    private func dot(_ color: Color, _ value: Double, _ maxV: Double, _ minV: Double, _ bright: Bool) -> some View {
        let range = maxV - minV
        let pct   = range > 0 ? (value - minV) / range : 0.5
        let h     = max(CGFloat(pct) * 50, 4)
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(bright ? 0.9 : 0.5))
            .frame(height: h)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
    }
}

// MARK: - Sleep Chart
struct SleepChart: View {
    let entries: [RecoveryEntry]

    @State private var appeared  = false
    @State private var selectedIdx: Int? = nil

    private let kL: CGFloat = 28

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var yMax: Double { max(entries.compactMap(\.sleepHours).max() ?? 8, 9) }

    private func barColor(_ h: Double) -> Color { h >= 7 ? .green : (h >= 6 ? .orange : .red) }

    @ViewBuilder
    private func gridLine(step: Int, w: CGFloat, h: CGFloat) -> some View {
        let frac = Double(step) / 4.0
        let yy   = CGFloat(1.0 - frac) * h
        let val  = yMax * frac
        Path { p in p.move(to: CGPoint(x: kL, y: yy)); p.addLine(to: CGPoint(x: w, y: yy)) }
            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        Text(String(format: "%.0fh", val))
            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.45))
            .frame(width: kL - 4, alignment: .trailing)
            .position(x: (kL - 4) / 2, y: yy)
    }

    private func dayAbbrev(_ e: RecoveryEntry) -> String {
        guard let d = e.date, let date = Self.dateFmt.date(from: d) else { return "" }
        return ["D","L","M","M","J","V","S"][Calendar.current.component(.weekday, from: date) - 1]
    }

    private func barDelay(_ i: Int) -> Double { Double(i) * 0.04 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOMMEIL — DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let w        = geo.size.width
                let h        = geo.size.height
                let chartW   = w - kL
                let n        = max(entries.count, 1)
                let slot: CGFloat = chartW / CGFloat(n)
                let barW: CGFloat = max(slot * 0.65, 3)

                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { step in gridLine(step: step, w: w, h: h) }

                    // 7h objective dashed line
                    let y7 = h - CGFloat(7.0 / yMax) * h
                    Path { p in p.move(to: CGPoint(x: kL, y: y7)); p.addLine(to: CGPoint(x: w, y: y7)) }
                        .stroke(Color.green.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Bars
                    ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                        let hours  = e.sleepHours ?? 0
                        let color  = barColor(hours)
                        let barH   = hours > 0 ? CGFloat(hours / yMax) * h : 0
                        let cx     = kL + CGFloat(i) * slot + slot / 2

                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(selectedIdx == i ? 1.0 : 0.65))
                            .frame(width: barW, height: max(barH, hours > 0 ? 2 : 0))
                            .scaleEffect(y: appeared ? 1 : 0, anchor: .bottom)
                            .position(x: cx, y: h - max(barH, hours > 0 ? 2 : 0) / 2)
                            .animation(.easeOut(duration: 0.5).delay(barDelay(i)), value: appeared)
                    }

                    // Tooltip
                    if let j = selectedIdx, entries.indices.contains(j) {
                        let sleepH = entries[j].sleepHours ?? 0
                        let cx     = kL + CGFloat(j) * slot + slot / 2
                        let barH   = CGFloat(sleepH / yMax) * h
                        VStack(spacing: 2) {
                            Text(String(format: "%.1fh", sleepH))
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            Text(entries[j].date ?? "")
                                .font(.system(size: 9)).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.appCard.opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(barColor(sleepH).opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .position(x: min(max(cx, 50), w - 50), y: max(h - barH - 30, 22))
                    }

                    // Touch layer
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let idx = Int((v.location.x - kL) / slot)
                                if entries.indices.contains(idx) { selectedIdx = idx }
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { selectedIdx = nil }
                                }
                            }
                        )
                }
            }
            .frame(height: 90)
            .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }

            // X axis
            HStack(spacing: 0) {
                Spacer().frame(width: kL)
                ForEach(Array(entries.enumerated()), id: \.0) { _, e in
                    VStack(spacing: 1) {
                        Text(dayAbbrev(e))
                            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.4))
                        if e.source == "healthkit" {
                            Image(systemName: "applewatch")
                                .font(.system(size: 6)).foregroundColor(.blue.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendDot(.green,  "≥7h")
                legendDot(.orange, "6–7h")
                legendDot(.red,    "<6h")
                Spacer()
                HStack(spacing: 4) {
                    HStack(spacing: 1) {
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 2, height: 1)
                    }
                    Text("Objectif 7h").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .blue, intensity: 0.05).cornerRadius(14)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
    }
}

// MARK: - Steps Chart
struct StepsChart: View {
    let entries: [RecoveryEntry]
    var stepGoal: Int = 10_000

    @State private var appeared   = false
    @State private var selectedIdx: Int? = nil

    private let kL: CGFloat = 30  // slightly wider — "10.5k" Y labels need a bit more room

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var yMax: Double {
        let m = entries.compactMap(\.steps).map(Double.init).max() ?? 0
        return max(m * 1.1, Double(stepGoal) * 1.15)
    }

    private func barColor(_ s: Double) -> Color { s >= 10_000 ? .green : (s >= 7_000 ? .orange : .red) }

    private func stepsLabel(_ s: Double) -> String {
        s >= 1_000 ? String(format: "%.1fk", s / 1_000) : "\(Int(s))"
    }

    @ViewBuilder
    private func gridLine(step: Int, w: CGFloat, h: CGFloat) -> some View {
        let frac = Double(step) / 4.0
        let yy   = CGFloat(1.0 - frac) * h
        let val  = yMax * frac
        Path { p in p.move(to: CGPoint(x: kL, y: yy)); p.addLine(to: CGPoint(x: w, y: yy)) }
            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        Text(stepsLabel(val))
            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.45))
            .frame(width: kL - 4, alignment: .trailing)
            .position(x: (kL - 4) / 2, y: yy)
    }

    private func dayAbbrev(_ e: RecoveryEntry) -> String {
        guard let d = e.date, let date = Self.dateFmt.date(from: d) else { return "" }
        return ["D","L","M","M","J","V","S"][Calendar.current.component(.weekday, from: date) - 1]
    }

    private func barDelay(_ i: Int) -> Double { Double(i) * 0.04 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PAS — DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let w      = geo.size.width
                let h      = geo.size.height
                let chartW = w - kL
                let n      = max(entries.count, 1)
                let slot: CGFloat = chartW / CGFloat(n)
                let barW: CGFloat = max(slot * 0.65, 3)

                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { step in gridLine(step: step, w: w, h: h) }

                    // 10k objective dashed line
                    let yGoal = h - CGFloat(Double(stepGoal) / yMax) * h
                    Path { p in p.move(to: CGPoint(x: kL, y: yGoal)); p.addLine(to: CGPoint(x: w, y: yGoal)) }
                        .stroke(Color.green.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Bars
                    ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                        let steps  = Double(e.steps ?? 0)
                        let color  = barColor(steps)
                        let barH   = steps > 0 ? CGFloat(steps / yMax) * h : 0
                        let cx     = kL + CGFloat(i) * slot + slot / 2

                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(selectedIdx == i ? 1.0 : 0.65))
                            .frame(width: barW, height: max(barH, steps > 0 ? 2 : 0))
                            .scaleEffect(y: appeared ? 1 : 0, anchor: .bottom)
                            .position(x: cx, y: h - max(barH, steps > 0 ? 2 : 0) / 2)
                            .animation(.easeOut(duration: 0.5).delay(barDelay(i)), value: appeared)
                    }

                    // Tooltip
                    if let j = selectedIdx, entries.indices.contains(j) {
                        let steps  = Double(entries[j].steps ?? 0)
                        let cx     = kL + CGFloat(j) * slot + slot / 2
                        let barH   = CGFloat(steps / yMax) * h
                        VStack(spacing: 2) {
                            Text(stepsLabel(steps) + " pas")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            Text(entries[j].date ?? "")
                                .font(.system(size: 9)).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.appCard.opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(barColor(steps).opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .position(x: min(max(cx, 55), w - 55), y: max(h - barH - 30, 22))
                    }

                    // Touch layer
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let idx = Int((v.location.x - kL) / slot)
                                if entries.indices.contains(idx) { selectedIdx = idx }
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { selectedIdx = nil }
                                }
                            }
                        )
                }
            }
            .frame(height: 90)
            .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }

            // X axis
            HStack(spacing: 0) {
                Spacer().frame(width: kL)
                ForEach(Array(entries.enumerated()), id: \.0) { _, e in
                    Text(dayAbbrev(e))
                        .font(.system(size: 8)).foregroundColor(.gray.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendDot(.green,  "≥10k")
                legendDot(.orange, "7k–10k")
                legendDot(.red,    "<7k")
                Spacer()
                HStack(spacing: 4) {
                    HStack(spacing: 1) {
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 2, height: 1)
                    }
                    Text("Objectif 10k").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .green, intensity: 0.05).cornerRadius(14)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
    }
}

// MARK: - Empty State
struct RecoveryEmptyState: View {
    var onAddTap: (() -> Void)? = nil

    var body: some View {
        EmptyStateView(
            icon: "moon.zzz.fill",
            title: "Comment tu te sens ce matin ?",
            subtitle: "30 secondes suffisent.",
            action: onAddTap,
            actionLabel: "Logger ma récupération"
        )
    }
}

// MARK: - Log Sheet
struct LogRecoverySheet: View {
    var prefillEntry: RecoveryEntry? = nil
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hk = HealthKitService.shared

    @State private var selectedDate = Date()
    @State private var sleepHoursStr = ""
    @State private var sleepQuality: Double = 0
    @State private var restingHrStr = ""
    @State private var hrvStr = ""
    @State private var stepsStr = ""
    @State private var activeEnergyStr = ""
    @State private var hrMorningStr = ""
    @State private var hrPostWorkoutStr = ""
    @State private var hrEveningStr = ""
    @State private var soreness: Double = 0
    @State private var fatigue: Double = 5
    @State private var energyPre: Double = 0
    @State private var notes = ""
    @State private var isSaving = false
    @State private var isLoadingHK = false
    @State private var apiError: String? = nil
    @State private var showFullMode = false
    @AppStorage("recoveryLogPrefersFull") private var prefersFull = false
    @AppStorage("recoveryLogFullUseCount") private var fullUseCount = 0

    private var isEditing: Bool { prefillEntry != nil }

    private var dateStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {

                        // Date picker — toujours visible
                        DatePicker("Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(14).background(Color.appCard).cornerRadius(12)

                        // HealthKit auto-fill — toujours visible
                        #if !targetEnvironment(macCatalyst)
                        Button(action: fillFromHealthKit) {
                            HStack(spacing: 8) {
                                if isLoadingHK {
                                    ProgressView().tint(.white).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "heart.text.square.fill")
                                        .font(.system(size: 15))
                                }
                                Text(isLoadingHK ? "Lecture Health..." : "Remplir depuis Apple Santé")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(12)
                        }
                        .disabled(isLoadingHK)
                        .buttonStyle(SpringButtonStyle())
                        #endif

                        if showFullMode {
                            // ── MODE COMPLET ─────────────────────────────

                            // Sleep complet
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SOMMEIL").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                HStack(spacing: 12) {
                                    RecoveryField(label: "DURÉE (h)", placeholder: "7.5", text: $sleepHoursStr)
                                    RecoveryField(label: "FC REPOS (bpm)", placeholder: "58", text: $restingHrStr)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("QUALITÉ").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        Text(String(format: "%.0f / 10", sleepQuality))
                                            .font(.system(size: 13, weight: .bold)).foregroundColor(.blue)
                                    }
                                    Slider(value: $sleepQuality, in: 1...10, step: 1).tint(.orange)
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Douleurs + Fatigue + Énergie
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("DOULEURS MUSCULAIRES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        Text(String(format: "%.0f / 10", soreness)).font(.system(size: 13, weight: .bold)).foregroundColor(sorenessColor(soreness))
                                    }
                                    Slider(value: $soreness, in: 0...10, step: 1).tint(sorenessColor(soreness))
                                    HStack {
                                        Text("0 = Aucune").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Sévère").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                                Divider().background(Color.white.opacity(0.06))
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("FATIGUE PERÇUE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        Text(String(format: "%.0f / 10", fatigue)).font(.system(size: 13, weight: .bold)).foregroundColor(fatigueColor(fatigue))
                                    }
                                    Slider(value: $fatigue, in: 0...10, step: 1).tint(fatigueColor(fatigue))
                                    HStack {
                                        Text("0 = Aucune").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Épuisé(e)").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                                Divider().background(Color.white.opacity(0.06))
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("ÉNERGIE PERÇUE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        if energyPre == 0 {
                                            Text("—").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
                                        } else {
                                            Text(String(format: "%.0f / 10", energyPre)).font(.system(size: 13, weight: .bold)).foregroundColor(energyPreColor(energyPre))
                                        }
                                    }
                                    Slider(value: $energyPre, in: 0...10, step: 1).tint(energyPre == 0 ? .gray : energyPreColor(energyPre))
                                    HStack {
                                        Text("0 = Non renseigné").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Excellent").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Activité
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ACTIVITÉ QUOTIDIENNE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                HStack(spacing: 12) {
                                    RecoveryField(label: "PAS", placeholder: "8500", text: $stepsStr, keyboardType: .numberPad)
                                    RecoveryField(label: "HRV (ms)", placeholder: "45", text: $hrvStr)
                                }
                                HStack(spacing: 12) {
                                    RecoveryField(label: "ÉNERGIE ACTIVE (kcal)", placeholder: "350", text: $activeEnergyStr, keyboardType: .numberPad)
                                    Spacer().frame(maxWidth: .infinity)
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Fréquence cardiaque
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "heart.fill").font(.system(size: 10)).foregroundColor(.red)
                                    Text("FRÉQUENCE CARDIAQUE (bpm)").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                }
                                HStack(spacing: 12) {
                                    RecoveryField(label: "MATIN (06-09h)", placeholder: "62", text: $hrMorningStr, keyboardType: .numberPad)
                                    RecoveryField(label: "POST SÉANCE (+30min)", placeholder: "88", text: $hrPostWorkoutStr, keyboardType: .numberPad)
                                }
                                HStack(spacing: 12) {
                                    RecoveryField(label: "SOIR (21-23h)", placeholder: "58", text: $hrEveningStr, keyboardType: .numberPad)
                                    Spacer().frame(maxWidth: .infinity)
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            // Notes
                            VStack(alignment: .leading, spacing: 6) {
                                Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                TextField("Comment tu te sens...", text: $notes, axis: .vertical)
                                    .lineLimit(3, reservesSpace: true)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color(hex: "191926"))
                                    .cornerRadius(10)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        } else {
                            // ── MODE RAPIDE ───────────────────────────────

                            // Sommeil (heures + qualité)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SOMMEIL").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                RecoveryField(label: "DURÉE (h)", placeholder: "7.5", text: $sleepHoursStr)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("QUALITÉ").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        if sleepQuality == 0 {
                                            Text("—").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
                                        } else {
                                            Text(String(format: "%.0f / 10", sleepQuality))
                                                .font(.system(size: 13, weight: .bold)).foregroundColor(.blue)
                                        }
                                    }
                                    Slider(value: $sleepQuality, in: 0...10, step: 1).tint(.orange)
                                    HStack {
                                        Text("0 = Non renseigné").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Excellent").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)

                            // Énergie + Soreness
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("ÉNERGIE DU JOUR").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        if energyPre == 0 {
                                            Text("—").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
                                        } else {
                                            Text(String(format: "%.0f / 10", energyPre)).font(.system(size: 13, weight: .bold)).foregroundColor(energyPreColor(energyPre))
                                        }
                                    }
                                    Slider(value: $energyPre, in: 0...10, step: 1).tint(energyPre == 0 ? .gray : energyPreColor(energyPre))
                                    HStack {
                                        Text("0 = Non renseigné").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Excellent").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                                Divider().background(Color.white.opacity(0.06))
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("DOULEURS MUSCULAIRES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Spacer()
                                        Text(String(format: "%.0f / 10", soreness)).font(.system(size: 13, weight: .bold)).foregroundColor(sorenessColor(soreness))
                                    }
                                    Slider(value: $soreness, in: 0...10, step: 1).tint(sorenessColor(soreness))
                                    HStack {
                                        Text("0 = Aucune").font(.system(size: 9)).foregroundColor(.gray)
                                        Spacer()
                                        Text("10 = Sévère").font(.system(size: 9)).foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(14).background(Color.appCard).cornerRadius(12)
                        }

                        // Bouton Logger — toujours visible
                        Button(action: save) {
                            Group {
                                if isSaving { ProgressView().tint(.white) }
                                else { Text("Logger").font(.system(size: 16, weight: .semibold)).foregroundColor(.white) }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.orange).cornerRadius(14)
                        .buttonStyle(SpringButtonStyle())

                        // Lien mode complet — seulement en mode rapide
                        if !showFullMode {
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) { showFullMode = true }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 12))
                                    Text("Plus de détails")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(Color(white: 0.40))
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(20)
                    .animation(.easeInOut(duration: 0.3), value: showFullMode)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Modifier la récupération" : "Récupération du jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
            .onAppear { prefill() }
        }
    }

    private func prefill() {
        if let e = prefillEntry {
            showFullMode = true  // édition → mode complet toujours
            if let h   = e.sleepHours    { sleepHoursStr    = String(format: "%.1f", h) }
            if let q   = e.sleepQuality  { sleepQuality     = q }
            if let hr  = e.restingHr     { restingHrStr     = String(format: "%.0f", hr) }
            if let v   = e.hrv           { hrvStr           = String(format: "%.0f", v) }
            if let s   = e.steps         { stepsStr         = "\(s)" }
            if let ae  = e.activeEnergy  { activeEnergyStr  = String(format: "%.0f", ae) }
            if let hrm = e.hrMorning     { hrMorningStr     = String(format: "%.0f", hrm) }
            if let hrp = e.hrPostWorkout { hrPostWorkoutStr = String(format: "%.0f", hrp) }
            if let hre = e.hrEvening     { hrEveningStr     = String(format: "%.0f", hre) }
            if let so  = e.soreness      { soreness   = so }
            if let fa  = e.fatigue       { fatigue    = fa }
            if let ep  = e.energyPre     { energyPre  = ep }
            notes = e.notes ?? ""
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            if let d = e.date, let parsed = f.date(from: d) { selectedDate = parsed }
        } else {
            showFullMode = prefersFull
            fillFromHealthKit()
        }
    }

    private func sorenessColor(_ v: Double) -> Color {
        if v >= 7 { return .red }; if v >= 4 { return .orange }; return .green
    }

    private func fatigueColor(_ v: Double) -> Color {
        if v >= 7 { return .red }; if v >= 4 { return .orange }; return .green
    }

    private func energyPreColor(_ v: Double) -> Color {
        if v >= 7 { return .green }; if v >= 4 { return .orange }; return .red
    }

    private func fillFromHealthKit() {
        isLoadingHK = true
        let date = selectedDate
        Task {
            let authorized = await hk.requestAuthorization()
            guard authorized else { isLoadingHK = false; return }

            // sequential — async let LIFO crash on iOS 26 beta
            let s  = await hk.fetchSleep(for: date)
            let h  = await hk.fetchRestingHR(for: date)
            let v  = await hk.fetchHRV(for: date)
            let st = await hk.fetchSteps(for: date)
            let a  = await hk.fetchActiveEnergy(for: date)
            let m  = await hk.fetchMorningHR(for: date)
            let pw = await hk.fetchPostWorkoutHR(for: date)
            let e  = await hk.fetchEveningHR(for: date)

            if let s  { sleepHoursStr    = String(format: "%.1f", s) }
            if let h  { restingHrStr     = String(format: "%.0f", h) }
            if let v  { hrvStr           = String(format: "%.0f", v) }
            if let st { stepsStr         = "\(st)" }
            if let a  { activeEnergyStr  = String(format: "%.0f", a) }
            if let m  { hrMorningStr     = String(format: "%.0f", m) }
            if let pw { hrPostWorkoutStr = String(format: "%.0f", pw) }
            if let e  { hrEveningStr     = String(format: "%.0f", e) }

            isLoadingHK = false
        }
    }

    private func save() {
        isSaving = true
        if showFullMode {
            fullUseCount += 1
            if fullUseCount >= 3 { prefersFull = true }
        }
        Task {
            do {
                try await APIService.shared.logRecovery(
                    sleepHours:    Double(sleepHoursStr.replacingOccurrences(of: ",", with: ".")),
                    sleepQuality:  sleepQuality > 0 ? sleepQuality : nil,
                    restingHr:     Double(restingHrStr),
                    hrv:           Double(hrvStr),
                    steps:         stepsStr.isEmpty ? nil : (Int(stepsStr) ?? Int(Double(stepsStr.replacingOccurrences(of: ",", with: ".")) ?? 0)),
                    soreness:      soreness == 0 ? nil : soreness,
                    fatigue:       showFullMode ? fatigue : nil,
                    energyPre:     energyPre == 0 ? nil : energyPre,
                    activeEnergy:  activeEnergyStr.isEmpty ? nil : Double(activeEnergyStr),
                    hrMorning:     hrMorningStr.isEmpty ? nil : Double(hrMorningStr),
                    hrPostWorkout: hrPostWorkoutStr.isEmpty ? nil : Double(hrPostWorkoutStr),
                    hrEvening:     hrEveningStr.isEmpty ? nil : Double(hrEveningStr),
                    notes:         notes,
                    date:          dateStr
                )
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

struct RecoveryField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .decimalPad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .foregroundColor(.white)
                .padding(10)
                .background(Color(hex: "191926"))
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Watch Sync Banner
struct WatchSyncBannerView: View {
    @ObservedObject var sync: WatchSyncService
    let onSync: () -> Void

    private var statusText: String {
        if sync.isSyncing { return "Synchronisation en cours..." }
        if let last = sync.lastSyncDate { return "Sync Watch · \(last.formatted(.relative(presentation: .numeric)))" }
        if let err = sync.lastError { return err }
        return "Apple Watch · Appuyer pour synchroniser"
    }
    private var statusColor: Color {
        if sync.isSyncing { return .cyan }
        if sync.lastError != nil { return .red }
        return .gray
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch")
                .font(.system(size: 12)).foregroundColor(.cyan)

            Text(statusText)
                .font(.system(size: 12)).foregroundColor(statusColor)
                .lineLimit(1)

            Spacer()

            Button(action: onSync) {
                if sync.isSyncing {
                    ProgressView().tint(.cyan).scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12)).foregroundColor(.cyan)
                }
            }
            .buttonStyle(.plain)
            .disabled(sync.isSyncing)
            .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.cyan.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.12), lineWidth: 1))
        .cornerRadius(10)
    }
}

// MARK: - HRV Analysis Card

struct HRVAnalysisCard: View {
    let analysis: HRVAnalysis

    private var zoneLabel: String {
        switch analysis.hrvZone {
        case "green":  return "OPTIMAL"
        case "orange": return "NORMAL"
        case "red":    return "FAIBLE"
        default:       return "—"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── En-tête ──────────────────────────────────────────────────────
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(analysis.zoneColor)
                Text("ANALYSE HRV PERSONNALISÉE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if analysis.streakAlert {
                    Text("⚠️ FATIGUE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                } else if let zone = analysis.hrvZone {
                    Text(zoneLabel)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(analysis.zoneColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(analysis.zoneColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // ── Métriques principales ─────────────────────────────────────────
            HStack(spacing: 16) {
                if let today = analysis.todayRmssd {
                    HRVMetricPill(label: "AUJOURD'HUI", value: String(format: "%.0f ms", today), color: analysis.zoneColor)
                }
                if let avg7 = analysis.hrv7dAvg {
                    HRVMetricPill(label: "MOY. 7J", value: String(format: "%.0f ms", avg7), color: .gray)
                }
                if let avg30 = analysis.hrv30dAvg {
                    HRVMetricPill(label: "MOY. 30J", value: String(format: "%.0f ms", avg30), color: .gray)
                }
                if let cv = analysis.hrvCv {
                    HRVMetricPill(label: "CV 30J", value: String(format: "%.0f%%", cv), color: .gray)
                }
                Spacer()
            }

            // ── Score normalisé + tendance ────────────────────────────────────
            if let score = analysis.hrvScore {
                HStack(spacing: 8) {
                    Text(String(format: "%.0f%%", score))
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(analysis.zoneColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("vs ta baseline 7j")
                            .font(.system(size: 11)).foregroundColor(.gray)
                        HStack(spacing: 4) {
                            Text(analysis.trendArrow)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(analysis.trendColor)
                            if let trend = analysis.hrvTrend {
                                Text(trend == "up" ? "en hausse" : trend == "down" ? "en baisse" : "stable")
                                    .font(.system(size: 11)).foregroundColor(.gray)
                            }
                            if analysis.consecutiveLowDays >= 2 {
                                Text("· \(analysis.consecutiveLowDays)j consécutifs")
                                    .font(.system(size: 11)).foregroundColor(.orange)
                            }
                        }
                    }
                    Spacer()
                }
            }

            // ── Sparkline 7j ─────────────────────────────────────────────────
            if analysis.history7d.count >= 2 {
                HRVSparkline(points: analysis.history7d, zoneColor: analysis.zoneColor)
                    .frame(height: 36)
            }

            // ── Message contextuel ────────────────────────────────────────────
            if let msg = analysis.contextualMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(analysis.hrvZone == "red" ? .red.opacity(0.9) : .gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("\(analysis.dataPoints7d) jours dans la baseline · \(analysis.dataPoints30d) jours au total")
                    .font(.system(size: 10)).foregroundColor(.gray.opacity(0.5))
                Spacer()
                NavigationLink(destination: HRVFAQView()) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                        Text("FAQ")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.cyan.opacity(0.8))
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

private struct HRVMetricPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
            Text(value).font(.system(size: 15, weight: .black)).foregroundColor(color)
        }
    }
}

private struct HRVSparkline: View {
    let points:    [HRVDataPoint]
    let zoneColor: Color

    var body: some View {
        let values = points.map(\.hrv)
        let minV   = values.min() ?? 0
        let maxV   = values.max() ?? 1
        let range  = maxV - minV > 0 ? maxV - minV : 1

        GeometryReader { geo in
            let w   = geo.size.width
            let h   = geo.size.height
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w

            ZStack(alignment: .leading) {
                // Baseline line (avg of all points)
                let avg = values.reduce(0, +) / Double(values.count)
                let avgY = h - CGFloat((avg - minV) / range) * h
                Path { p in
                    p.move(to: CGPoint(x: 0, y: avgY))
                    p.addLine(to: CGPoint(x: w, y: avgY))
                }
                .stroke(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                // Sparkline
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h - CGFloat((pt.hrv - minV) / range) * h
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else       { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(zoneColor, lineWidth: 2)

                // Last point dot
                if let last = points.last {
                    let x = CGFloat(points.count - 1) * step
                    let y = h - CGFloat((last.hrv - minV) / range) * h
                    Circle()
                        .fill(zoneColor)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - HRV Baseline Progress

struct HRVBaselineProgressView: View {
    let dataPoints: Int
    let target = 7

    @State private var displayProgress: Double = 0

    private var progress: Double { min(1.0, Double(dataPoints) / Double(target)) }
    private var daysLeft: Int    { max(0, target - dataPoints) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundColor(.cyan)
                Text("BASELINE EN CONSTRUCTION")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
            }

            Text("Continue — ta baseline personnelle se construit.")
                .font(.system(size: 14, weight: .medium)).foregroundColor(.white)

            Text(daysLeft > 0
                 ? "\(daysLeft) jour\(daysLeft > 1 ? "s" : "") de plus pour des insights précis."
                 : "Baseline prête dans quelques instants.")
                .font(.system(size: 13)).foregroundColor(.gray)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.cyan)
                        .frame(width: geo.size.width * displayProgress, height: 8)
                }
            }
            .frame(height: 8)

            Text("\(dataPoints) / \(target) jours de données collectés")
                .font(.system(size: 11)).foregroundColor(.gray.opacity(0.6))
        }
        .padding(14)
        .glassCard(color: .cyan, intensity: 0.05).cornerRadius(14)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { displayProgress = progress }
        }
    }
}

// MARK: - HRV Contextual Tip (one-time dismissable)

struct HRVContextualTipView: View {
    let tipId:      String
    let icon:       String
    let message:    String
    var accentColor: Color = .cyan

    @State private var dismissed = false
    private var shownKey: String { "hrv_tip_shown_\(tipId)" }

    var body: some View {
        if !dismissed && !UserDefaults.standard.bool(forKey: shownKey) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(accentColor)
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    UserDefaults.standard.set(true, forKey: shownKey)
                    withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.6))
                        .frame(width: 22, height: 22)
                }
            }
            .padding(10)
            .background(accentColor.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accentColor.opacity(0.12), lineWidth: 1))
            .cornerRadius(10)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - HRV Morning Nudge (Today page)

struct HRVMorningNudgeView: View {
    let analysis: HRVAnalysis?

    private var currentHour: Int { Calendar.current.component(.hour, from: Date()) }

    private enum MorningState { case received, missingAfter9, watchNotWorn, tooEarly }

    private var state: MorningState {
        guard let a = analysis else { return .tooEarly }
        if a.todayRmssd != nil { return .received }
        if currentHour < 9    { return .tooEarly }
        if a.dataPoints7d > 0 { return .missingAfter9 }
        return .watchNotWorn
    }

    var body: some View {
        switch state {
        case .received, .tooEarly:
            EmptyView()
        case .missingAfter9:
            HRVNudgeBanner(
                icon: "waveform.path.ecg",
                message: "Mesure HRV manquante ce matin — pense à rester allongé quelques secondes demain.",
                color: .orange
            )
        case .watchNotWorn:
            HRVNudgeBanner(
                icon: "applewatch",
                message: "Porte ton Apple Watch cette nuit pour une mesure HRV fiable.",
                color: .cyan
            )
        }
    }
}

private struct HRVNudgeBanner: View {
    let icon: String; let message: String; let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            Text(message).font(.system(size: 12)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(color.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15), lineWidth: 1))
        .cornerRadius(10)
    }
}

// MARK: - HRV FAQ Sheet

struct HRVFAQView: View {
    private let items: [(String, String)] = [
        ("Pourquoi mesurer le matin ?",
         "Le matin au réveil, ton corps est dans son état le plus stable — pas encore influencé par l'effort, la caféine ou le stress. C'est le seul moment où la mesure est comparable d'un jour à l'autre."),
        ("Pourquoi rester allongé ?",
         "Le simple fait de se lever fait monter la fréquence cardiaque et perturbe le HRV pendant plusieurs minutes. Rester allongé garantit une mesure propre et reproductible."),
        ("Ma valeur est-elle bonne ou mauvaise ?",
         "La valeur absolue ne signifie rien sans contexte. 40 ms peut être excellent pour toi, faible pour quelqu'un d'autre. Ce qui compte : ta valeur du jour vs ta propre baseline. C'est ce que VinceSeven calcule."),
        ("Pourquoi ça change chaque jour ?",
         "Le HRV réagit à tout : sommeil, alcool, stress, volume d'entraînement, alimentation. Une variation d'un jour à l'autre est normale. La tendance sur 7 jours est le signal utile."),
        ("Alcool, stress, manque de sommeil — quel impact ?",
         "Alcool : baisse significative le lendemain, même en petite quantité. Manque de sommeil : baisse proportionnelle à la dette de sommeil. Stress chronique : baisse graduelle sur 5-10 jours."),
        ("Comment lire vert / orange / rouge ?",
         "Vert (≥110% de ta baseline 7j) : récupération optimale, séance à 100%. Orange (90-109%) : dans la norme, séance normale. Rouge (<90%) : récupération incomplète, réduis le volume."),
        ("Et si je n'ai pas de mesure ce matin ?",
         "Aucun problème — l'app n'invente pas de valeur. Ton coaching reste actif basé sur les données récentes. Pas de culpabilité : une mesure manquante n'affecte pas ta baseline."),
    ]

    var body: some View {
        ZStack {
            AmbientBackground(color: .cyan)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HRVFAQItem(question: item.0, answer: item.1)
                    }
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 20)
            }
        }
        .navigationTitle("HRV — Questions fréquentes")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct HRVFAQItem: View {
    let question: String; let answer: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Text(question).font(.system(size: 14, weight: .semibold)).foregroundColor(.white).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(answer).font(.system(size: 13)).foregroundColor(.gray).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .background(Color.appCard).cornerRadius(12)
    }
}

// MARK: - Recovery Performance Banner

private struct RecoveryPerformanceBanner: View {
    let dashboard: DashboardData?
    let hrvAnalysis: HRVAnalysis?
    let recoveryScore: Double?
    var onTap: (() -> Void)? = nil

    private enum BannerState {
        case rest
        case hrvCritical
        case low(Double)
        case moderate
        case good(Double)
    }

    private var bannerState: BannerState? {
        guard let dash = dashboard else { return nil }
        let t = dash.today.lowercased()
        let isRest = t.isEmpty || t == "repos" || t == "rest"
        if isRest { return .rest }

        if let hrv = hrvAnalysis, hrv.baselineAvailable, hrv.hrvZone == "red" {
            return .hrvCritical
        }

        guard let score = recoveryScore else { return nil }
        if score < 4.0  { return .low(score) }
        if score <= 6.5 { return .moderate }
        return .good(score)
    }

    private typealias Cfg = (icon: String, text: String, color: Color)

    private func config(for state: BannerState) -> Cfg {
        switch state {
        case .rest:
            return ("moon.zzz.fill",
                    "Journée de repos — profites-en pour récupérer.",
                    .gray)
        case .hrvCritical:
            return ("waveform.path.ecg",
                    "HRV sous ta baseline — priorise la récupération, réduis l'intensité.",
                    .red)
        case .low(let s):
            return ("exclamationmark.triangle.fill",
                    "Récupération à \(String(format: "%.1f", s))/10 — réduis le volume de ta séance aujourd'hui.",
                    .orange)
        case .moderate:
            return ("bolt.fill",
                    "Récupération modérée — reste sur le programme, écoute ton corps.",
                    Color(red: 1, green: 0.6, blue: 0))
        case .good(let s):
            return ("checkmark.circle.fill",
                    "Bonne récupération (\(String(format: "%.1f", s))/10) — conditions optimales pour ta séance.",
                    .green)
        }
    }

    var body: some View {
        if let state = bannerState {
            let c = config(for: state)
            Button { onTap?() } label: {
                HStack(spacing: 10) {
                    Image(systemName: c.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(c.color)
                        .frame(width: 20)
                    Text(c.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.85))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(c.color.opacity(0.08))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(c.color.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
        }
    }
}
