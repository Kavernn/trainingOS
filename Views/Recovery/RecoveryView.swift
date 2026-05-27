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
    @EnvironmentObject private var appState: AppState
    @State private var log: [RecoveryEntry] = []
    @State private var isLoading = true
    @State private var showSheet = false
    @State private var editTarget: RecoveryEntry? = nil
    @State private var apiError: String? = nil
    @State private var toast: ToastMessage? = nil
    @ObservedObject private var watchSync = WatchSyncService.shared
    @State private var isBackfilling = false
    @State private var backfillDone  = false
    @State private var stats = RecoveryStats(log: [])
    @State private var hrvAnalysis: HRVAnalysis? = nil
    @State private var dailySummary: DailySummary? = nil
    @AppStorage("hrv_onboarding_done") private var hrvOnboardingDone = false
    @State private var showHRVOnboarding = false

    private var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    private var entriesMissingHK: [RecoveryEntry] {
        log.filter { $0.restingHr == nil || $0.hrv == nil }
    }

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

                            // Watch sync status (iOS uniquement — HealthKit non dispo sur Mac)
                            #if !targetEnvironment(macCatalyst)
                            WatchSyncBannerView(sync: watchSync) {
                                Task {
                                    await watchSync.requestAuthorizationAndSync()
                                    await loadData()
                                }
                            }
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0)
                            #endif

                            // HealthKit backfill banner
                            #if !targetEnvironment(macCatalyst)
                            if !entriesMissingHK.isEmpty && !backfillDone {
                                HStack(spacing: 10) {
                                    Image(systemName: "heart.text.square.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 15))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(entriesMissingHK.count) entrée\(entriesMissingHK.count > 1 ? "s" : "") sans FC / HRV")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("Synchroniser depuis Apple Santé")
                                            .font(.system(size: 10))
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Button {
                                        Task { await backfillFromHealthKit() }
                                    } label: {
                                        if isBackfilling {
                                            ProgressView().tint(.white).scaleEffect(0.75)
                                        } else {
                                            Text("Sync")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .background(Color.red.opacity(0.8))
                                                .cornerRadius(8)
                                        }
                                    }
                                    .disabled(isBackfilling)
                                }
                                .padding(12)
                                .background(Color.red.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                            }
                            #endif

                            // KPI grid — récupération
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    KPICard(value: String(format: "%.1f/10", avgFatigue),
                                            label: "Fatigue moy.", color: avgFatigue >= 7 ? .red : (avgFatigue >= 4 ? .orange : .green))
                                }
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.055)
                            }

                            // KPI grid — FC journalière
                            if avgHRMorning > 0 || avgHRPostWorkout > 0 || avgHREvening > 0 {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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

                            // Contextual tips HRV (une seule fois par scénario)
                            if let hrv = hrvAnalysis {
                                if hrv.streakAlert {
                                    HRVContextualTipView(
                                        tipId: "streak_alert",
                                        icon: "exclamationmark.triangle.fill",
                                        message: "Ton HRV est sous ta baseline depuis \(hrv.consecutiveLowDays) jours consécutifs. Priorité à la récupération — réduis le volume cette semaine."
                                    )
                                    .padding(.horizontal, 16)
                                }
                                if hrv.hrvCv ?? 0 > 20 {
                                    HRVContextualTipView(
                                        tipId: "high_cv",
                                        icon: "waveform.path.ecg",
                                        message: "Ton HRV est très variable (\(Int(hrv.hrvCv ?? 0))% CV). C'est normal au début — continue à mesurer chaque matin pour stabiliser ta baseline."
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }

                            // Readiness card
                            if let today = log.first(where: { $0.date == todayStr }) {
                                ReadinessCard(entry: today, backendScore: dailySummary?.recoveryScore,
                                              hrv7dBaseline: hrvAnalysis?.hrv7dAvg)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.08)
                            }

                            // HRV chart
                            let hrvEntries = Array(log.prefix(14).reversed())
                            if hrvEntries.filter({ $0.hrv != nil }).count >= 2 {
                                HRVChart(entries: hrvEntries)
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
                                RecoveryEmptyState()
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("HISTORIQUE")
                                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        .padding(.horizontal, 16)
                                    ForEach(log) { entry in
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
            isBackfilling = false
            backfillDone  = true
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
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
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
                HStack(spacing: 10) {
                    if let h = entry.sleepHours {
                        Label(String(format: "%.1fh", h), systemImage: "moon.fill")
                            .font(.system(size: 11)).foregroundColor(.blue)
                    }
                    if let q = entry.sleepQuality {
                        Label(String(format: "%.0f/10", q), systemImage: "star.fill")
                            .font(.system(size: 11)).foregroundColor(.purple)
                    }
                    if let hr = entry.restingHr {
                        Label(String(format: "%.0f bpm", hr), systemImage: "heart.fill")
                            .font(.system(size: 11)).foregroundColor(.red)
                    }
                }
                if let s = entry.steps {
                    Label("\(s) pas", systemImage: "figure.walk")
                        .font(.system(size: 11)).foregroundColor(.green)
                }
            }

            Spacer()

            if let soreness = entry.soreness {
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", soreness))
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(sorenessColor(soreness))
                    Text("douleurs")
                        .font(.system(size: 9)).foregroundColor(.gray)
                }
            }

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .frame(width: 30, height: 30)
                        .background(Color.orange.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(12)
        .confirmationDialog("Supprimer cette entrée ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func sorenessColor(_ v: Double) -> Color {
        if v >= 7 { return .red }; if v >= 4 { return .orange }; return .green
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
    var maxHRV: Double { max(entries.compactMap(\.hrv).max() ?? 1, 80) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HRV — 14 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let hrv   = e.hrv ?? 0
                    let pct   = maxHRV > 0 ? hrv / maxHRV : 0
                    let color: Color = hrv >= 50 ? .green : (hrv >= 30 ? .orange : .red)
                    VStack(spacing: 2) {
                        if hrv > 0 {
                            Text(String(format: "%.0f", hrv))
                                .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(hrv > 0 ? color.opacity(i == entries.count - 1 ? 1 : 0.55) : Color.clear)
                            .frame(height: max(hrv > 0 ? CGFloat(pct) * 60 : 0, hrv > 0 ? 2 : 0))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
            HStack(spacing: 12) {
                legendDot(.green,  "≥50 ms")
                legendDot(.orange, "30-50 ms")
                legendDot(.red,    "<30 ms")
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

// MARK: - RHR Chart

struct RHRChart: View {
    let entries: [RecoveryEntry]
    // Inverted: lower RHR = better. Display as distance from ceiling (85 bpm).
    private let ceiling: Double = 85

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FC REPOS — 14 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let hr    = e.restingHr ?? 0
                    // Normalize: bar height = how LOW the HR is (good = tall bar)
                    let pct   = hr > 0 ? max(0, (ceiling - hr) / (ceiling - 35)) : 0
                    let color: Color = hr > 0 ? (hr <= 55 ? .green : (hr <= 65 ? .orange : .red)) : .clear
                    VStack(spacing: 2) {
                        if hr > 0 {
                            Text(String(format: "%.0f", hr))
                                .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(hr > 0 ? color.opacity(i == entries.count - 1 ? 1 : 0.55) : Color.clear)
                            .frame(height: max(hr > 0 ? CGFloat(pct) * 60 : 0, hr > 0 ? 2 : 0))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
            HStack(spacing: 12) {
                legendDot(.green,  "≤55 bpm")
                legendDot(.orange, "55-65 bpm")
                legendDot(.red,    ">65 bpm")
                Spacer()
                Text("Barre haute = FC basse = mieux")
                    .font(.system(size: 8)).foregroundColor(.gray.opacity(0.6))
            }
        }
        .padding(16).glassCard(color: .red, intensity: 0.04).cornerRadius(14)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
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
    var maxH: Double { max(entries.compactMap(\.sleepHours).max() ?? 1, 9) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOMMEIL — DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let h = e.sleepHours ?? 0
                    let pct = maxH > 0 ? h / maxH : 0
                    let color: Color = h >= 7 ? .blue : (h >= 5 ? .orange : .red)
                    VStack(spacing: 2) {
                        if h > 0 {
                            Text(String(format: "%.0fh", h))
                                .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(i == entries.count - 1 ? 1 : 0.5))
                            .frame(height: max(CGFloat(pct) * 60, 2))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text("≥7h").font(.system(size: 9)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("5-7h").font(.system(size: 9)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("<5h").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .blue, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Steps Chart
struct StepsChart: View {
    let entries: [RecoveryEntry]
    var maxSteps: Double { max(entries.compactMap(\.steps).map(Double.init).max() ?? 1, 10_000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAS — DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let steps = Double(e.steps ?? 0)
                    let pct   = maxSteps > 0 ? steps / maxSteps : 0
                    let color: Color = steps >= 10_000 ? .green : (steps >= 7_000 ? .orange : .red)
                    VStack(spacing: 2) {
                        if steps > 0 {
                            Text(steps >= 1000 ? String(format: "%.0fk", steps / 1000) : "\(Int(steps))")
                                .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(i == entries.count - 1 ? 1 : 0.5))
                            .frame(height: max(CGFloat(pct) * 60, 2))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("≥10k").font(.system(size: 9)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("7k-10k").font(.system(size: 9)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("<7k").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .green, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Empty State
struct RecoveryEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "moon.zzz.fill", title: "Aucune donnée de récupération", subtitle: "Appuie sur + pour en ajouter une")
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
    @State private var sleepQuality: Double = 7
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

                        // Date picker
                        DatePicker("Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(14).background(Color.appCard).cornerRadius(12)

                        // HealthKit auto-fill button
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

                        // Sleep
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
                                Slider(value: $sleepQuality, in: 1...10, step: 1)
                                    .tint(.orange)
                            }
                        }
                        .padding(14).background(Color.appCard).cornerRadius(12)

                        // Douleurs musculaires + Fatigue perçue (Hooper Index)
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("DOULEURS MUSCULAIRES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    Spacer()
                                    Text(String(format: "%.0f / 10", soreness))
                                        .font(.system(size: 13, weight: .bold)).foregroundColor(sorenessColor(soreness))
                                }
                                Slider(value: $soreness, in: 0...10, step: 1)
                                    .tint(sorenessColor(soreness))
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
                                    Text(String(format: "%.0f / 10", fatigue))
                                        .font(.system(size: 13, weight: .bold)).foregroundColor(fatigueColor(fatigue))
                                }
                                Slider(value: $fatigue, in: 0...10, step: 1)
                                    .tint(fatigueColor(fatigue))
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
                                        Text(String(format: "%.0f / 10", energyPre))
                                            .font(.system(size: 13, weight: .bold)).foregroundColor(energyPreColor(energyPre))
                                    }
                                }
                                Slider(value: $energyPre, in: 0...10, step: 1)
                                    .tint(energyPre == 0 ? .gray : energyPreColor(energyPre))
                                HStack {
                                    Text("0 = Non renseigné").font(.system(size: 9)).foregroundColor(.gray)
                                    Spacer()
                                    Text("10 = Excellent").font(.system(size: 9)).foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(14).background(Color.appCard).cornerRadius(12)

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

                        Button(action: save) {
                            Group {
                                if isSaving { ProgressView().tint(.white) }
                                else { Text("Enregistrer").font(.system(size: 15, weight: .semibold)).foregroundColor(.white) }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.orange).cornerRadius(14)
                        .buttonStyle(SpringButtonStyle())
                    }
                    .padding(20)
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
        Task {
            do {
                try await APIService.shared.logRecovery(
                    sleepHours:    Double(sleepHoursStr.replacingOccurrences(of: ",", with: ".")),
                    sleepQuality:  sleepQuality,
                    restingHr:     Double(restingHrStr),
                    hrv:           Double(hrvStr),
                    steps:         stepsStr.isEmpty ? nil : (Int(stepsStr) ?? Int(Double(stepsStr.replacingOccurrences(of: ",", with: ".")) ?? 0)),
                    soreness:      soreness == 0 ? nil : soreness,
                    fatigue:       fatigue,
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch")
                .font(.system(size: 14))
                .foregroundColor(.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Watch")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                if sync.isSyncing {
                    Text("Synchronisation...")
                        .font(.system(size: 10)).foregroundColor(.cyan)
                } else if let last = sync.lastSyncDate {
                    Text("Dernière sync : \(last, style: .relative)")
                        .font(.system(size: 10)).foregroundColor(.gray)
                } else if let err = sync.lastError {
                    Text(err)
                        .font(.system(size: 10)).foregroundColor(.red)
                } else {
                    Text("Appuyer pour synchroniser")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
            }

            Spacer()

            Button(action: onSync) {
                Group {
                    if sync.isSyncing {
                        ProgressView().tint(.cyan).scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundColor(.cyan)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(sync.isSyncing)
        }
        .padding(12)
        .background(Color.cyan.opacity(0.08))
        .cornerRadius(12)
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

    private var progress: Double { min(1.0, Double(dataPoints) / Double(target)) }
    private var daysLeft: Int    { max(0, target - dataPoints) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundColor(.cyan)
                Text("BASELINE EN CONSTRUCTION")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
            }
            Text("Continue — ta baseline personnelle se construit.")
                .font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            Text(daysLeft > 0
                 ? "\(daysLeft) jour\(daysLeft > 1 ? "s" : "") de plus pour des insights précis."
                 : "Baseline prête dans quelques instants.")
                .font(.system(size: 13)).foregroundColor(.gray)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4).fill(Color.cyan)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.easeOut(duration: 0.6), value: progress)
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(dataPoints) / \(target) jours collectés")
                    .font(.system(size: 11)).foregroundColor(.gray.opacity(0.7))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.cyan)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - HRV Contextual Tip (one-time dismissable)

struct HRVContextualTipView: View {
    let tipId:   String
    let icon:    String
    let message: String

    @State private var dismissed = false
    private var shownKey: String { "hrv_tip_shown_\(tipId)" }

    var body: some View {
        if !dismissed && !UserDefaults.standard.bool(forKey: shownKey) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 15)).foregroundColor(.cyan).padding(.top, 1)
                Text(message).font(.system(size: 13)).foregroundColor(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    UserDefaults.standard.set(true, forKey: shownKey)
                    withAnimation { dismissed = true }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            .padding(12)
            .background(Color.cyan.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.15), lineWidth: 1))
            .cornerRadius(12)
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
