import SwiftUI
import OSLog

private let logger = Logger(subsystem: "TrainingOS", category: "Recovery")

private enum RecoveryViewTab { case today, history }

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

// MARK: - RecoveryDayCell

private struct RecoveryDayCell: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    let isHK: Bool
    var infoEntry: InfoEntry? = nil

    @State private var showInfo = false

    var body: some View {
        Button {
            if infoEntry != nil { showInfo = true }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.appHeadline.weight(.medium))
                        .foregroundColor(value == "—" ? .gray.opacity(0.5) : color)
                    if isHK && value == "—" {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.red.opacity(0.65))
                            .offset(x: 7, y: -3)
                    } else if infoEntry != nil {
                        Image(systemName: "info.circle")
                            .font(.system(size: 7))
                            .foregroundColor(.gray.opacity(0.45))
                            .offset(x: 7, y: -3)
                    }
                }
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(value == "—" ? .gray.opacity(0.5) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(label)
                    .font(.appMicro.weight(.medium))
                    .foregroundColor(.gray)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showInfo) {
            if let entry = infoEntry {
                InfoSheetView(title: label, entries: [entry])
            }
        }
    }
}

// MARK: - RecoveryHeroCard

private struct RecoveryHeroCard: View {
    let score: Double?
    let hrv: Double?
    let sleepHours: Double?
    let restingHr: Double?
    let isSyncing: Bool
    let lastSyncLabel: String
    let formattedDate: String
    let onSync: () -> Void

    @State private var displayScore: Double = 0

    private var scoreInt: Int { score.map { Int($0 * 100) } ?? 0 }

    private var scoreColor: Color {
        guard score != nil else { return .gray }
        if scoreInt >= 80 { return .green }
        if scoreInt >= 60 { return Color(red: 1.0, green: 0.78, blue: 0.0) }
        if scoreInt >= 40 { return .orange }
        return .red
    }

    private var gradientTop: Color {
        guard score != nil else { return .gray.opacity(0.12) }
        if scoreInt >= 80 { return .green.opacity(0.28) }
        if scoreInt >= 60 { return Color(red: 1.0, green: 0.78, blue: 0.0).opacity(0.22) }
        if scoreInt >= 40 { return .orange.opacity(0.24) }
        return .red.opacity(0.24)
    }

    private var verdictLabel: String {
        guard score != nil else { return "En attente de données" }
        if scoreInt >= 80 { return "Prêt(e) à performer" }
        if scoreInt >= 60 { return "Récupération modérée" }
        if scoreInt >= 40 { return "Récupération incomplète" }
        return "Repos prioritaire"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate)
                        .font(.appLabel)
                        .foregroundColor(.white.opacity(0.85))
                    Text(lastSyncLabel)
                        .font(.appCaption)
                        .foregroundColor(.gray.opacity(0.65))
                }
                Spacer()
                #if !targetEnvironment(macCatalyst)
                Button(action: onSync) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.appCaption.weight(.bold))
                            .rotationEffect(.degrees(isSyncing ? 360 : 0))
                            .animation(
                                isSyncing
                                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                    : .default,
                                value: isSyncing
                            )
                        Text("Sync")
                            .font(.appCaption.weight(.semibold))
                    }
                    .foregroundColor(isSyncing ? .gray : scoreColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(SpringButtonStyle())
                .disabled(isSyncing)
                #endif
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(displayScore))")
                        .font(.system(size: 68, weight: .black, design: .rounded))
                        .foregroundColor(scoreColor)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    if score != nil {
                        Text("/100")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor.opacity(0.55))
                            .padding(.bottom, 6)
                    }
                }
                Text(verdictLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray.opacity(0.75))
            }
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                heroPill(icon: "waveform.path.ecg",
                         label: "HRV",
                         value: hrv.map { String(format: "%.0f ms", $0) },
                         color: .green)
                heroPill(icon: "moon.zzz.fill",
                         label: "Sommeil",
                         value: sleepHours.map { String(format: "%.1f h", $0) },
                         color: .blue)
                heroPill(icon: "heart.fill",
                         label: "FC repos",
                         value: restingHr.map { String(format: "%.0f bpm", $0) },
                         color: .red)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .background(
            ZStack {
                Color.appCard
                LinearGradient(colors: [gradientTop, gradientTop.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
            }
        )
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(scoreColor.opacity(score != nil ? 0.20 : 0.08), lineWidth: 1))
        .onAppear { animateScore() }
        .onChange(of: score) { _, _ in animateScore() }
    }

    private func animateScore() {
        withAnimation(.easeOut(duration: 1.2)) { displayScore = (score ?? 0) * 100 }
    }

    private func heroPill(icon: String, label: String, value: String?, color: Color) -> some View {
        let hasValue = value != nil
        return VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(hasValue ? color : .gray.opacity(0.35))
            Text(value ?? "—")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(hasValue ? .white : .gray.opacity(0.4))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundColor(.gray.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(hasValue ? 0.10 : 0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(color.opacity(hasValue ? 0.18 : 0.06), lineWidth: 1))
    }
}

// MARK: - RecoveryView

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
    @State private var readinessData: ReadinessResponse? = nil
    @AppStorage("hrv_onboarding_done") private var hrvOnboardingDone = false
    @State private var showHRVOnboarding = false

    // Tab + HK sync
    @State private var activeTab: RecoveryViewTab = .today
    @State private var isSyncingHK = false
    @State private var syncSuccess = false
    @AppStorage("last_hk_sync_recovery") private var lastHKSyncTimestamp: Double = 0
    @State private var hkSpO2: Double? = nil
    @State private var hkWristTemp: Double? = nil

    private var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private var formattedToday: String {
        Self.dayFmt.string(from: Date()).capitalized
    }

    private var lastSyncLabel: String {
        guard lastHKSyncTimestamp > 0 else { return "Jamais synchronisé" }
        let date = Date(timeIntervalSince1970: lastHKSyncTimestamp)
        let mins = Int(-date.timeIntervalSinceNow / 60)
        if mins < 1 { return "Synced à l'instant" }
        if mins < 60 { return "Synced il y a \(mins) min" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "Synced à \(f.string(from: date))"
    }

    private var entriesMissingHK: [RecoveryEntry] {
        let cutoff = Calendar.current.safeDateByAdding(.day, value: -7, to: Date())
        return log.filter {
            guard let d = $0.date, let date = Self.isoFmt.date(from: d) else { return false }
            return date >= cutoff && ($0.restingHr == nil || $0.hrv == nil)
        }
    }

    private var backfillDone: Bool { backfillDoneDate == todayStr }

    private var alreadyLoggedToday: Bool {
        log.contains { $0.date == todayStr }
    }

    private var todayEntry: RecoveryEntry? {
        log.first(where: { $0.date == todayStr })
    }

    // KPIs — cached per loadData
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
                    VStack(spacing: 0) {
                        pillBar
                        if activeTab == .today {
                            todayScrollView
                        } else {
                            historyScrollView
                        }
                    }
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
                    if alreadyLoggedToday, let entry = todayEntry {
                        editTarget = entry
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
            hkSpO2      = await HealthKitService.shared.fetchLatestSpO2()
            hkWristTemp = await HealthKitService.shared.fetchLatestWristTemperature()
            if !hrvOnboardingDone {
                showHRVOnboarding = true
            }
        }
        .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(apiError ?? "") }
        .toast($toast)
        .sensoryFeedback(.success, trigger: syncSuccess)
        .onChange(of: watchSync.lastSyncCompleted) { _, _ in
            Task { await loadData() }
        }
    }

    // MARK: - Pill Bar

    private var pillBar: some View {
        HStack(spacing: 0) {
            pillButton(title: "Aujourd'hui", icon: "sun.max.fill", tab: .today)
            pillButton(title: "Historique", icon: "chart.line.uptrend.xyaxis", tab: .history)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appBg.opacity(0.85))
    }

    private func pillButton(title: String, icon: String, tab: RecoveryViewTab) -> some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { activeTab = tab } } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.appCaption.weight(.semibold))
                Text(title).font(.appLabel.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(activeTab == tab ? Color.orange : Color.clear)
            .foregroundColor(activeTab == tab ? .white : .gray)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today Tab

    private var todayScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                RecoveryHeroCard(
                    score: readinessData.map { Double($0.score) / 10.0 },
                    hrv: todayEntry?.hrv,
                    sleepHours: todayEntry?.sleepHours,
                    restingHr: todayEntry?.restingHr,
                    isSyncing: isSyncingHK,
                    lastSyncLabel: lastSyncLabel,
                    formattedDate: formattedToday,
                    onSync: { Task { await syncHealthKitNow() } }
                )
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0)

                metricGrid
                    .padding(.horizontal, 16)
                    .appearAnimation(delay: 0.06)

                Button {
                    if alreadyLoggedToday, let entry = todayEntry {
                        editTarget = entry
                    } else {
                        showSheet = true
                    }
                } label: {
                    Label(
                        alreadyLoggedToday ? "Modifier la saisie manuelle" : "Compléter manuellement",
                        systemImage: alreadyLoggedToday ? "pencil" : "plus.circle"
                    )
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassCard()
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.08)

                Spacer(minLength: 32)
            }
            .padding(.vertical, 16)
            .padding(.bottom, contentBottomPadding)
        }
        .refreshable {
            await loadData()
        }
    }

    private var metricGrid: some View {
        let entry = todayEntry
        let stepsStr: String = {
            guard let s = entry?.steps else { return "—" }
            let n = NSNumber(value: s)
            return NumberFormatter.localizedString(from: n, number: .decimal)
        }()
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            Group {
                RecoveryDayCell(icon: "moon.zzz.fill",
                                value: entry?.sleepHours.map { String(format: "%.1fh", $0) } ?? "—",
                                label: "Sommeil", color: .blue, isHK: true,
                                infoEntry: .sleepDurationMetric)
                RecoveryDayCell(icon: "star.fill",
                                value: entry?.sleepQuality.map { String(format: "%.1f/10", $0) } ?? "—",
                                label: "Qualité sommeil", color: .purple, isHK: false,
                                infoEntry: .sleepQualityMetric)
                RecoveryDayCell(icon: "heart.fill",
                                value: entry?.restingHr.map { String(format: "%.0f bpm", $0) } ?? "—",
                                label: "FC repos", color: .red, isHK: true,
                                infoEntry: .restingHrMetric)
                RecoveryDayCell(icon: "waveform.path.ecg",
                                value: entry?.hrv.map { String(format: "%.0f ms", $0) } ?? "—",
                                label: "HRV", color: hrvAnalysis?.zoneColor ?? .green, isHK: true,
                                infoEntry: .hrvMetric)
                RecoveryDayCell(icon: "figure.walk",
                                value: stepsStr,
                                label: "Pas", color: .teal, isHK: true,
                                infoEntry: .stepsMetric)
                RecoveryDayCell(icon: "flame.fill",
                                value: entry?.activeEnergy.map { String(format: "%.0f kcal", $0) } ?? "—",
                                label: "Énergie active", color: .orange, isHK: true,
                                infoEntry: .activeEnergyMetric)
            }
            Group {
                RecoveryDayCell(icon: "sunrise.fill",
                                value: entry?.hrMorning.map { String(format: "%.0f bpm", $0) } ?? "—",
                                label: "FC matin", color: .cyan, isHK: true,
                                infoEntry: .hrMorningMetric)
                RecoveryDayCell(icon: "dumbbell.fill",
                                value: entry?.hrPostWorkout.map { String(format: "%.0f bpm", $0) } ?? "—",
                                label: "FC post séance", color: Color(red: 1, green: 0.42, blue: 0.12), isHK: true,
                                infoEntry: .hrPostWorkoutMetric)
                RecoveryDayCell(icon: "moon.fill",
                                value: entry?.hrEvening.map { String(format: "%.0f bpm", $0) } ?? "—",
                                label: "FC soir", color: .indigo, isHK: true,
                                infoEntry: .hrEveningMetric)
                RecoveryDayCell(icon: "bolt.fill",
                                value: entry?.soreness.map { String(format: "%.1f/10", $0) } ?? "—",
                                label: "Courbatures", color: .yellow, isHK: false,
                                infoEntry: .sorenessMetric)
                RecoveryDayCell(icon: "battery.25percent",
                                value: entry?.fatigue.map { String(format: "%.1f/10", $0) } ?? "—",
                                label: "Fatigue", color: .red, isHK: false,
                                infoEntry: .fatigueMetric)
                RecoveryDayCell(icon: "bolt.circle.fill",
                                value: entry?.energyPre.map { String(format: "%.1f/10", $0) } ?? "—",
                                label: "Énergie pré", color: .mint, isHK: false,
                                infoEntry: .energyPreMetric)
                RecoveryDayCell(icon: "lungs.fill",
                                value: hkSpO2.map { String(format: "%.0f%%", $0) } ?? "—",
                                label: "SpO2", color: .blue, isHK: true,
                                infoEntry: .spo2Metric)
                RecoveryDayCell(icon: "thermometer.medium",
                                value: hkWristTemp.map { String(format: "%@%.1f°C", $0 >= 0 ? "+" : "", $0) } ?? "—",
                                label: "Temp. poignet", color: .mint, isHK: true,
                                infoEntry: .wristTempMetric)
            }
        }
    }

    // MARK: - History Tab

    private var historyScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {

                // Backfill banner
                #if !targetEnvironment(macCatalyst)
                if !entriesMissingHK.isEmpty && !backfillDone {
                    HStack(spacing: 10) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.appLabel).foregroundColor(.red)
                        Text("\(entriesMissingHK.count) entrée\(entriesMissingHK.count > 1 ? "s" : "") sans FC/HRV")
                            .font(.appCaption.weight(.semibold)).foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Button { Task { await backfillFromHealthKit() } } label: {
                            if isBackfilling {
                                ProgressView().tint(.red).scaleEffect(0.65)
                            } else {
                                Text("Sync")
                                    .font(.appCaption.weight(.semibold)).foregroundColor(.red)
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
                .appearAnimation(delay: 0.02)

                if avgFatigue > 0 {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        KPICard(value: String(format: "%.1f/10", avgFatigue),
                                label: "Fatigue moy.", color: avgFatigue >= 7 ? .red : (avgFatigue >= 4 ? .orange : .green))
                    }
                    .padding(.horizontal, 16)
                    .appearAnimation(delay: 0.025)
                }

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
                    .appearAnimation(delay: 0.03)
                }

                // HRV Analysis card
                if let hrv = hrvAnalysis, hrv.baselineAvailable || hrv.todayRmssd != nil {
                    HRVAnalysisCard(analysis: hrv)
                        .padding(.horizontal, 16)
                        .appearAnimation(delay: 0.04)
                }

                if let hrv = hrvAnalysis, hrv.dataPoints7d < 7 {
                    HRVBaselineProgressView(dataPoints: hrv.dataPoints7d)
                        .padding(.horizontal, 16)
                        .appearAnimation(delay: 0.045)
                }

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

                // Charts
                let hrvEntries = Array(log.prefix(14).reversed())
                if hrvEntries.filter({ $0.hrv != nil }).count >= 2 {
                    HRVChart(entries: hrvEntries,
                             baseline: hrvAnalysis?.hrv7dAvg,
                             zoneColor: hrvAnalysis?.zoneColor ?? .green)
                        .padding(.horizontal, 16)
                        .appearAnimation(delay: 0.05)
                }

                if hrvEntries.filter({ $0.restingHr != nil }).count >= 2 {
                    RHRChart(entries: hrvEntries)
                        .padding(.horizontal, 16)
                        .appearAnimation(delay: 0.06)
                }

                if hrvEntries.filter({ $0.hrMorning != nil || $0.hrPostWorkout != nil || $0.hrEvening != nil }).count >= 2 {
                    HRMomentsChart(entries: hrvEntries)
                        .padding(.horizontal, 16)
                        .appearAnimation(delay: 0.07)
                }

                if log.filter({ $0.sleepHours != nil }).count >= 2 {
                    SleepChart(entries: Array(log.prefix(10).reversed()))
                        .padding(.horizontal, 16)
                } else {
                    EmptyChartPlaceholder(message: "Logge au moins 2 nuits pour voir l'évolution du sommeil")
                        .padding(.horizontal, 16)
                }

                if log.filter({ $0.steps != nil }).count >= 2 {
                    StepsChart(entries: Array(log.prefix(10).reversed()))
                        .padding(.horizontal, 16)
                } else {
                    EmptyChartPlaceholder(message: "Logge au moins 2 jours de pas pour voir la tendance")
                        .padding(.horizontal, 16)
                }

                // History list
                if log.isEmpty {
                    RecoveryEmptyState(onAddTap: { showSheet = true })
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("HISTORIQUE")
                            .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
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

    // MARK: - Data

    private func loadData() async {
        isLoading = true
        log = (try? await APIService.shared.fetchRecoveryData()) ?? []
        stats = RecoveryStats(log: log)
        // sequential — async let LIFO crash on iOS 26 beta
        let analysis  = try? await APIService.shared.fetchHRVAnalysis()
        let readiness = try? await APIService.shared.fetchReadiness()
        await MainActor.run {
            hrvAnalysis   = analysis
            readinessData = readiness
            isLoading     = false
        }
    }

    #if !targetEnvironment(macCatalyst)
    private func syncHealthKitNow() async {
        isSyncingHK = true
        await watchSync.requestAuthorizationAndSync()
        await loadData()
        lastHKSyncTimestamp = Date().timeIntervalSince1970
        isSyncingHK = false
        if let err = watchSync.lastError {
            apiError = err
        } else {
            syncSuccess.toggle()
        }
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

            let snapshot = WearableSnapshot(
                date: dateStr,
                steps: entry.steps,
                sleepHours: entry.sleepHours,
                restingHr: newRHR ?? entry.restingHr,
                hrv: newHRV ?? entry.hrv,
                activeEnergy: entry.activeEnergy,
                bodyWeightLbs: nil,
                bodyFatPct: nil,
                hrMorning: entry.hrMorning,
                hrPostWorkout: entry.hrPostWorkout,
                hrEvening: entry.hrEvening,
                workouts: [],
                spo2: nil,
                wristTemp: nil
            )
            do {
                try await APIService.shared.syncWearableData(snapshot)
                updated += 1
            } catch {
                logger.error("backfill failed for \(dateStr): \(error)")
            }
        }

        await loadData()
        await MainActor.run {
            isBackfilling    = false
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
    #endif
}
