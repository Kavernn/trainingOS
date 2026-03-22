
import SwiftUI

struct DashboardView: View {
    @ObservedObject private var api = APIService.shared
    @State private var insights: [InsightEntry] = []
    @State private var deload: DeloadReport?
    @State private var moodDue: MoodDueStatus?
    @State private var brief: MorningBriefData?
    @State private var soirData: SeanceSoirData?
    @State private var showMoodSheet = false
    @State private var lastRefresh: Date = .distantPast
    @State private var sleepPromptDismissedThisSession = false
    @State private var todaySleepLogged = false
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
                    VStack(spacing: 16) {
                        ProgressView().tint(.orange).scaleEffect(1.4)
                        Text("Chargement...")
                            .font(.system(size: 13)).foregroundColor(.gray)
                    }
                } else if let dash = api.dashboard {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            GreetingHeaderView(dash: dash)
                                .appearAnimation(delay: 0)

                            if shouldShowSleepPrompt {
                                SleepPromptCard(onDone: {
                                    UserDefaults.standard.set(todayStr, forKey: "sleepPromptDate")
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        sleepPromptDismissedThisSession = true
                                    }
                                })
                            }

                            ChecklistCardView()
                                .appearAnimation(delay: 0.02)

                            if let report = deload, report.fatigueLevel > 0 {
                                DeloadBannerView(report: report)
                                    .appearAnimation(delay: 0.03)
                            }

                            if let b = brief, b.recommendation != "go" {
                                MorningBriefCardView(data: b)
                                    .appearAnimation(delay: 0.04)
                            }

                            if moodDue?.isDue == true {
                                Button { showMoodSheet = true } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "face.smiling.fill")
                                            .foregroundColor(.yellow)
                                        Text("Loguer ton humeur aujourd'hui")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    .padding(12)
                                    .background(Color.yellow.opacity(0.18))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .appearAnimation(delay: 0.04)
                            }

                            if !insights.isEmpty {
                                DashboardInsightsCard(insights: insights)
                                    .appearAnimation(delay: 0.05)
                            }

                            TodayCardView(dash: dash)
                                .appearAnimation(delay: 0.06)

                            if let soir = soirData, soir.hasEveningSession {
                                SoirCardView(data: soir)
                                    .appearAnimation(delay: 0.07)
                            }

                            StatsRowView(dash: dash)
                                .appearAnimation(delay: 0.1)

                            HeatmapView(sessions: dash.sessions)
                                .appearAnimation(delay: 0.15)

                            WeekGridView(schedule: dash.schedule, sessions: dash.sessions)
                                .appearAnimation(delay: 0.2)

                            NutritionSummaryView(totals: dash.nutritionTotals)
                                .appearAnimation(delay: 0.25)
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
            deload   = try? await d
            moodDue  = try? await m
            brief    = try? await b
            soirData = try? await s
            insights = (try? await i) ?? []
            if let log = try? await r {
                todaySleepLogged = log.first(where: { $0.date == todayStr })?.sleepHours != nil
            }
            lastRefresh = Date()
        }
        .onChange(of: scenePhase) {
            // Ne refetch que si la dernière mise à jour date de plus de 5 min
            if scenePhase == .active,
               Date().timeIntervalSince(lastRefresh) > 300 {
                Task {
                    await api.fetchDashboard()
                    async let d = APIService.shared.fetchDeloadData()
                    async let m = APIService.shared.checkMoodDue()
                    async let b = APIService.shared.fetchMorningBrief()
                    async let s = APIService.shared.fetchSeanceSoirData()
                    async let r = APIService.shared.fetchRecoveryData()
                    deload   = try? await d
                    moodDue  = try? await m
                    brief    = try? await b
                    soirData = try? await s
                    if let log = try? await r {
                        todaySleepLogged = log.first(where: { $0.date == todayStr })?.sleepHours != nil
                    }
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
    @ObservedObject private var units = UnitSettings.shared

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
                VStack(alignment: .leading, spacing: 4) {
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

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
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
        .padding(.top, 12)
    }
}

// MARK: - Today Card
struct TodayCardView: View {
    let dash: DashboardData

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
                        PulsingDot(color: .green)
                        Text("Complété")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)

            if isLoggedToday, let session = todaySession {
                // ── Récap séance loggée ───────────────────────────────────
                TodaySessionRecap(session: session, color: todayColor)
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
                        ForEach(exercises.prefix(5), id: \.0) { ex, sets in
                            HStack {
                                Circle().fill(todayColor.opacity(0.25)).frame(width: 5, height: 5)
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

    var body: some View {
        HStack(spacing: 10) {
            StatPill(value: "\(totalSessions)", label: "SÉANCES", color: .orange)
            StatPill(value: avgRPE > 0 ? String(format: "%.1f", avgRPE) : "—", label: "RPE MOY", color: .purple)
            StatPill(value: "S\(dash.week)", label: "SEMAINE", color: .blue)
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
                ForEach(Array(last30Days.enumerated()), id: \.0) { _, day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.1 ? Color.orange : Color.white.opacity(0.04))
                        .frame(height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(day.1 ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 0.5)
                        )
                }
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
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08))
                        .frame(width: 12, height: 12)
                    Text("Repos / non loggé")
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
                            .font(.system(size: 9, weight: today ? .bold : .medium))
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
                                    .font(.system(size: 8, weight: .bold))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "NUTRITION AUJOURD'HUI", icon: "fork.knife")

            HStack(spacing: 12) {
                NutriBadge(value: "\(Int(totals.calories ?? 0))", unit: "kcal", color: .orange)
                NutriBadge(value: "\(Int(totals.proteines ?? 0))", unit: "g prot", color: .blue)
                NutriBadge(value: "\(Int(totals.glucides ?? 0))", unit: "g carbs", color: .yellow)
                NutriBadge(value: "\(Int(totals.lipides ?? 0))", unit: "g lip", color: .pink)
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

// MARK: - Morning Brief Card
struct MorningBriefCardView: View {
    let data: MorningBriefData

    private var accentColor: Color {
        switch data.recommendation {
        case "defer":      return .red
        case "reduce":     return .orange
        case "go_caution": return .yellow
        default:           return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(accentColor)
                Text("Coach du matin")
                    .font(.system(size: 11, weight: .bold)).tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                lssChip
            }
            Text(data.message)
                .font(.system(size: 14))
                .foregroundColor(.white)

            if !data.adjustments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(data.adjustments, id: \.self) { adj in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(accentColor)
                            Text(adj)
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(accentColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accentColor.opacity(0.3), lineWidth: 1))
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    private var lssChip: some View {
        Group {
            if let lss = data.lss {
                Text("LSS \(Int(lss))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accentColor.opacity(0.15))
                    .cornerRadius(8)
            }
        }
    }

    private var iconName: String {
        switch data.recommendation {
        case "defer":  return "exclamationmark.triangle.fill"
        case "reduce": return "arrow.down.circle.fill"
        default:       return "exclamationmark.circle.fill"
        }
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
