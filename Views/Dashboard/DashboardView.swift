
import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject private var api = APIService.shared
    @ObservedObject private var alertService = AlertService.shared
    @State private var insights: [InsightEntry] = []
    @State private var deload: DeloadReport?
    @State private var moodDue: MoodDueStatus?
    @State private var brief: MorningBriefData?
    @State private var soirData: SeanceSoirData?
    @State private var showMoodSheet = false
    @State private var lastRefresh: Date = .distantPast
    @State private var sleepPromptDismissedThisSession = false
    @State private var todaySleepLogged = false
    @State private var todayRecovery: RecoveryEntry?
    @State private var lssTrend: [LifeStressScore] = []
    @State private var peakPrediction: PeakPredictionResponse? = nil
    @Environment(\.scenePhase) private var scenePhase

    private var todayStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private var shouldShowSleepPrompt: Bool {
        // todaySleepLogged = vérité serveur (fonctionne cross-appareils)
        // UserDefaults = cache local pour éviter un flash après dismissal
        // sleepPromptDismissedThisSession = disparition animée dans la session courante
        !sleepPromptDismissedThisSession &&
        !todaySleepLogged &&
        UserDefaults.standard.string(forKey: "sleepPromptDate") != todayStr
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: todayAccentColor)
                if api.isLoading && api.dashboard == nil {
                    DashboardSkeletonView()
                } else if let dash = api.dashboard {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            if let alert = alertService.visibleAlert {
                                ProactiveBannerCard(alert: alert) {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        alertService.dismiss(alert)
                                    }
                                }
                                .appearAnimation(delay: 0)
                            }

                            GreetingHeaderView(dash: dash)
                                .appearAnimation(delay: 0)

                            // Fix #1: TodayCard at top — primary action every session
                            TodayCardView(
                                dash: dash,
                                showGreatDayBadge: brief?.recommendation == "go" && (deload?.fatigueLevel ?? 0) == 0 && dash.sessions[todayStr] != nil
                            )
                            .appearAnimation(delay: 0.01)

                            if let soir = soirData, soir.hasEveningSession {
                                SoirCardView(data: soir)
                                    .appearAnimation(delay: 0.02)
                            }

                            // Fix #3: tappable recovery strip; Fix #15: indigo accent
                            if let rec = todayRecovery,
                               rec.sleepHours != nil || rec.restingHr != nil || rec.hrv != nil || rec.steps != nil {
                                NavigationLink(destination: RecoveryView()) {
                                    RecoverySnapshotView(recovery: rec)
                                }
                                .buttonStyle(.plain)
                                .appearAnimation(delay: 0.03)
                            }

                            // Fix #2: remove inline re-show button; keep SleepPromptCard only
                            if shouldShowSleepPrompt {
                                SleepPromptCard(onDone: {
                                    UserDefaults.standard.set(todayStr, forKey: "sleepPromptDate")
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        sleepPromptDismissedThisSession = true
                                    }
                                })
                                .appearAnimation(delay: 0.04)
                            }

                            ChecklistCardView()
                                .appearAnimation(delay: 0.05)

                            // Fix #7: full banner only for level 2; compact chip for level 1
                            if let report = deload, report.fatigueLevel > 0 {
                                if report.fatigueLevel == 2 {
                                    DeloadBannerView(report: report) {
                                        Task { await applyDeload(report: report) }
                                    }
                                    .appearAnimation(delay: 0.06)
                                } else {
                                    DeloadChipView(report: report)
                                        .appearAnimation(delay: 0.06)
                                }
                            }

                            if let b = brief,
                               b.recommendation != "go" ||
                               b.flags.hrvDrop || b.flags.sleepDeprivation || b.flags.trainingOverload {
                                MorningBriefCardView(
                                    data: b,
                                    lssTrend: lssTrend,
                                    lastSessionDate: api.dashboard?.sessions.keys.max()
                                )
                                .appearAnimation(delay: 0.07)
                            }

                            if let peak = peakPrediction, !peak.days.isEmpty {
                                PeakPredictionCard(prediction: peak)
                                    .appearAnimation(delay: 0.08)
                            }

                            // Fix #8: mood button redesigned as proper card
                            if moodDue?.isDue == true {
                                MoodCardView { showMoodSheet = true }
                                    .appearAnimation(delay: 0.09)
                            }

                            if !insights.isEmpty {
                                DashboardInsightsCard(insights: insights)
                                    .appearAnimation(delay: 0.10)
                            }

                            // Fix #3: tappable stats row
                            NavigationLink(destination: StatsView()) {
                                StatsRowView(dash: dash)
                            }
                            .buttonStyle(.plain)
                            .appearAnimation(delay: 0.11)

                            WeekGridView(schedule: dash.schedule, sessions: dash.sessions)
                                .appearAnimation(delay: 0.13)

                            // Fix #3: tappable nutrition summary; Fix #9: HeatmapView removed (redundant)
                            NavigationLink(destination: NutritionView()) {
                                NutritionSummaryView(totals: dash.nutritionTotals, settings: dash.nutritionSettings)
                            }
                            .buttonStyle(.plain)
                            .appearAnimation(delay: 0.15)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, contentBottomPadding)
                    }
                    .refreshable {
                        await api.fetchDashboard()
                        async let d  = APIService.shared.fetchDeloadData()
                        async let m  = APIService.shared.checkMoodDue()
                        async let b  = APIService.shared.fetchMorningBrief()
                        async let s  = APIService.shared.fetchSeanceSoirData()
                        deload   = try? await d
                        moodDue  = try? await m
                        brief    = try? await b
                        soirData = try? await s
                    }
                } else if let err = api.error {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 48)).foregroundColor(.gray)
                        Text("Connexion impossible").foregroundColor(.white).fontWeight(.semibold)
                        Text(err).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                        Button {
                            Task { await api.fetchDashboard() }
                        } label: {
                            Text("Réessayer")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 28).padding(.vertical, 12)
                                .background(Color.orange).cornerRadius(22)
                        }
                        .buttonStyle(SpringButtonStyle())
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await api.fetchDashboard()
            async let d = APIService.shared.fetchDeloadData()
            async let m = APIService.shared.checkMoodDue()
            async let b = APIService.shared.fetchMorningBrief()
            async let s = APIService.shared.fetchSeanceSoirData()
            async let i = APIService.shared.fetchInsights()
            async let r = APIService.shared.fetchRecoveryData()
            async let t = APIService.shared.fetchLifeStressTrend(days: 7)
            async let p = APIService.shared.fetchPeakPrediction()
            deload         = try? await d
            moodDue        = try? await m
            brief          = try? await b
            soirData       = try? await s
            insights       = (try? await i) ?? []
            lssTrend       = (try? await t) ?? []
            peakPrediction = try? await p
            if let log = try? await r {
                let entry = log.first(where: { $0.date == todayStr })
                todaySleepLogged = entry?.sleepHours != nil
                todayRecovery = entry
            }
            await alertService.fetch()
            lastRefresh = Date()
        }
        .onChange(of: scenePhase) {
            // Ne refetch que si la dernière mise à jour date de plus de 5 min et qu'aucun fetch n'est en cours
            if scenePhase == .active,
               !api.isLoading,
               Date().timeIntervalSince(lastRefresh) > 300 {
                Task {
                    await api.fetchDashboard()
                    async let d = APIService.shared.fetchDeloadData()
                    async let m = APIService.shared.checkMoodDue()
                    async let b = APIService.shared.fetchMorningBrief()
                    async let s = APIService.shared.fetchSeanceSoirData()
                    async let r = APIService.shared.fetchRecoveryData()
                    async let t = APIService.shared.fetchLifeStressTrend(days: 7)
                    async let p = APIService.shared.fetchPeakPrediction()
                    deload         = try? await d
                    moodDue        = try? await m
                    brief          = try? await b
                    soirData       = try? await s
                    lssTrend       = (try? await t) ?? []
                    peakPrediction = try? await p
                    if let log = try? await r {
                        let entry = log.first(where: { $0.date == todayStr })
                        todaySleepLogged = entry?.sleepHours != nil
                        todayRecovery = entry
                    }
                    await alertService.fetch()
                    lastRefresh = Date()
                }
            }
        }
        .sheet(isPresented: $showMoodSheet, onDismiss: {
            Task { moodDue = try? await APIService.shared.checkMoodDue() }
        }) {
            MoodLogSheet()
        }
    }

    var todayAccentColor: Color {
        switch api.dashboard?.today {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .blue
        }
    }

    private func applyDeload(report: DeloadReport) async {
        let url = URL(string: "https://training-os-rho.vercel.app/api/apply_deload")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["poids_deload": report.poidsDeload]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
        CacheService.shared.clear(for: "seance_data")
        CacheService.shared.clear(for: "dashboard")
        await api.fetchDashboard()
        deload = nil   // Masquer la bannière après application
    }
}

// MARK: - Dashboard Skeleton (fix #5)
struct DashboardSkeletonView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBar(width: 80, height: 10)
                        SkeletonBar(width: 200, height: 26)
                        SkeletonBar(width: 140, height: 12)
                    }
                    Spacer()
                    SkeletonBar(width: 36, height: 36, radius: 18)
                }
                .padding(.top, 12)

                // TodayCard
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        SkeletonBar(width: 36, height: 36, radius: 18)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBar(width: 70, height: 9)
                            SkeletonBar(width: 130, height: 16)
                        }
                        Spacer()
                    }
                    SkeletonBar(height: 48, radius: 12)
                }
                .padding(16)
                .background(Color.white.opacity(0.04))
                .cornerRadius(16)

                // Recovery strip
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: 6) {
                            SkeletonBar(width: 16, height: 16, radius: 8)
                            SkeletonBar(width: 32, height: 14)
                            SkeletonBar(width: 28, height: 9)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(16)

                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonBar(height: 60, radius: 12) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var radius: CGFloat = 6
    @State private var opacity: Double = 0.04

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    opacity = 0.13
                }
            }
    }
}

// MARK: - Deload Compact Chip (fix #7 — level 1 only)
struct DeloadChipView: View {
    let report: DeloadReport

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            Text("Fatigue accumulée détectée — score \(report.fatigueScore)/100")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text("Niv. \(report.fatigueLevel)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)
            CardInfoButton(title: "Fatigue & déload", entries: InfoEntry.deloadEntries)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - Mood Card (fix #8 — proper card instead of raw button)
struct MoodCardView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.yellow.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: "face.smiling.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.yellow)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("HUMEUR DU JOUR")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    Text("Comment tu te sens aujourd'hui ?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(14)
            .glassCard(color: .yellow, intensity: 0.05)
            .cornerRadius(16)
        }
        .buttonStyle(SpringButtonStyle())
    }
}

// MARK: - Sleep Prompt Card

struct SleepPromptCard: View {
    let onDone: () -> Void

    @State private var bedtime  = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var wakeTime = Calendar.current.date(bySettingHour: 7,  minute: 0, second: 0, of: Date()) ?? Date()
    @State private var isSaving = false
    @State private var hkImported = false

    private var durationHours: Double {
        let d = wakeTime.timeIntervalSince(bedtime) / 3600
        return d < 0 ? d + 24 : d
    }

    private var durationColor: Color {
        if durationHours < 6  { return .red }
        if durationHours < 7  { return .yellow }
        if durationHours <= 9 { return .green }
        return .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.indigo)
                Text("Ton sommeil cette nuit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    onDone() // dismiss without saving
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(6)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if hkImported {
                Label("Horaires détectés depuis Santé", systemImage: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.8))
            }

            // Pickers
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COUCHÉ")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("LEVÉ")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                }
                Spacer()
                // Duration badge
                VStack(spacing: 2) {
                    Text(String(format: "%.1fh", durationHours))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(durationColor)
                    Text("durée")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }

            // Save button
            Button {
                Task { await save() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Text("Enregistrer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.indigo)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isSaving || durationHours <= 0 || durationHours > 16)

            // Fix #16: explain why save is disabled
            if durationHours <= 0 || durationHours > 16 {
                Text("Durée invalide — ajuste l'heure de coucher ou de réveil")
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.indigo.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.indigo.opacity(0.25), lineWidth: 1))
        )
        .task { await tryHealthKitImport() }
    }

    private func tryHealthKitImport() async {
        guard let window = await HealthKitService.shared.fetchLastNightSleepWindow() else { return }
        await MainActor.run {
            bedtime    = window.bedtime
            wakeTime   = window.wakeTime
            hkImported = true
        }
    }

    private func save() async {
        isSaving = true
        try? await APIService.shared.logRecovery(
            sleepHours:   durationHours,
            sleepQuality: nil,
            restingHr:    nil,
            hrv:          nil,
            steps:        nil,
            soreness:     nil,
            notes:        ""
        )
        await MainActor.run {
            isSaving = false
            onDone()
        }
    }
}

// MARK: - Deload Banner
struct DeloadBannerView: View {
    let report: DeloadReport
    var onApplyDeload: (() -> Void)? = nil
    @ObservedObject private var units = UnitSettings.shared
    @State private var isApplying = false

    private var accentColor: Color {
        report.fatigueLevel == 2 ? .yellow : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: report.fatigueLevel == 2 ? "arrow.down.circle.fill" : "flame.fill")
                    .font(.system(size: 18))
                    .foregroundColor(accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(report.fatigueLevel == 2 ? "Semaine de déload recommandée" : "Fatigue accumulée détectée")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    if let rpe = report.rpeAvg7j {
                        Text("RPE moyen 7 jours : \(String(format: "%.1f", rpe))/10")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                Spacer()
                CardInfoButton(title: "Fatigue & déload", entries: InfoEntry.deloadEntries)
            }

            // Fatigue score gauge
            FatigueScoreGauge(score: report.fatigueScore)

            // Details
            if report.fatigueRpe {
                Label("RPE élevé ces dernières séances", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }

            if report.streakDays >= 7 {
                Label("\(report.streakDays) jours consécutifs sans repos", systemImage: "calendar.badge.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundColor(.orange.opacity(0.85))
            }

            if !report.stagnants.isEmpty {
                Text("Stagnation : \(report.stagnants.joined(separator: ", "))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }

            if report.fatigueLevel == 2, !report.poidsDeload.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Charges suggérées (−15 %)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(report.poidsDeload.sorted(by: { $0.key < $1.key }), id: \.key) { ex, w in
                            HStack {
                                Text(ex).lineLimit(1).font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text(units.format(w)).font(.system(size: 11, weight: .semibold)).foregroundColor(.yellow)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                    if let onApplyDeload {
                        Button {
                            isApplying = true
                            onApplyDeload()
                        } label: {
                            HStack(spacing: 6) {
                                if isApplying {
                                    ProgressView().tint(.black).scaleEffect(0.75)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                }
                                Text("Appliquer le déload (−15 %)")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.yellow)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(isApplying)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(accentColor.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(accentColor.opacity(0.3), lineWidth: 1))
        )
    }
}

// MARK: - Fatigue Score Gauge
struct FatigueScoreGauge: View {
    let score: Int

    private var gaugeColor: Color {
        if score >= 75 { return .red }
        if score >= 65 { return .orange }
        return .green
    }

    private var label: String {
        if score >= 75 { return "Critique" }
        if score >= 65 { return "Attention" }
        return "Modéré"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Score de fatigue")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("\(score)/100 — \(label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(gaugeColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                    Capsule()
                        .fill(gaugeColor)
                        .frame(width: geo.size.width * CGFloat(score) / 100, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Greeting Header
struct GreetingHeaderView: View {
    let dash: DashboardData

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Bon matin" }
        if hour < 18 { return "Bon après-midi" }
        return "Bonsoir"
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: Date()).capitalized
    }

    var streak: Int {
        // N'utilise PAS Calendar.startOfDay ni addingTimeInterval :
        // sur iOS 26 ces appels routent via Calendar.date(byAdding:wrappingComponents:true)
        // qui recurse infiniment dans _CalendarGregorian.dateComponents → crash 0x8BADF00D.
        let fmt = DateFormatter.isoDate
        let todayStr = fmt.string(from: Date())                     // dateComponents, pas date(byAdding:)
        guard let todayMidnight = fmt.date(from: todayStr) else { return 0 }  // parse → Date, pas date(byAdding:)
        let base = todayMidnight.timeIntervalSince1970              // secondes epoch
        var count = 0
        for i in 0..<365 {
            let checkDate = Date(timeIntervalSince1970: base - Double(i) * 86400.0) // arithmétique pure
            let key = fmt.string(from: checkDate)
            if dash.sessions[key] != nil {
                count += 1
            } else if i == 0 {
                continue // aujourd'hui pas encore loggé, on vérifie hier
            } else {
                break
            }
        }
        return count
    }

    var todayColor: Color {
        switch dash.today {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .blue
        }
    }

    var todayIcon: String {
        switch dash.today {
        case "Push A", "Push B", "Pull A", "Pull B + Full Body", "Legs": return "dumbbell.fill"
        case "Yoga / Tai Chi": return "figure.mind.and.body"
        case "Recovery":       return "heart.fill"
        default:               return "moon.fill"
        }
    }

    var weekSessions: Int {
        let fmt = DateFormatter.isoDate
        let todayStr = fmt.string(from: Date())
        guard let todayMidnight = fmt.date(from: todayStr) else { return 0 }
        let base = todayMidnight.timeIntervalSince1970
        let weekday = Calendar.current.component(.weekday, from: Date())
        let daysSinceMonday = (weekday + 5) % 7
        var count = 0
        for i in 0...daysSinceMonday {
            let d = Date(timeIntervalSince1970: base - Double(i) * 86400.0)
            if dash.sessions[fmt.string(from: d)] != nil { count += 1 }
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("VINCE")
                            .font(.system(size: 11, weight: .black))
                            .tracking(4)
                            .foregroundColor(.gray.opacity(0.7))
                        +
                        Text("SEVEN")
                            .font(.system(size: 11, weight: .black))
                            .tracking(4)
                            .foregroundColor(.orange)
                    }
                    Text(greeting + (dash.profile.name.map { ", \($0.components(separatedBy: " ").first ?? $0)" } ?? "") + " 👋")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text(formattedDate)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("S\(dash.week)")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())

                    if streak > 1 {
                        StreakBadge(count: streak)
                    }
                }
            }

            // Workout badge + week progress
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: todayIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(todayColor)
                    Text(dash.today)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(todayColor)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(todayColor.opacity(0.12))
                .overlay(Capsule().stroke(todayColor.opacity(0.25), lineWidth: 1))
                .clipShape(Capsule())

                Spacer()

                if weekSessions > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.7))
                        Text("\(weekSessions) séance\(weekSessions != 1 ? "s" : "") cette sem.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Today Card
struct TodayCardView: View {
    let dash: DashboardData
    var showGreatDayBadge: Bool = false

    /// Source de vérité : alreadyLoggedToday OU session présente dans le dict.
    /// Double-check côté client pour absorber les désync API/cache.
    private var isLoggedToday: Bool {
        dash.alreadyLoggedToday || dash.sessions[dash.todayDate] != nil
    }

    private var todaySession: SessionEntry? {
        dash.sessions[dash.todayDate]
    }

    var todayColor: Color {
        switch dash.today {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .gray
        }
    }

    var todayIcon: String {
        switch dash.today {
        case "Push A", "Push B", "Pull A", "Pull B + Full Body", "Legs": return "dumbbell.fill"
        case "Yoga / Tai Chi":               return "figure.mind.and.body"
        case "Recovery":                     return "heart.fill"
        default:                             return "moon.fill"
        }
    }

    var exercises: [(String, String)] {
        guard let program = dash.fullProgram[dash.today] else { return [] }
        // On convertit la valeur en String ici pour respecter la promesse [(String, String)]
        return program.map { ($0.key, $0.value.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(todayColor.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: isLoggedToday ? "checkmark" : todayIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isLoggedToday ? .green : todayColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("AUJOURD'HUI")
                        .font(.system(size: 9, weight: .bold)).tracking(2).foregroundColor(.gray)
                    Text(dash.today)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isLoggedToday ? .green : todayColor)
                }
                Spacer()
                if isLoggedToday {
                    HStack(spacing: 5) {
                        if showGreatDayBadge {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                                Text("Parfait")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                        } else {
                            PulsingDot(color: .green)
                            Text("Complété")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
                        }
                    }
                } else if !exercises.isEmpty {
                    Text("\(exercises.count) exos")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)

            if isLoggedToday {
                // ── Récap séance loggée ───────────────────────────────────
                // isLoggedToday peut être vrai via alreadyLoggedToday même sans session dans le dict
                if let session = todaySession {
                    TodaySessionRecap(session: session, color: todayColor)
                }
                NavigationLink(destination: BonusSeanceView()) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Faire une séance bonus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.12))
                    .foregroundColor(.gray)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            } else {
                // ── Programme prévu (pas encore loggé) ───────────────────
                if !exercises.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(exercises.prefix(5).enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 10) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(todayColor.opacity(0.5))
                                    .frame(width: 16)
                                Text(item.0)
                                    .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                                Spacer()
                                Text(item.1)
                                    .font(.system(size: 12)).foregroundColor(.gray)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            if idx < exercises.prefix(5).count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.04))
                                    .padding(.horizontal, 16)
                            }
                        }
                        if exercises.count > 5 {
                            Text("+ \(exercises.count - 5) exercices")
                                .font(.system(size: 11)).foregroundColor(.gray)
                                .padding(.horizontal, 16).padding(.bottom, 8)
                        }
                    }
                }

                if dash.today == "Repos" {
                    NavigationLink(destination: BonusSeanceView()) {
                        HStack(spacing: 8) {
                            Image(systemName: dash.hasPartialLogs ? "play.fill" : "plus.circle.fill")
                            Text(dash.hasPartialLogs ? "Continuer la séance" : "Faire une séance")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.gray, Color.gray.opacity(0.75)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color.gray.opacity(0.3), radius: 10, y: 4)
                    }
                    .buttonStyle(SpringButtonStyle())
                    .padding([.horizontal, .bottom], 16)
                    .padding(.top, 12)
                } else {
                    NavigationLink(destination: SeanceView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text(dash.hasPartialLogs ? "Continuer la séance" : "Commencer la séance")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [todayColor, todayColor.opacity(0.75)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: todayColor.opacity(0.4), radius: 10, y: 4)
                    }
                    .buttonStyle(SpringButtonStyle())
                    .padding([.horizontal, .bottom], 16)
                    .padding(.top, 12)
                }
            }
        }
        .glassCardAccent(isLoggedToday ? .green : todayColor)
        .cornerRadius(16)
    }
}

// MARK: - Today Session Recap
struct TodaySessionRecap: View {
    let session: SessionEntry
    let color: Color
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Métriques clés
            HStack(spacing: 0) {
                if let rpe = session.rpe {
                    RecapMetric(value: String(format: "%.1f", rpe), label: "RPE", color: rpeColor(rpe))
                }
                if let dur = session.durationMin {
                    RecapMetric(value: String(format: "%.0f min", dur), label: "Durée", color: .blue)
                }
                if let energy = session.energyPre {
                    RecapMetric(
                        value: String(repeating: "⚡", count: energy),
                        label: "Énergie",
                        color: .yellow
                    )
                }
                Spacer()
            }

            // Exercices réalisés
            if let exos = session.exos, !exos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXERCICES")
                        .font(.system(size: 9, weight: .bold)).tracking(2).foregroundColor(.gray)
                    FlowRow(items: exos.prefix(6).map { $0 }) { ex in
                        Text(ex)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(color.opacity(0.1))
                            .cornerRadius(5)
                    }
                    if exos.count > 6 {
                        Text("+ \(exos.count - 6) autres")
                            .font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
            }

            // Commentaire
            if let comment = session.comment, !comment.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 10)).foregroundColor(.gray)
                    Text(comment)
                        .font(.system(size: 12)).foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func rpeColor(_ rpe: Double) -> Color {
        if rpe >= 9 { return .red }
        if rpe >= 7 { return .orange }
        return .green
    }
}

// MARK: - Recap Metric Pill
struct RecapMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .black))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 4)
    }
}

// MARK: - Flow Row (wrap des tags)
struct FlowRow<Item: StringProtocol, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        // Wrap manuel : HStack en lignes de max 3 items
        let rows = stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0..<min($0 + 3, items.count)])
        }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.0) { _, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.0) { _, item in
                        content(item)
                    }
                }
            }
        }
    }
}

// MARK: - Stats Row
struct StatsRowView: View {
    let dash: DashboardData

    var totalSessions: Int { dash.sessions.count }
    var avgRPE: Double {
        let rpes = dash.sessions.values.compactMap(\.rpe)
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }
    var weekSessions: Int {
        let fmt = DateFormatter.isoDate
        let todayStr = fmt.string(from: Date())
        guard let todayMidnight = fmt.date(from: todayStr) else { return 0 }
        let base = todayMidnight.timeIntervalSince1970
        let weekday = Calendar.current.component(.weekday, from: Date())
        let daysSinceMonday = (weekday + 5) % 7
        var count = 0
        for i in 0...daysSinceMonday {
            let d = Date(timeIntervalSince1970: base - Double(i) * 86400.0)
            if dash.sessions[fmt.string(from: d)] != nil { count += 1 }
        }
        return count
    }
    var totalVolume: String {
        let vol = dash.sessions.values.compactMap(\.sessionVolume).reduce(0, +)
        if vol >= 1000 { return String(format: "%.1ft", vol / 1000.0) }
        return vol > 0 ? String(format: "%.0fkg", vol) : "—"
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatPill(value: "\(totalSessions)", label: "SÉANCES", color: .orange)
            StatPill(value: avgRPE > 0 ? String(format: "%.1f", avgRPE) : "—", label: "RPE MOY", color: .purple)
            StatPill(value: "\(weekSessions)", label: "CETTE SEMAINE", color: .cyan)
            StatPill(value: totalVolume, label: "VOLUME TOTAL", color: .green)
        }
    }
}

// MARK: - Heatmap
struct HeatmapView: View {
    let sessions: [String: SessionEntry]

    private var last30Days: [(String, Bool)] {
        let base = Date().timeIntervalSince1970
        return (0..<30).reversed().map { offset in
            let date = Date(timeIntervalSince1970: base - Double(offset) * 86400.0)
            let key = DateFormatter.isoDate.string(from: date)
            return (key, sessions[key] != nil)
        }
    }

    var activeDays: Int { last30Days.filter(\.1).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(title: "ASSIDUITÉ")
                    Text("Jours d'entraînement complétés")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(activeDays)")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.orange)
                    Text("sur 30 jours")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }

            // Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                ForEach(Array(last30Days.enumerated()), id: \.0) { idx, day in
                    let isToday = idx == last30Days.count - 1
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.1 ? Color.orange : Color.white.opacity(0.04))
                        if isToday {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                        } else if day.1 {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
                        }
                    }
                    .frame(height: 22)
                }
            }

            // Barre d'assiduité
            let pct = Double(activeDays) / 30.0
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Assiduité")
                        .font(.system(size: 10)).foregroundColor(.gray)
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07)).frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * pct), height: 4)
                    }
                }
                .frame(height: 4)
            }

            // Légende
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.orange)
                        .frame(width: 12, height: 12)
                    Text("Entraînement")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    Text("Aujourd'hui")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
                Spacer()
                Text("← passé   présent →")
                    .font(.system(size: 9)).foregroundColor(.gray.opacity(0.5))
            }
        }
        .padding(16)
        .glassCard()
        .cornerRadius(16)
    }
}

// MARK: - Week Grid
struct WeekGridView: View {
    let schedule: [String: String]
    let sessions: [String: SessionEntry]

    private let days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    private func dateForDay(_ index: Int) -> String {
        let weekday = Calendar.current.component(.weekday, from: Date()) // Sun=1, Mon=2..Sat=7
        let daysSinceMonday = (weekday + 5) % 7
        let base = Date().timeIntervalSince1970
        let monday = Date(timeIntervalSince1970: base - Double(daysSinceMonday) * 86400.0)
        let day = Date(timeIntervalSince1970: monday.timeIntervalSince1970 + Double(index) * 86400.0)
        return DateFormatter.isoDate.string(from: day)
    }

    private func isToday(_ index: Int) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return index == (weekday + 5) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "CETTE SEMAINE")

            let scheduleKeys = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    let seance = schedule[scheduleKeys[i]] ?? "Repos"
                    let dateStr = dateForDay(i)
                    let done = sessions[dateStr] != nil
                    let today = isToday(i)

                    VStack(spacing: 5) {
                        Text(days[i])
                            .font(.system(size: 10, weight: today ? .bold : .medium))
                            .foregroundColor(today ? .white : .gray)

                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(done ? seanceColor(seance) : seanceColor(seance).opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(today ? seanceColor(seance).opacity(0.6) : seanceColor(seance).opacity(0.15), lineWidth: today ? 1.5 : 0.5)
                                )

                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Text(seanceShort(seance))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(seanceColor(seance))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .padding(.horizontal, 2)
                            }
                        }
                        .frame(height: 32)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .glassCard()
        .cornerRadius(16)
    }

    private func seanceShort(_ s: String) -> String {
        switch s {
        case "Push A":             return "PSH A"
        case "Pull A":             return "PLL A"
        case "Legs":               return "LEGS"
        case "Push B":             return "PSH B"
        case "Pull B + Full Body": return "PLL B"
        case "Yoga / Tai Chi":     return "YOGA"
        case "Recovery":           return "REC"
        default: return "—"
        }
    }

    private func seanceColor(_ s: String) -> Color {
        switch s {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery": return .green
        default: return .gray
        }
    }
}

// MARK: - Nutrition Summary
struct NutritionSummaryView: View {
    let totals: NutritionTotals
    let settings: NutritionSettings?

    private var protTarget: Double { settings?.proteines ?? 160 }
    private var protCurrent: Double { totals.proteines ?? 0 }
    private var pct: Double { min(protCurrent / max(protTarget, 1), 1.0) }
    private var ringColor: Color {
        if protCurrent > protTarget { return .red }
        if protCurrent >= protTarget { return .green }
        return .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "NUTRITION AUJOURD'HUI", icon: "fork.knife")

            HStack(spacing: 16) {
                // Anneau protéines
                ZStack {
                    Circle().stroke(Color(hex: "191926"), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: pct)
                    VStack(spacing: 0) {
                        Text("\(Int(protCurrent))")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.white)
                        Text("g")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 6) {
                    // Statut protéines
                    if protCurrent >= protTarget {
                        Label("Objectif atteint", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    } else {
                        Text("Encore \(Int(protTarget - protCurrent))g de prot")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                    }

                    // Badges macros
                    HStack(spacing: 8) {
                        NutriBadge(value: "\(Int(totals.calories ?? 0))", unit: "kcal", color: .orange)
                        NutriBadge(value: "\(Int(totals.glucides ?? 0))", unit: "g carbs", color: .yellow)
                        NutriBadge(value: "\(Int(totals.lipides ?? 0))", unit: "g lip", color: .pink)
                    }
                }
            }

            // Barre de progression calories
            if let calTarget = settings?.calories, calTarget > 0 {
                let calCurrent = totals.calories ?? 0
                let calPct = min(calCurrent / calTarget, 1.0)
                let overTarget = calCurrent > calTarget
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Calories")
                            .font(.system(size: 10)).foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(calCurrent)) / \(Int(calTarget)) kcal")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(overTarget ? .red : .orange)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                            Capsule()
                                .fill(overTarget ? Color.red : Color.orange)
                                .frame(width: max(5, geo.size.width * calPct), height: 5)
                                .animation(.easeOut(duration: 0.6), value: calPct)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(16)
        .glassCard(color: .orange, intensity: 0.04)
        .cornerRadius(16)
    }
}

struct NutriBadge: View {
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .black))
                .foregroundColor(color)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15), lineWidth: 0.5))
        .cornerRadius(10)
    }
}

// MARK: - Recovery Snapshot Strip

struct RecoverySnapshotView: View {
    let recovery: RecoveryEntry

    var body: some View {
        HStack(spacing: 0) {
            if let sleep = recovery.sleepHours {
                SnapMetric(icon: "moon.zzz.fill", value: String(format: "%.1fh", sleep), label: "Sommeil", color: .indigo)
            }
            if let rhr = recovery.restingHr {
                SnapMetric(icon: "heart.fill", value: "\(Int(rhr))", label: "FC repos", color: .red)
            }
            if let hrv = recovery.hrv {
                SnapMetric(icon: "waveform.path.ecg", value: "\(Int(hrv))ms", label: "HRV", color: .green)
            }
            if let steps = recovery.steps {
                let stepsStr = steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000.0) : "\(steps)"
                SnapMetric(icon: "figure.walk", value: stepsStr, label: "Pas", color: .blue)
            }
        }
        .padding(.vertical, 12)
        .glassCard(color: .indigo, intensity: 0.05)
        .cornerRadius(16)
    }
}

struct SnapMetric: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 15, weight: .black))
                .foregroundColor(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(0.3)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Morning Brief Card
struct MorningBriefCardView: View {
    let data: MorningBriefData
    var lssTrend: [LifeStressScore] = []
    var lastSessionDate: String? = nil

    private var accentColor: Color {
        switch data.recommendation {
        case "defer":      return .red
        case "reduce":     return .orange
        case "go_caution": return .yellow
        default:           return .green
        }
    }

    private var iconName: String {
        switch data.recommendation {
        case "defer":      return "exclamationmark.triangle.fill"
        case "reduce":     return "arrow.down.circle.fill"
        case "go_caution": return "exclamationmark.circle.fill"
        default:           return "checkmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(accentColor.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("COACH DU MATIN")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    Text(data.sessionToday)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                Spacer()
                CardInfoButton(title: "Coach du matin", entries: InfoEntry.lssEntries)
                if let lss = data.lss {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(lss))")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(accentColor)
                        Text("LSS")
                            .font(.system(size: 9, weight: .bold)).tracking(1)
                            .foregroundColor(.gray)
                    }
                }
            }

            // LSS gauge
            if let lss = data.lss {
                LSSGauge(score: lss, color: accentColor)
            }

            // Message
            Text(data.message)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            // Flags actifs
            let activeFlags = flagChips
            if !activeFlags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(activeFlags, id: \.label) { chip in
                        HStack(spacing: 4) {
                            Image(systemName: chip.icon)
                                .font(.system(size: 9, weight: .bold))
                            Text(chip.label)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(chip.color)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(chip.color.opacity(0.12))
                        .overlay(Capsule().stroke(chip.color.opacity(0.3), lineWidth: 0.5))
                        .clipShape(Capsule())
                    }
                }
            }

            // Ajustements
            if !data.adjustments.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(data.adjustments, id: \.self) { adj in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(accentColor.opacity(0.7))
                                .padding(.top, 2)
                            Text(adj)
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            // Composantes LSS
            if let comp = data.components {
                LSSComponentsRow(components: comp)
            }

            // LSS sparkline + delta vs semaine
            if lssTrend.count >= 3 {
                LSSSparklineRow(trend: lssTrend, currentLss: data.lss, accentColor: accentColor)
            }

            // Contexte temporel
            let hour = Calendar.current.component(.hour, from: Date())
            if let lastDate = lastSessionDate,
               let last = DateFormatter.isoDate.date(from: lastDate) {
                let hours = Int(Date().timeIntervalSince(last) / 3600)
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.system(size: 10)).foregroundColor(.gray)
                    Text("Dernière séance il y a \(hours)h")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            if hour >= 20 {
                HStack(spacing: 5) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 10)).foregroundColor(.indigo)
                    Text("Séance tardive — pense à bien récupérer après")
                        .font(.system(size: 11)).foregroundColor(.indigo.opacity(0.8))
                }
            }

            // Couverture de données insuffisante — Fix #16: direct action link
            if data.dataCoverage < 0.6 {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text("Données partielles — \(Int(data.dataCoverage * 100))% des métriques disponibles")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    NavigationLink(destination: RecoveryView()) {
                        Text("Compléter →")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.indigo)
                    }
                }
            }
        }
        .padding(16)
        .background(accentColor.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accentColor.opacity(0.28), lineWidth: 1))
        .cornerRadius(16)
    }

    private struct FlagChip {
        let icon: String
        let label: String
        let color: Color
    }

    private var flagChips: [FlagChip] {
        var chips: [FlagChip] = []
        if data.flags.hrvDrop        { chips.append(.init(icon: "waveform.path.ecg", label: "HRV bas",          color: .orange)) }
        if data.flags.sleepDeprivation { chips.append(.init(icon: "moon.zzz.fill",  label: "Manque sommeil",   color: .indigo)) }
        if data.flags.trainingOverload { chips.append(.init(icon: "flame.fill",      label: "Surcharge",       color: .red)) }
        return chips
    }
}

// MARK: - Peak Prediction Card
struct PeakPredictionCard: View {
    let prediction: PeakPredictionResponse

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "go":         return .green
        case "go_caution": return .yellow
        case "reduce":     return .orange
        default:           return .red
        }
    }

    private func dayLabel(_ dateStr: String) -> String {
        guard let d = DateFormatter.isoDate.date(from: dateStr) else { return "?" }
        let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = Locale(identifier: "fr_CA")
        return f.string(from: d).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.purple)
                Text("PRÉVISION 7 JOURS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("base LSS \(String(format: "%.0f", prediction.baseline))")
                    .font(.system(size: 10)).foregroundColor(.gray)
                CardInfoButton(title: "Prévision 7 jours", entries: InfoEntry.predictionEntries)
            }

            HStack(spacing: 6) {
                ForEach(prediction.days) { day in
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(levelColor(day.level).opacity(day.isPeak ? 0.3 : 0.1))
                                .frame(width: 36, height: 36)
                            if day.isPeak {
                                Circle()
                                    .stroke(Color.orange, lineWidth: 1.5)
                                    .frame(width: 36, height: 36)
                            }
                            Text("\(Int(day.predictedLss))")
                                .font(.system(size: 11, weight: day.isPeak ? .black : .semibold))
                                .foregroundColor(day.isPeak ? .orange : levelColor(day.level))
                        }
                        Text(dayLabel(day.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(day.isPeak ? .orange : .gray)
                        if day.isPeak {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7)).foregroundColor(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Fix #6: CTA toward best training day
            if let peakDay = prediction.days.first(where: { $0.isPeak }) {
                NavigationLink(destination: StatsView()) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Jour optimal : \(dayLabel(peakDay.date)) — Voir les stats")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassCard(color: .purple, intensity: 0.04)
        .cornerRadius(16)
    }
}

// MARK: - LSS Sparkline Row
struct LSSSparklineRow: View {
    let trend: [LifeStressScore]   // index 0 = today (most recent)
    let currentLss: Double?
    let accentColor: Color

    private var sorted: [LifeStressScore] { trend.sorted { $0.date < $1.date } }

    private var avg: Double {
        let scores = trend.map { $0.score }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    private var delta: Double {
        guard let lss = currentLss else { return 0 }
        return lss - avg
    }

    var body: some View {
        HStack(spacing: 10) {
            Chart {
                ForEach(sorted.indices, id: \.self) { i in
                    LineMark(
                        x: .value("j", i),
                        y: .value("LSS", sorted[i].score)
                    )
                    .foregroundStyle(accentColor.opacity(0.8))
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("j", i),
                        y: .value("LSS", sorted[i].score)
                    )
                    .foregroundStyle(accentColor.opacity(0.12))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...100)
            .frame(width: 72, height: 28)

            let d = delta
            HStack(spacing: 3) {
                Image(systemName: d >= 3 ? "arrow.up.right" : d <= -3 ? "arrow.down.right" : "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                Text("\(d >= 0 ? "+" : "")\(String(format: "%.0f", d)) pts vs moy 7j")
                    .font(.system(size: 11))
            }
            .foregroundColor(d >= 5 ? .green : d <= -5 ? .orange : .gray)

            Spacer()
        }
    }
}

// MARK: - LSS Gauge
struct LSSGauge: View {
    let score: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 6)
                Capsule()
                    .fill(LinearGradient(
                        colors: [.red, .orange, .yellow, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * score / 100, height: 6)
                    .animation(.easeOut(duration: 0.7), value: score)
                // Curseur
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .shadow(color: color.opacity(0.5), radius: 4)
                    .offset(x: max(0, geo.size.width * score / 100 - 5))
                    .animation(.easeOut(duration: 0.7), value: score)
            }
        }
        .frame(height: 10)
    }
}

// MARK: - LSS Components Row
struct LSSComponentsRow: View {
    let components: MorningBriefComponents

    private var items: [(String, String, Double?)] {
        [
            ("moon.fill",       "Sommeil",   components.sleepQuality),
            ("waveform.path.ecg", "HRV",     components.hrvTrend),
            ("heart.fill",      "FC repos",  components.rhrTrend),
            ("brain.head.profile", "Stress", components.subjectiveStress),
            ("flame.fill",      "Fatigue",   components.trainingFatigue),
        ]
    }

    var body: some View {
        let available = items.filter { $0.2 != nil }
        if available.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text("DÉTAIL LSS")
                    .font(.system(size: 9, weight: .bold)).tracking(2)
                    .foregroundColor(.gray)
                HStack(spacing: 6) {
                    ForEach(available, id: \.0) { icon, label, value in
                        if let v = value {
                            VStack(spacing: 4) {
                                Image(systemName: icon)
                                    .font(.system(size: 9))
                                    .foregroundColor(scoreColor(v))
                                GeometryReader { geo in
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white.opacity(0.07))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(scoreColor(v))
                                            .frame(height: geo.size.height * v / 100)
                                    }
                                }
                                .frame(width: 6, height: 24)
                                .animation(.easeOut(duration: 0.6), value: v)
                                Text(label)
                                    .font(.system(size: 8))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        )
    }

    private func scoreColor(_ v: Double) -> Color {
        if v >= 70 { return .green }
        if v >= 45 { return .yellow }
        return .red
    }
}

// MARK: - SoirCardView

struct SoirCardView: View {
    let data: SeanceSoirData

    private var sessionName: String { data.todaySoir ?? "Séance du soir" }

    private var sessionColor: Color {
        switch sessionName {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .indigo
        }
    }

    private var sessionIcon: String {
        switch sessionName {
        case "Push A", "Push B", "Pull A", "Pull B + Full Body", "Legs": return "dumbbell.fill"
        case "Yoga / Tai Chi": return "figure.mind.and.body"
        case "Recovery":       return "heart.fill"
        default:               return "moon.stars.fill"
        }
    }

    private var exercises: [(String, String)] {
        guard let program = data.fullProgram[sessionName] else { return [] }
        return program.map { ($0.key, $0.value.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(sessionColor.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: data.alreadyLogged ? "checkmark" : sessionIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(data.alreadyLogged ? .green : sessionColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("CE SOIR")
                        .font(.system(size: 9, weight: .bold)).tracking(2).foregroundColor(.gray)
                    Text(sessionName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(data.alreadyLogged ? .green : sessionColor)
                }
                Spacer()
                if data.alreadyLogged {
                    HStack(spacing: 5) {
                        PulsingDot(color: .green)
                        Text("Complété")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)

            if !exercises.isEmpty && !data.alreadyLogged {
                VStack(spacing: 0) {
                    ForEach(exercises.prefix(5), id: \.0) { ex, sets in
                        HStack {
                            Circle().fill(sessionColor.opacity(0.25)).frame(width: 5, height: 5)
                            Text(ex)
                                .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                            Spacer()
                            Text(sets)
                                .font(.system(size: 12)).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 7)
                    }
                    if exercises.count > 5 {
                        Text("+ \(exercises.count - 5) exercices")
                            .font(.system(size: 11)).foregroundColor(.gray)
                            .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                }
            }

            if !data.alreadyLogged {
                NavigationLink(destination: SeanceSoirView()) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill")
                        Text("Commencer la séance du soir")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [sessionColor, sessionColor.opacity(0.75)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: sessionColor.opacity(0.4), radius: 10, y: 4)
                }
                .buttonStyle(SpringButtonStyle())
                .padding([.horizontal, .bottom], 16)
                .padding(.top, 12)
            }
        }
        .glassCardAccent(data.alreadyLogged ? .green : sessionColor)
        .cornerRadius(16)
    }
}

// MARK: - Insights Card

struct DashboardInsightsCard: View {
    let insights: [InsightEntry]

    private func color(for level: String) -> Color {
        switch level {
        case "warning": return .orange
        case "success": return .green
        default:        return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "INTELLIGENCE", icon: "brain.head.profile")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ForEach(Array(insights.enumerated()), id: \.element.id) { idx, insight in
                if idx > 0 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.horizontal, 16)
                }
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color(for: insight.level).opacity(0.15))
                            .frame(width: 34, height: 34)
                        Image(systemName: insight.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(color(for: insight.level))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(insight.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text(insight.message)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Spacer(minLength: 4)
        }
        .glassCard(color: .purple, intensity: 0.05)
    }
}

// MARK: - Great Day Card
struct GreatDayCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            Text("Récupération optimale — séance complète")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(color: .green, intensity: 0.06)
    }
}
