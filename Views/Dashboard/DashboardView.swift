
import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = DashboardViewModel()
    @ObservedObject private var api = APIService.shared
    @ObservedObject private var alertService = AlertService.shared
    @State private var showMoodSheet = false
    @State private var showChecklist = false
    @State private var lastRefresh: Date = .distantPast
    @State private var sleepPromptDismissedThisSession = false
    @State private var actionErrorMessage: String? = nil
    @State private var showMorningReveal = false
    @Environment(\.scenePhase) private var scenePhase
    var onOpenSession: (() -> Void)? = nil

    private var todayStr: String {
        DateFormatter.isoDate.string(from: Date())
    }
    private var shouldShowSleepPrompt: Bool {
        // todaySleepLogged = vérité serveur (fonctionne cross-appareils)
        // UserDefaults = cache local pour éviter un flash après dismissal
        // sleepPromptDismissedThisSession = disparition animée dans la session courante
        !sleepPromptDismissedThisSession &&
        !vm.todaySleepLogged &&
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

                            GreetingHeaderView(dash: dash, showChecklist: $showChecklist)
                                .appearAnimation(delay: 0)

                            if let tip = vm.coachTip {
                                CoachTipCard(tip: tip)
                                    .appearAnimation(delay: 0.01)
                            }

                            if let sd = vm.smartDay {
                                SmartDayBannerView(recommendation: sd)
                                    .appearAnimation(delay: 0.015)
                            }

                            DataGapSection(dash: dash, recovery: vm.todayRecovery)
                                .appearAnimation(delay: 0.02)

                            // TodayCard: primary action every session
                            TodayCardView(
                                dash: dash,
                                showGreatDayBadge: vm.morningBrief?.recommendation == "go" && (vm.deload?.fatigueLevel ?? 0) == 0 && dash.sessions[todayStr] != nil,
                                onOpenSession: onOpenSession
                            )
                            .appearAnimation(delay: 0.02)

                            if let soir = vm.eveningSession, soir.hasEveningSession {
                                SoirCardView(data: soir)
                                    .appearAnimation(delay: 0.03)
                            }

                            // UX#4: Week progress strip right under TodayCard
                            WeekProgressStripView(dash: dash)
                                .appearAnimation(delay: 0.04)

                            // UX#5: Compact nutrition strip in position 4 (not last)
                            NavigationLink(destination: NutritionView()) {
                                NutritionStripView(totals: dash.nutritionTotals, settings: dash.nutritionSettings)
                            }
                            .buttonStyle(.plain)
                            .appearAnimation(delay: 0.05)

                            // Recovery snapshot
                            if let rec = vm.todayRecovery,
                               rec.sleepHours != nil || rec.restingHr != nil || rec.hrv != nil || rec.steps != nil {
                                NavigationLink(destination: RecoveryView()) {
                                    RecoverySnapshotView(recovery: rec)
                                }
                                .buttonStyle(.plain)
                                .appearAnimation(delay: 0.06)
                            }

                            if shouldShowSleepPrompt {
                                SleepPromptCard(onDone: {
                                    UserDefaults.standard.set(todayStr, forKey: "sleepPromptDate")
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        sleepPromptDismissedThisSession = true
                                    }
                                }, onError: { message in
                                    actionErrorMessage = message
                                })
                                .appearAnimation(delay: 0.07)
                            }

                            // UX#mood moved up — log while biometrics are fresh
                            if vm.moodDue?.isDue == true {
                                MoodCardView { showMoodSheet = true }
                                    .appearAnimation(delay: 0.08)
                            }

                            // Fix #7: full banner only for level 2; compact chip for level 1
                            if let report = vm.deload, report.fatigueLevel > 0 {
                                if report.fatigueLevel == 2 {
                                    DeloadBannerView(report: report) {
                                        await applyDeload(report: report)
                                    }
                                    .appearAnimation(delay: 0.09)
                                } else {
                                    DeloadChipView(report: report)
                                        .appearAnimation(delay: 0.09)
                                }
                            }


                            if !vm.insights.isEmpty {
                                DashboardInsightsCard(insights: vm.insights)
                                    .appearAnimation(delay: 0.12)
                            }

                            if let report = vm.weeklyReport {
                                NavigationLink(destination: WeeklyReportView(report: report)) {
                                    WeeklyReportTeaser(report: report)
                                }
                                .buttonStyle(.plain)
                                .appearAnimation(delay: 0.125)
                            }

                            // Full stats grid + heatmap stay at the bottom for deeper review
                            NavigationLink(destination: StatsView()) {
                                StatsRowView(dash: dash)
                            }
                            .buttonStyle(.plain)
                            .appearAnimation(delay: 0.13)

                            WeekGridView(schedule: dash.schedule, sessions: dash.sessions)
                                .appearAnimation(delay: 0.14)
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
                        vm.deload   = try? await d
                        vm.moodDue  = try? await m
                        vm.morningBrief    = try? await b
                        vm.eveningSession = try? await s
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
        .task { await vm.loadAll(); lastRefresh = Date(); checkAndShowMorningReveal() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                BehaviorTracker.shared.record(.appOpen)
                if !api.isLoading, Date().timeIntervalSince(lastRefresh) > 300 {
                    Task { await vm.loadAll(); lastRefresh = Date(); checkAndShowMorningReveal() }
                }
            }
        }
        .sheet(isPresented: $showMoodSheet, onDismiss: {
            Task { await vm.refreshMoodDue() }
        }) {
            MoodLogSheet()
        }
        .sheet(isPresented: $showChecklist) {
            NavigationStack {
                ScrollView {
                    ChecklistCardView()
                        .padding(16)
                }
                .navigationTitle("Avant de partir")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { showChecklist = false }
                    }
                }
                .background(Color(hex: "0D0D14").ignoresSafeArea())
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Erreur", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { actionErrorMessage = nil }
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .fullScreenCover(isPresented: $showMorningReveal) {
            if let brief = vm.morningBrief {
                MorningRevealView(morningBrief: brief) {
                    UserDefaults.standard.set(todayStr, forKey: "morningRevealDate")
                    showMorningReveal = false
                }
            }
        }
    }

    private func checkAndShowMorningReveal() {
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour < 14,
              UserDefaults.standard.string(forKey: "morningRevealDate") != todayStr,
              vm.morningBrief != nil else { return }
        showMorningReveal = true
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

    private func applyDeload(report: DeloadReport) async -> Bool {
        do {
            try await api.applyDeload(poidsDeload: report.poidsDeload)
        } catch {
            actionErrorMessage = "Erreur lors du déload — réessaie."
            return false
        }
        await api.fetchDashboard()
        vm.deload = nil
        return true
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
    var onError: (String) -> Void = { _ in }

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
        do {
            try await APIService.shared.logRecovery(
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
        } catch {
            await MainActor.run {
                isSaving = false
                onError("Impossible d'enregistrer le sommeil pour le moment.")
            }
        }
    }
}

// MARK: - Deload Banner
struct DeloadBannerView: View {
    let report: DeloadReport
    var onApplyDeload: (() async -> Bool)? = nil
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
                            Task {
                                let success = await onApplyDeload()
                                if !success { isApplying = false }
                            }
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
    @Binding var showChecklist: Bool

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
                    Text(greeting + (dash.profile.name.map { ", \($0.components(separatedBy: " ").first ?? $0)" } ?? "") + " 👋")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text(formattedDate)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        // UX#2: Checklist button in header — out of main scroll
                        Button {
                            showChecklist = true
                        } label: {
                            Image(systemName: "checklist")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.orange)
                                .padding(8)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Text("Sem. \(dash.week)")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }

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
    var onOpenSession: (() -> Void)? = nil
    @ObservedObject private var api = APIService.shared

    /// Source de vérité : flag serveur OU session dans le dict OU flag optimiste local.
    private var isLoggedToday: Bool {
        dash.alreadyLoggedToday || dash.sessions[dash.todayDate] != nil || api.sessionLoggedToday
    }

    private var todaySession: SessionEntry? {
        dash.sessions[dash.todayDate]
    }

    private var hasPartialLogs: Bool {
        dash.hasPartialLogs || SessionDraftStore.hasDraft(date: dash.todayDate, sessionType: "morning")
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
                            Image(systemName: hasPartialLogs ? "play.fill" : "plus.circle.fill")
                            Text(hasPartialLogs ? "Continuer la séance" : "Faire une séance")
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
                    Group {
                        if let onOpenSession {
                            Button(action: onOpenSession) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text(hasPartialLogs ? "Continuer la séance" : "Commencer la séance")
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
                        } else {
                            NavigationLink(destination: SeanceView()) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text(hasPartialLogs ? "Continuer la séance" : "Commencer la séance")
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
                        }
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

// MARK: - UX#1 — Readiness Strip (before TodayCard)

struct ReadinessStripView: View {
    let brief: MorningBriefData?
    let recovery: RecoveryEntry?

    private var accent: Color {
        switch brief?.recommendation {
        case "defer":      return .red
        case "reduce":     return .orange
        case "go_caution": return .yellow
        default:           return .green
        }
    }

    private var label: String {
        switch brief?.recommendation {
        case "defer":      return "Repos recommandé"
        case "reduce":     return "Volume réduit aujourd'hui"
        case "go_caution": return "Entraîne-toi avec prudence"
        default:           return "Prêt à performer"
        }
    }

    private var icon: String {
        switch brief?.recommendation {
        case "defer":      return "exclamationmark.triangle.fill"
        case "reduce":     return "arrow.down.circle.fill"
        case "go_caution": return "exclamationmark.circle.fill"
        default:           return "bolt.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("READINESS")
                    .font(.system(size: 9, weight: .bold)).tracking(2)
                    .foregroundColor(.gray)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
            }
            Spacer()
            if let rec = recovery {
                HStack(spacing: 14) {
                    if let hrv = rec.hrv {
                        VStack(spacing: 0) {
                            Text("\(Int(hrv))")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.green)
                            Text("HRV")
                                .font(.system(size: 8)).foregroundColor(.gray)
                        }
                    }
                    if let rhr = rec.restingHr {
                        VStack(spacing: 0) {
                            Text("\(Int(rhr))")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.red.opacity(0.85))
                            Text("FC")
                                .font(.system(size: 8)).foregroundColor(.gray)
                        }
                    }
                    if let sleep = rec.sleepHours {
                        VStack(spacing: 0) {
                            Text(String(format: "%.1fh", sleep))
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.indigo)
                            Text("Sommeil")
                                .font(.system(size: 8)).foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - UX#4 — Week Progress Strip (right under TodayCard)

struct WeekProgressStripView: View {
    let dash: DashboardData

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
            let dateStr = fmt.string(from: d)
            // sessions dict = completed sessions (completed=true en DB)
            // Pour aujourd'hui, alreadyLoggedToday est la source la plus fraîche
            let counted = dash.sessions[dateStr] != nil
                || (dateStr == dash.todayDate && dash.alreadyLoggedToday)
            if counted { count += 1 }
        }
        return count
    }

    var weekTarget: Int {
        let restWords = ["repos", "rest", "off", "récupération"]
        let active = dash.schedule.values.filter { val in
            let lower = val.lowercased()
            return !lower.isEmpty && !restWords.contains(where: { lower.contains($0) })
        }.count
        return max(active, 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 14))
                .foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(weekSessions) / \(weekTarget) séances cette semaine")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07)).frame(height: 4)
                        Capsule()
                            .fill(weekSessions >= weekTarget ? Color.green : Color.cyan)
                            .frame(width: max(4, geo.size.width * min(Double(weekSessions) / Double(weekTarget), 1.0)), height: 4)
                            .animation(.easeOut(duration: 0.5), value: weekSessions)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(color: .cyan, intensity: 0.04)
        .cornerRadius(12)
    }
}

// MARK: - UX#5 — Nutrition Strip (compact, position 4)

struct NutritionStripView: View {
    let totals: NutritionTotals
    let settings: NutritionSettings?

    private var calTarget: Double { settings?.calories ?? 0 }
    private var calCurrent: Double { totals.calories ?? 0 }
    private var calPct: Double { calTarget > 0 ? min(calCurrent / calTarget, 1.0) : 0 }
    private var overCal: Bool { calTarget > 0 && calCurrent > calTarget }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("NUTRITION")
                    .font(.system(size: 9, weight: .bold)).tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(Int(calCurrent))\(calTarget > 0 ? " / \(Int(calTarget))" : "") kcal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(overCal ? .red : .orange)
            }

            HStack(spacing: 6) {
                NutriBadge(value: "\(Int(totals.proteines ?? 0))", unit: "prot", color: .blue)
                NutriBadge(value: "\(Int(totals.glucides ?? 0))", unit: "carbs", color: .yellow)
                NutriBadge(value: "\(Int(totals.lipides ?? 0))", unit: "lipides", color: .pink)
                if calTarget > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.06)).frame(height: 4)
                            Capsule()
                                .fill(overCal ? Color.red : Color.orange)
                                .frame(width: max(4, geo.size.width * calPct), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .frame(maxWidth: 80)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(color: .orange, intensity: 0.04)
        .cornerRadius(12)
    }
}

// MARK: - UX#3 — Morning Brief Compact (always shown when "go" + no flags)

struct MorningBriefCompactView: View {
    let data: MorningBriefData

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 30, height: 30)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
            }
            Text("Brief du matin")
                .font(.system(size: 9, weight: .bold)).tracking(2)
                .foregroundColor(.gray)
            Text("Tout est vert — vas-y.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.15), lineWidth: 1))
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

            // Lien vers la vue Stress détaillée
            Divider().background(Color.white.opacity(0.06))
            NavigationLink { PSSView() } label: {
                HStack {
                    Text("Voir le détail Stress")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10)).foregroundColor(.gray.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
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

// MARK: - Data Gap Section

struct DataGapSection: View {
    let dash: DashboardData
    let recovery: RecoveryEntry?

    private var missingRecovery: Bool {
        recovery == nil ||
        (recovery?.sleepHours == nil && recovery?.hrv == nil && recovery?.restingHr == nil)
    }
    private var missingNutrition: Bool { (dash.nutritionTotals.calories ?? 0) < 1 }
    private var missingWeight: Bool    { (dash.profile.weight ?? 0) == 0 }
    private var missingGoals: Bool     { dash.goals.isEmpty && dash.smartGoalsCount == 0 }

    var body: some View {
        let gaps = [missingRecovery, missingNutrition, missingWeight, missingGoals]
        if gaps.contains(true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("À COMPLÉTER")
                    .font(.system(size: 10, weight: .bold)).tracking(2)
                    .foregroundColor(.gray)
                    .padding(.leading, 2)

                VStack(spacing: 6) {
                    if missingRecovery {
                        NavigationLink(destination: RecoveryView()) {
                            DataGapCard(
                                icon: "moon.zzz.fill",
                                color: .indigo,
                                title: "Récupération du jour",
                                subtitle: "Sommeil, FC repos, HRV, courbatures"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if missingNutrition {
                        NavigationLink(destination: NutritionView()) {
                            DataGapCard(
                                icon: "fork.knife",
                                color: .green,
                                title: "Nutrition du jour",
                                subtitle: "Aucun repas enregistré aujourd'hui"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if missingWeight {
                        NavigationLink(destination: BodyCompView()) {
                            DataGapCard(
                                icon: "scalemass.fill",
                                color: .orange,
                                title: "Poids corporel",
                                subtitle: "Ajoute ton poids pour un suivi précis"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if missingGoals {
                        NavigationLink(destination: ObjectifsView()) {
                            DataGapCard(
                                icon: "target",
                                color: .blue,
                                title: "Objectifs",
                                subtitle: "Aucun objectif défini pour le moment"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct DataGapCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(color.opacity(0.6))
        }
        .padding(12)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
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

// MARK: - Smart Day Banner

struct SmartDayBannerView: View {
    let recommendation: SmartDayRecommendation

    private var accentColor: Color {
        switch recommendation.intensity {
        case "normale": return .green
        case "réduite": return .orange
        default:        return .red
        }
    }
    private var icon: String {
        switch recommendation.intensity {
        case "normale": return "bolt.fill"
        case "réduite": return "tortoise.fill"
        default:        return "moon.zzz.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.cta)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accentColor)
                Text(recommendation.reason)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer()
            if let session = recommendation.suggestedSession {
                Text(session)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accentColor.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(color: accentColor, intensity: 0.07)
        .cornerRadius(14)
    }
}

// MARK: - Weekly Report Teaser (tap to open full view)

struct WeeklyReportTeaser: View {
    let report: WeeklyReport

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("RAPPORT DE LA SEMAINE")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5)
                    .foregroundColor(.gray)
                HStack(spacing: 16) {
                    Label("\(report.sessionCount) séances", systemImage: "flame.fill")
                    if report.prCount > 0 {
                        Label("\(report.prCount) PR", systemImage: "trophy.fill")
                            .foregroundColor(.yellow)
                    }
                    if report.totalVolumeLbs > 0 {
                        Label("\(Int(report.totalVolumeLbs / 1000))k lbs", systemImage: "scalemass.fill")
                            .foregroundColor(.orange)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12)).foregroundColor(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(color: .purple, intensity: 0.06)
        .cornerRadius(14)
    }
}

// MARK: - Weekly Report Full View

struct WeeklyReportView: View {
    let report: WeeklyReport
    @ObservedObject private var units = UnitSettings.shared

    private var shareText: String {
        var lines = ["📊 Rapport semaine TrainingOS"]
        lines.append("Séances : \(report.sessionCount)")
        if report.prCount > 0 { lines.append("🏆 PRs : \(report.prCount)") }
        if report.totalVolumeLbs > 0 {
            lines.append("Volume : \(Int(report.totalVolumeLbs / 1000))k lbs")
        }
        if let r = report.avgRecoveryScore { lines.append("Récupération moy. : \(String(format: "%.1f", r))/10") }
        if let s = report.avgSleepHours   { lines.append("Sommeil moy. : \(String(format: "%.1f", s))h") }
        if let c = report.nutritionCompliance { lines.append("Compliance nutrition : \(c)%") }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: .purple)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 4) {
                        Text("RAPPORT SEMAINE")
                            .font(.system(size: 11, weight: .bold)).tracking(2)
                            .foregroundColor(.gray)
                        Text("\(report.weekStart) → \(report.weekEnd)")
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 8)

                    // KPI grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        WeeklyKPI(value: "\(report.sessionCount)", label: "Séances", icon: "flame.fill", color: .orange)
                        WeeklyKPI(value: "\(report.prCount)", label: "PRs battus", icon: "trophy.fill", color: .yellow)
                        if report.totalVolumeLbs > 0 {
                            WeeklyKPI(value: "\(Int(report.totalVolumeLbs / 1000))k", label: "Volume (lbs)", icon: "scalemass.fill", color: .cyan)
                        }
                        if let r = report.avgRecoveryScore {
                            WeeklyKPI(value: String(format: "%.1f/10", r), label: "Récup. moy.", icon: "heart.fill", color: .green)
                        }
                        if let s = report.avgSleepHours {
                            WeeklyKPI(value: String(format: "%.1fh", s), label: "Sommeil moy.", icon: "moon.fill", color: .indigo)
                        }
                        if let steps = report.avgSteps {
                            WeeklyKPI(value: "\(steps / 1000)k", label: "Pas/jour", icon: "figure.walk", color: .teal)
                        }
                        if let hrv = report.avgHrv {
                            WeeklyKPI(value: String(format: "%.0f ms", hrv), label: "HRV moy.", icon: "waveform.path.ecg", color: .cyan)
                        }
                        if let c = report.nutritionCompliance {
                            WeeklyKPI(value: "\(c)%", label: "Nutrition", icon: "fork.knife", color: .green)
                        }
                    }

                    if let top = report.topExercise {
                        HStack(spacing: 10) {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("EXERCICE PHARE").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.gray)
                                Text(top).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .glassCard(color: .yellow, intensity: 0.07)
                        .cornerRadius(14)
                    }

                    ShareLink(item: shareText) {
                        Label("Partager ce rapport", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.purple.opacity(0.7))
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Semaine")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WeeklyKPI: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(color)
            Text(value)
                .font(.system(size: 18, weight: .black)).foregroundColor(color)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .medium)).tracking(1).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard(color: color, intensity: 0.05)
        .cornerRadius(14)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
}
