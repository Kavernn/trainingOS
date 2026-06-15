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

private enum RecoveryMetricState {
    case value(String)
    case hkNeeded       // HK-sourced, nil → invite à syncer
    case manualNeeded   // Saisie manuelle, nil → invite à logger
}

private struct RecoveryDayCell: View {
    let icon: String
    let label: String
    let color: Color
    let state: RecoveryMetricState
    var infoEntry: InfoEntry? = nil
    var onAction: (() -> Void)? = nil

    @State private var showInfo = false

    var body: some View {
        Button {
            switch state {
            case .value: if infoEntry != nil { showInfo = true }
            case .hkNeeded, .manualNeeded: onAction?()
            }
        } label: {
            VStack(spacing: 7) {
                switch state {
                case .value(let v):
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                    Text(v)
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(.appTextPrimary)
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Text(label)
                        .font(.appMicro.weight(.medium))
                        .foregroundColor(.gray)
                        .lineLimit(2).multilineTextAlignment(.center)

                case .hkNeeded:
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color.opacity(0.28))
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill").font(.appMicro).foregroundColor(Color.appDanger.opacity(0.65))
                        Text("Sync Santé").font(.appCaption.weight(.bold)).foregroundColor(Color.forge.opacity(0.9))
                    }
                    Text(label)
                        .font(.appMicro.weight(.medium))
                        .foregroundColor(.gray.opacity(0.6))
                        .lineLimit(2).multilineTextAlignment(.center)

                case .manualNeeded:
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color.opacity(0.28))
                    HStack(spacing: 3) {
                        Image(systemName: "pencil").font(.appMicro).foregroundColor(Color.statusBlue.opacity(0.75))
                        Text("Saisir").font(.appCaption.weight(.bold)).foregroundColor(Color.statusBlue.opacity(0.85))
                    }
                    Text(label)
                        .font(.appMicro.weight(.medium))
                        .foregroundColor(.gray.opacity(0.6))
                        .lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 4)
            .background(cellBg)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(cellBorder, lineWidth: 1))
        }
        .buttonStyle(SpringButtonStyle())
        .sheet(isPresented: $showInfo) {
            if let e = infoEntry { InfoSheetView(title: label, entries: [e]) }
        }
    }

    private var cellBg: Color {
        switch state {
        case .value:        return Color.appCard
        case .hkNeeded:     return Color.statusOrange.opacity(0.06)
        case .manualNeeded: return Color.statusBlue.opacity(0.06)
        }
    }

    private var cellBorder: Color {
        switch state {
        case .value:        return Color.appSurfaceInset
        case .hkNeeded:     return Color.statusOrange.opacity(0.20)
        case .manualNeeded: return Color.statusBlue.opacity(0.17)
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
        if scoreInt >= 80 { return Color.appSuccess }
        if scoreInt >= 60 { return Color(red: 1.0, green: 0.78, blue: 0.0) }
        if scoreInt >= 40 { return Color.statusOrange }
        return Color.appDanger
    }

    private var gradientTop: Color {
        guard score != nil else { return .gray.opacity(0.12) }
        if scoreInt >= 80 { return Color.appSuccess.opacity(0.28) }
        if scoreInt >= 60 { return Color(red: 1.0, green: 0.78, blue: 0.0).opacity(0.22) }
        if scoreInt >= 40 { return Color.statusOrange.opacity(0.24) }
        return Color.appDanger.opacity(0.24)
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
                        .foregroundColor(.appOnSurface.opacity(0.85))
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
                    .background(Color.appSurfaceInset)
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
                    .font(.appMicro.weight(.bold))
                    .tracking(2)
                    .foregroundColor(.gray.opacity(0.75))
            }
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                heroPill(icon: "waveform.path.ecg",
                         label: "HRV",
                         value: hrv.map { String(format: "%.0f ms", $0) },
                         color: Color.appSuccess)
                heroPill(icon: "moon.zzz.fill",
                         label: "Sommeil",
                         value: sleepHours.map { String(format: "%.1f h", $0) },
                         color: Color.statusBlue)
                heroPill(icon: "heart.fill",
                         label: "FC repos",
                         value: restingHr.map { String(format: "%.0f bpm", $0) },
                         color: Color.appDanger)
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
                .font(.appLabel)
                .foregroundColor(hasValue ? color : .gray.opacity(0.35))
            Text(value ?? "—")
                .font(.appLabel.weight(.bold))
                .foregroundColor(hasValue ? .white : .gray.opacity(0.4))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.appMicro.weight(.semibold))
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

// MARK: - SleepProgressBar

private struct SleepProgressBar: View {
    let ratio: CGFloat
    let color: Color
    @State private var animRatio: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appSurfaceInset).frame(height: 6)
                Capsule().fill(color)
                    .frame(width: geo.size.width * animRatio, height: 6)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) { animRatio = min(ratio, 1.0) }
        }
        .onChange(of: ratio) { _, v in
            withAnimation(.easeOut(duration: 0.6)) { animRatio = min(v, 1.0) }
        }
    }
}

// MARK: - RecoverySleepBarChart

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
                    // Goal line
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: goalY))
                        p.addLine(to: CGPoint(x: w, y: goalY))
                    }
                    .stroke(Color.appSuccess.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Bars + quality dots
                    ForEach(Array(entries.enumerated()), id: \.1.id) { i, entry in
                        let x = CGFloat(i) * (w / CGFloat(entries.count)) + 2
                        let bh = entry.sleepHours.map { CGFloat($0 / yMax) * h } ?? 0
                        let color = barColor(entry.sleepHours ?? 0)

                        // Bar
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.75))
                            .frame(width: barW, height: bh)
                            .position(x: x + barW / 2, y: h - bh / 2)

                        // Quality dot
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

            // X-axis labels
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

// MARK: - AccordionRow

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
                        .foregroundColor(.appOnSurface.opacity(0.9))
                    if let src = entry.source {
                        Text(src == "manual" ? "Manuel" : "Apple Santé")
                            .font(.appMicro)
                            .foregroundColor(.gray.opacity(0.55))
                    }
                }
                Spacer()
                // Key metrics inline
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
                .foregroundColor(value != nil ? .appOnSurface.opacity(0.85) : .gray.opacity(0.35))
        }
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
    @AppStorage("sleep_goal_hours") private var sleepGoalHours: Double = 8.0
    @State private var showHistoryAccordion = false
    @State private var hkSpO2: Double? = nil
    @State private var hkWristTemp: Double? = nil
    @ObservedObject private var theme = AppTheme.shared

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
                AmbientBackground(color: Color.forge)
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
                LogRecoverySheet(onSaved: {
                    await loadData()
                    await MainActor.run { toast = ToastMessage(message: "Récupération enregistrée", style: .success) }
                })
            }
            .sheet(item: $editTarget) { entry in
                LogRecoverySheet(prefillEntry: entry, onSaved: {
                    await loadData()
                    await MainActor.run { toast = ToastMessage(message: "Récupération mise à jour", style: .success) }
                })
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
            .background(activeTab == tab ? Color.forge : Color.clear)
            .foregroundColor(activeTab == tab ? Color.onAccent : .gray)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today Tab

    private var todayScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                RecoveryHeroCard(
                    score: readinessData.map { Double($0.score) / 100.0 },
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

                deltaFCCard
                    .padding(.horizontal, 16)
                    .appearAnimation(delay: 0.08)

                miniHRVSparkline
                    .padding(.horizontal, 16)
                    .appearAnimation(delay: 0.10)

                sleepSection
                    .padding(.horizontal, 16)
                    .appearAnimation(delay: 0.12)

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
                    .foregroundColor(Color.forge)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassCard()
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.08)

                historyAccordion
                    .padding(.horizontal, 16)
                    .appearAnimation(delay: 0.14)

                Spacer(minLength: 32)
            }
            .padding(.vertical, 16)
            .padding(.bottom, fabBottomPadding + 72)
        }
        .refreshable {
            await loadData()
        }
    }

    private var metricGrid: some View {
        let entry = todayEntry
        let stepsVal: String? = entry?.steps.map {
            NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal)
        }
        let manualAction: () -> Void = {
            if let e = entry { editTarget = e } else { showSheet = true }
        }
        let hkvColor = hrvAnalysis?.zoneColor ?? Color.appSuccess

        func hk(_ v: String?) -> RecoveryMetricState { v.map { .value($0) } ?? .hkNeeded }
        func man(_ v: String?) -> RecoveryMetricState { v.map { .value($0) } ?? .manualNeeded }

        return VStack(alignment: .leading, spacing: 10) {
            Text("MÉTRIQUES DU JOUR")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                RecoveryDayCell(icon: "moon.zzz.fill", label: "Sommeil", color: Color.statusBlue,
                                state: hk(entry?.sleepHours.map { String(format: "%.1fh", $0) }),
                                infoEntry: .sleepDurationMetric,
                                onAction: { Task { await syncHealthKitNow() } })
                RecoveryDayCell(icon: "heart.fill", label: "FC repos", color: Color.appDanger,
                                state: hk(entry?.restingHr.map { String(format: "%.0f bpm", $0) }),
                                infoEntry: .restingHrMetric,
                                onAction: { Task { await syncHealthKitNow() } })
                RecoveryDayCell(icon: "waveform.path.ecg", label: "HRV", color: hkvColor,
                                state: hk(entry?.hrv.map { String(format: "%.0f ms", $0) }),
                                infoEntry: .hrvMetric,
                                onAction: { Task { await syncHealthKitNow() } })
                RecoveryDayCell(icon: "figure.walk", label: "Pas", color: Color.statusCyan,
                                state: hk(stepsVal),
                                infoEntry: .stepsMetric,
                                onAction: { Task { await syncHealthKitNow() } })
                RecoveryDayCell(icon: "flame.fill", label: "Énergie active", color: Color.statusOrange,
                                state: hk(entry?.activeEnergy.map { String(format: "%.0f kcal", $0) }),
                                infoEntry: .activeEnergyMetric,
                                onAction: { Task { await syncHealthKitNow() } })
                RecoveryDayCell(icon: "star.fill", label: "Qualité sommeil", color: Color.statusPurple,
                                state: man(entry?.sleepQuality.map { String(format: "%.1f/10", $0) }),
                                infoEntry: .sleepQualityMetric, onAction: manualAction)
                RecoveryDayCell(icon: "bolt.fill", label: "Courbatures", color: Color.statusYellow,
                                state: man(entry?.soreness.map { String(format: "%.1f/10", $0) }),
                                infoEntry: .sorenessMetric, onAction: manualAction)
                RecoveryDayCell(icon: "battery.25percent", label: "Fatigue", color: Color.appDanger,
                                state: man(entry?.fatigue.map { String(format: "%.1f/10", $0) }),
                                infoEntry: .fatigueMetric, onAction: manualAction)
                RecoveryDayCell(icon: "bolt.circle.fill", label: "Énergie pré", color: .mint,
                                state: man(entry?.energyPre.map { String(format: "%.1f/10", $0) }),
                                infoEntry: .energyPreMetric, onAction: manualAction)
            }

            if entry?.hrMorning != nil || entry?.hrPostWorkout != nil || entry?.hrEvening != nil
                || hkSpO2 != nil || hkWristTemp != nil {
                let postColor = Color(red: 1, green: 0.42, blue: 0.12)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    RecoveryDayCell(icon: "sunrise.fill", label: "FC matin", color: Color.statusCyan,
                                    state: hk(entry?.hrMorning.map { String(format: "%.0f", $0) }),
                                    infoEntry: .hrMorningMetric,
                                    onAction: { Task { await syncHealthKitNow() } })
                    RecoveryDayCell(icon: "dumbbell.fill", label: "FC post séance", color: postColor,
                                    state: hk(entry?.hrPostWorkout.map { String(format: "%.0f", $0) }),
                                    infoEntry: .hrPostWorkoutMetric,
                                    onAction: { Task { await syncHealthKitNow() } })
                    RecoveryDayCell(icon: "moon.fill", label: "FC soir", color: .indigo,
                                    state: hk(entry?.hrEvening.map { String(format: "%.0f", $0) }),
                                    infoEntry: .hrEveningMetric,
                                    onAction: { Task { await syncHealthKitNow() } })
                    RecoveryDayCell(icon: "lungs.fill", label: "SpO2", color: Color.statusBlue,
                                    state: hk(hkSpO2.map { String(format: "%.0f%%", $0) }),
                                    infoEntry: .spo2Metric,
                                    onAction: { Task { await syncHealthKitNow() } })
                    RecoveryDayCell(icon: "thermometer.medium", label: "Temp.", color: .mint,
                                    state: hk(hkWristTemp.map { String(format: "%@%.1f°", $0 >= 0 ? "+" : "", $0) }),
                                    infoEntry: .wristTempMetric,
                                    onAction: { Task { await syncHealthKitNow() } })
                }
            }
        }
    }

    // MARK: - Sleep section

    private var sleepSection: some View {
        let entry = todayEntry
        let hours = entry?.sleepHours
        let quality = entry?.sleepQuality
        let bedtime = entry?.bedtime
        let wakeTime = entry?.wakeTime
        let goal = sleepGoalHours
        let sleepPts = Array(log.prefix(10).reversed()).filter { $0.sleepHours != nil }

        return VStack(alignment: .leading, spacing: 10) {
            // ── Hero ──────────────────────────────────────
            if let h = hours {
                let ratio = min(h / goal, 1.0)
                let dColor: Color = h < 5 ? Color.appDanger : (h < goal * 0.85 ? Color.statusOrange : Color.appSuccess)

                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Image(systemName: "moon.zzz.fill").font(.appMicro).foregroundColor(Color.statusBlue)
                                Text("SOMMEIL").font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(String(format: "%.1f", h))
                                    .font(.system(size: 36, weight: .black, design: .rounded))
                                    .foregroundColor(dColor)
                                Text("h")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(dColor.opacity(0.7))
                                    .padding(.bottom, 2)
                            }
                            if let bt = bedtime, let wt = wakeTime {
                                Text("\(bt) → \(wt)")
                                    .font(.appCaption)
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "%.1fh obj.", goal))
                                .font(.appMicro.weight(.semibold))
                                .foregroundColor(.gray)
                            Text(String(format: "%.0f%%", ratio * 100))
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(dColor)
                            if let q = quality {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill").font(.appMicro).foregroundColor(Color.statusYellow)
                                    Text(String(format: "%.1f/10", q))
                                        .font(.appCaption.weight(.semibold)).foregroundColor(.appOnSurface.opacity(0.8))
                                }
                            }
                        }
                    }
                    .padding(14)

                    // Progress bar
                    SleepProgressBar(ratio: ratio, color: dColor)
                        .frame(height: 6)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                }
                .background(Color.appCard)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(dColor.opacity(0.20), lineWidth: 1))
            }

            // ── 10-day bar chart ──────────────────────────
            if sleepPts.count >= 3 {
                RecoverySleepBarChart(entries: sleepPts, goalHours: goal)
            }
        }
    }

    // MARK: - Delta FC card

    private var deltaFCCard: some View {
        Group {
            if let hrM = todayEntry?.hrMorning, let rhr = todayEntry?.restingHr {
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

    // MARK: - Mini HRV sparkline

    private var miniHRVSparkline: some View {
        let pts = Array(log.prefix(14).reversed()).compactMap { $0.hrv }
        let baseline = hrvAnalysis?.hrv7dAvg
        return Group {
            if pts.count >= 3 {
                let mn = (pts.min() ?? 0) - 5
                let mx = (pts.max() ?? 60) + 5
                let rng = max(mx - mn, 1)
                let avg = pts.reduce(0, +) / Double(pts.count)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "waveform.path.ecg").font(.appMicro).foregroundColor(Color.appSuccess)
                        Text("HRV — \(pts.count) JOURS").font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.0f ms moy.", avg))
                            .font(.appCaption.weight(.semibold)).foregroundColor(Color.appSuccess)
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let step = pts.count > 1 ? w / CGFloat(pts.count - 1) : w
                        ZStack {
                            // baseline
                            if let bl = baseline {
                                let by = h - CGFloat((bl - mn) / rng) * h
                                Path { p in
                                    p.move(to: CGPoint(x: 0, y: by))
                                    p.addLine(to: CGPoint(x: w, y: by))
                                }
                                .stroke(Color.appSuccess.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            }
                            // area fill
                            Path { p in
                                let first = h - CGFloat((pts[0] - mn) / rng) * h
                                p.move(to: CGPoint(x: 0, y: h))
                                p.addLine(to: CGPoint(x: 0, y: first))
                                for i in 1..<pts.count {
                                    let x = CGFloat(i) * step
                                    let y = h - CGFloat((pts[i] - mn) / rng) * h
                                    p.addLine(to: CGPoint(x: x, y: y))
                                }
                                p.addLine(to: CGPoint(x: CGFloat(pts.count - 1) * step, y: h))
                                p.closeSubpath()
                            }
                            .fill(
                                LinearGradient(colors: [Color.appSuccess.opacity(0.18), Color.appSuccess.opacity(0)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            // line
                            Path { p in
                                let first = h - CGFloat((pts[0] - mn) / rng) * h
                                p.move(to: CGPoint(x: 0, y: first))
                                for i in 1..<pts.count {
                                    let x = CGFloat(i) * step
                                    let y = h - CGFloat((pts[i] - mn) / rng) * h
                                    p.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                            .stroke(Color.appSuccess.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            // last dot
                            if let last = pts.last {
                                let lx = CGFloat(pts.count - 1) * step
                                let ly = h - CGFloat((last - mn) / rng) * h
                                Circle().fill(Color.appSuccess).frame(width: 7, height: 7)
                                    .position(x: lx, y: ly)
                            }
                        }
                    }
                    .frame(height: 52)
                }
                .padding(14)
                .glassCard()
            }
        }
    }

    // MARK: - History Accordion (today tab)

    private var historyAccordion: some View {
        let recent = Array(log.prefix(10))
        return Group {
            if !recent.isEmpty {
                VStack(spacing: 0) {
                    // Header / toggle
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showHistoryAccordion.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(.gray)
                            Text("HISTORIQUE RÉCENT")
                                .font(.appMicro.weight(.bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(recent.count) entrées")
                                .font(.appMicro)
                                .foregroundColor(.gray.opacity(0.6))
                            Image(systemName: showHistoryAccordion ? "chevron.up" : "chevron.down")
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.appCard)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    if showHistoryAccordion {
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.1.id) { i, entry in
                                AccordionRow(entry: entry, onEdit: { editTarget = entry })
                                if i < recent.count - 1 {
                                    Divider()
                                        .background(Color.appSurfaceInset)
                                        .padding(.horizontal, 14)
                                }
                            }
                        }
                        .background(Color.appCard.opacity(0.6))
                        .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appSurfaceInset, lineWidth: 1))
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
                            .font(.appLabel).foregroundColor(Color.appDanger)
                        Text("\(entriesMissingHK.count) entrée\(entriesMissingHK.count > 1 ? "s" : "") sans FC/HRV")
                            .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                            .lineLimit(1)
                        Spacer()
                        Button { Task { await backfillFromHealthKit() } } label: {
                            if isBackfilling {
                                ProgressView().tint(Color.appDanger).scaleEffect(0.65)
                            } else {
                                Text("Sync")
                                    .font(.appCaption.weight(.semibold)).foregroundColor(Color.appDanger)
                            }
                        }
                        .disabled(isBackfilling)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.appDanger.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appDanger.opacity(0.14), lineWidth: 1))
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
                            label: "Sommeil moy.", color: Color.statusBlue,
                            subtitle: countSleep > 0 ? "sur \(countSleep) logs" : nil)
                    KPICard(value: avgSleepQuality > 0 ? String(format: "%.1f/10", avgSleepQuality) : "—",
                            label: "Qualité moy.", color: Color.statusPurple,
                            subtitle: countSleepQuality > 0 ? "sur \(countSleepQuality) logs" : nil)
                    KPICard(value: avgRestHR > 0 ? String(format: "%.0f bpm", avgRestHR) : "—",
                            label: "FC repos moy.", color: Color.appDanger,
                            subtitle: countRestHR > 0 ? "sur \(countRestHR) logs" : nil)
                    KPICard(value: avgSteps > 0 ? String(format: "%.0f", avgSteps) : "—",
                            label: "Pas moy./jour", color: Color.appSuccess,
                            subtitle: countSteps > 0 ? "sur \(countSteps) logs" : nil)
                    KPICard(value: avgActiveEnergy > 0 ? String(format: "%.0f kcal", avgActiveEnergy) : "—",
                            label: "Énergie active", color: Color.statusOrange,
                            subtitle: countActiveEnergy > 0 ? "sur \(countActiveEnergy) logs" : nil)
                    KPICard(
                        value: avgHRV > 0 ? String(format: "%.0f ms", avgHRV) : "—",
                        label: "HRV moy.",
                        color: hrvAnalysis?.zoneColor ?? Color.appSuccess,
                        subtitle: countHRV > 0 ? "sur \(countHRV) logs" : nil
                    )
                }
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.02)

                if avgFatigue > 0 {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        KPICard(value: String(format: "%.1f/10", avgFatigue),
                                label: "Fatigue moy.", color: avgFatigue >= 7 ? Color.appDanger : (avgFatigue >= 4 ? Color.statusOrange : Color.appSuccess))
                    }
                    .padding(.horizontal, 16)
                    .appearAnimation(delay: 0.025)
                }

                if avgHRMorning > 0 || avgHRPostWorkout > 0 || avgHREvening > 0 {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        KPICard(value: avgHRMorning > 0 ? String(format: "%.0f bpm", avgHRMorning) : "—",
                                label: "FC matin moy.", color: Color.statusCyan)
                        KPICard(value: avgHRPostWorkout > 0 ? String(format: "%.0f bpm", avgHRPostWorkout) : "—",
                                label: "FC post séance", color: Color.statusOrange)
                        KPICard(value: avgHREvening > 0 ? String(format: "%.0f bpm", avgHREvening) : "—",
                                label: "FC soir moy.", color: Color.statusBlue)
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
                            accentColor: Color.appWarning
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
                             zoneColor: hrvAnalysis?.zoneColor ?? Color.appSuccess)
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
                                    .fill(Color.appSurfaceInset)
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                }

                Spacer(minLength: 32)
            }
            .padding(.vertical, 16)
            .padding(.bottom, fabBottomPadding + 72)
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

    #if targetEnvironment(macCatalyst)
    private func syncHealthKitNow() async {}
    #else
    private func syncHealthKitNow() async {
        isSyncingHK = true
        let prevSync = watchSync.lastSyncCompleted
        await watchSync.requestAuthorizationAndSync()
        await loadData()
        lastHKSyncTimestamp = Date().timeIntervalSince1970
        isSyncingHK = false
        if let err = watchSync.lastError {
            apiError = err
        } else if watchSync.lastSyncCompleted != prevSync {
            syncSuccess.toggle()
        }
        // if lastSyncCompleted unchanged, sync was blocked by isSyncing guard — no haptic
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
                wristTemp: nil,
                bedtime: nil,
                wakeTime: nil
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
