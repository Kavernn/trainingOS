import SwiftUI
import Charts

// MARK: - Entry point

struct MentalAmeView: View {
    @State private var moodDue:        MoodDueStatus?
    @State private var recentMoods:    [MoodEntry] = []
    @State private var summary:        MentalHealthSummary?
    @State private var lss:            LifeStressScore?
    @State private var cachedEmotions: [MoodEmotion] = []
    @State private var showMoodSheet   = false
    @AppStorage("mh_disclaimer_dismissed") private var disclaimerDismissed = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AmbientBackground(color: .teal)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    SignalDuJourHeader(lss: lss, recentMoods: recentMoods)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    MesuresContent(
                        summary: summary,
                        recentMoods: recentMoods,
                        moodDue: moodDue,
                        cachedEmotions: cachedEmotions,
                        disclaimerDismissed: $disclaimerDismissed,
                        showMoodSheet: $showMoodSheet
                    )
                }
            }
            .navigationTitle("Mental & Âme")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showMoodSheet,
                   onDismiss: { Task { await loadData() } }) {
                MoodLogSheet(emotions: cachedEmotions)
            }
            .task { await loadData() }
        }
    }

    private func loadData() async {
        // Sequential — async let LIFO crash on iOS 26 beta
        let d = try? await APIService.shared.checkMoodDue()
        let s = try? await APIService.shared.fetchMentalHealthSummary(days: 7)
        let m = try? await APIService.shared.fetchMoodHistory(days: 14, limit: 7)
        let e = try? await APIService.shared.fetchMoodEmotions()
        let l = try? await APIService.shared.fetchLifeStressScore()
        await MainActor.run {
            moodDue        = d
            summary        = s
            if let items = m?.items { recentMoods = items }
            if let list  = e, !list.isEmpty { cachedEmotions = list }
            lss            = l
        }
    }
}

// MARK: - Signal du jour header

private struct SignalDuJourHeader: View {
    let lss: LifeStressScore?
    let recentMoods: [MoodEntry]

    private var todayMood: MoodEntry? {
        let today = String(Date().ISO8601Format().prefix(10))
        return recentMoods.first { $0.date.hasPrefix(today) }
    }

    private var lssColor: Color {
        guard let s = lss?.score else { return .gray }
        return s >= 70 ? Color.appSuccess : s >= 40 ? Color.appWarning : Color.appDanger
    }

    private var lssLabel: String {
        guard let s = lss?.score else { return "—" }
        return s >= 70 ? "Équilibre" : s >= 40 ? "Vigilance" : "Stress élevé"
    }

    private var moodColor: Color {
        guard let s = todayMood?.score else { return .gray }
        return Color.moodColor(for: s)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ÉQUILIBRE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.appOnSurface.opacity(0.4))
                    .tracking(2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(lss.map { "\($0.score)" } ?? "—")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(lssColor)
                    if lss != nil {
                        Text("/ 100")
                            .font(.appMicro.weight(.light))
                            .foregroundStyle(Color.appOnSurface.opacity(0.4))
                    }
                }
                Text(lssLabel)
                    .font(.appMicro.weight(.medium))
                    .foregroundStyle(lssColor.opacity(0.8))
                Text("Sommeil · HRV · Fatigue")
                    .font(.system(size: 8, weight: .light))
                    .foregroundStyle(Color.appOnSurface.opacity(0.25))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.appSurfaceInset)
                .frame(width: 0.5)
                .padding(.vertical, 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text("HUMEUR")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.appOnSurface.opacity(0.4))
                    .tracking(2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(todayMood.map { "\($0.score)" } ?? "—")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(moodColor)
                    if todayMood != nil {
                        Text("/ 10")
                            .font(.appMicro.weight(.light))
                            .foregroundStyle(Color.appOnSurface.opacity(0.4))
                    }
                }
                Text(todayMood != nil ? "Aujourd'hui" : "Non loggé")
                    .font(.appMicro.weight(.medium))
                    .foregroundStyle(todayMood != nil ? moodColor.opacity(0.8) : Color.gray.opacity(0.5))
                Text("Humeur subjective /10")
                    .font(.system(size: 8, weight: .light))
                    .foregroundStyle(Color.appOnSurface.opacity(0.25))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appSurfaceInset)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.appSurfaceInset, lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Mesures content

private struct MesuresContent: View {
    let summary: MentalHealthSummary?
    let recentMoods: [MoodEntry]
    let moodDue: MoodDueStatus?
    let cachedEmotions: [MoodEmotion]
    @Binding var disclaimerDismissed: Bool
    @Binding var showMoodSheet: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if !disclaimerDismissed {
                    DisclaimerBanner(onDismiss: { disclaimerDismissed = true })
                }

                MoodQuickLogCard(
                    moodDue: moodDue,
                    recentMoods: recentMoods,
                    cachedEmotions: cachedEmotions,
                    onLog: { showMoodSheet = true }
                )
                .appearAnimation(delay: 0.03)

                if recentMoods.count >= 2 {
                    MoodSparklineCard(entries: recentMoods)
                        .appearAnimation(delay: 0.05)
                }

                NavigationLink { PSSView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.title2).foregroundColor(Color.appInfo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stress & PSS")
                                .font(.headline).foregroundColor(.appTextPrimary)
                            Text(stressSubtitle)
                                .font(.caption).foregroundColor(Color.appOnSurface.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(Color.appOnSurface.opacity(0.4))
                    }
                    .padding(14)
                    .glassCard()
                    .padding(.horizontal)
                }
                .appearAnimation(delay: 0.06)

                NavigationLink { MoodTrackerView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "face.smiling.fill")
                            .font(.title2).foregroundColor(Color.forge)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Humeur")
                                .font(.headline).foregroundColor(.appTextPrimary)
                            Text(moodSubtitle)
                                .font(.caption).foregroundColor(Color.appOnSurface.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(Color.appOnSurface.opacity(0.4))
                    }
                    .padding(14)
                    .glassCard()
                    .padding(.horizontal)
                }
                .appearAnimation(delay: 0.07)

                NavigationLink { MentalHealthDashboardView() } label: {
                    HStack {
                        Label("Résumé & insights", systemImage: "chart.bar.fill")
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(Color.appOnSurface.opacity(0.4))
                    }
                    .padding()
                    .glassCard(color: .teal, intensity: 0.08)
                    .padding(.horizontal)
                }
                .appearAnimation(delay: 0.09)

                NavigationLink { CrisisResourcesView() } label: {
                    HStack {
                        Image(systemName: "phone.fill").foregroundColor(Color.appDanger)
                        Text("Ressources en cas de crise")
                            .foregroundColor(Color.appDanger).fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(Color.appOnSurface.opacity(0.4))
                    }
                    .padding()
                    .glassCard(color: Color.appDanger, intensity: 0.06)
                    .padding(.horizontal)
                }
                .appearAnimation(delay: 0.11)

                Spacer(minLength: contentBottomPadding)
            }
            .padding(.top, 8)
        }
    }

    private var stressSubtitle: String {
        if let score = summary?.pssScore, let cat = summary?.pssCategory {
            let label = cat == "low" ? "Faible" : cat == "moderate" ? "Modéré" : "Élevé"
            return "PSS \(score)/40 · Stress \(label)"
        }
        return "Bilan mensuel + score automatique"
    }

    private var moodSubtitle: String {
        if let avg = summary?.avgMood { return String(format: "Moy. %.1f/10", avg) }
        return moodDue?.isDue == true ? "À loguer" : "À jour"
    }
}

// MARK: - Composants Mesures

private struct DisclaimerBanner: View {
    let onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundColor(Color.appInfo)
            Text("Cette section est un outil d'auto-suivi. Elle ne remplace pas un professionnel de santé mentale.")
                .font(.caption).foregroundColor(Color.appOnSurface.opacity(0.7))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.appCaption.weight(.medium)).foregroundColor(.gray)
            }
        }
        .padding(12)
        .glassCard(color: Color.appInfo, intensity: 0.06)
        .padding(.horizontal)
    }
}

private struct MoodQuickLogCard: View {
    let moodDue: MoodDueStatus?
    let recentMoods: [MoodEntry]
    let cachedEmotions: [MoodEmotion]
    let onLog: () -> Void

    private var todayEntry: MoodEntry? {
        let today = String(Date().ISO8601Format().prefix(10))
        return recentMoods.first { $0.date.hasPrefix(today) }
    }

    private var scoreColor: Color {
        guard let s = todayEntry?.score else { return Color.forge }
        return Color.moodColor(for: s)
    }

    var body: some View {
        Button(action: onLog) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(scoreColor.opacity(0.15)).frame(width: 48, height: 48)
                    if let entry = todayEntry {
                        Text("\(entry.score)")
                            .font(.system(size: 20, weight: .bold)).foregroundColor(scoreColor)
                    } else {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 22)).foregroundColor(.statusYellow)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let entry = todayEntry {
                        Text("Humeur loggée")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.appTextPrimary)
                        if !entry.emotions.isEmpty {
                            Text(entry.emotions.prefix(3).joined(separator: " · "))
                                .font(.caption).foregroundColor(Color.appOnSurface.opacity(0.6)).lineLimit(1)
                        } else {
                            Text("Appuie pour modifier")
                                .font(.caption).foregroundColor(Color.appOnSurface.opacity(0.6))
                        }
                    } else {
                        Text(moodDue?.isDue == true ? "Note ton humeur" : "Comment tu te sens ?")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.appTextPrimary)
                        Text("30 secondes · émotions + score")
                            .font(.caption).foregroundColor(Color.appOnSurface.opacity(0.6))
                    }
                }
                Spacer()
                Image(systemName: todayEntry == nil ? "plus.circle.fill" : "pencil.circle")
                    .font(.system(size: 22))
                    .foregroundColor(todayEntry == nil ? .statusYellow : Color.appOnSurface.opacity(0.4))
            }
            .padding(14)
            .glassCard(color: todayEntry != nil ? scoreColor : .statusYellow, intensity: 0.08)
        }
        .buttonStyle(SpringButtonStyle())
        .padding(.horizontal)
    }
}

private struct MoodSparklineCard: View {
    let entries: [MoodEntry]

    private var last7: [MoodEntry] { Array(entries.prefix(7).reversed()) }

    private func color(for score: Int) -> Color {
        Color.moodColor(for: score)
    }

    var body: some View {
        let avg = last7.isEmpty ? 5.0 : Double(last7.map(\.score).reduce(0, +)) / Double(last7.count)
        let lineColor = color(for: Int(avg.rounded()))

        VStack(alignment: .leading, spacing: 10) {
            Text("Humeur — 7 derniers jours")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.appOnSurface.opacity(0.65))
                .padding(.horizontal, 16)

            Chart(last7) { entry in
                LineMark(x: .value("Date", entry.date), y: .value("Score", entry.score))
                    .foregroundStyle(lineColor.opacity(0.7))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", entry.date), y: .value("Score", entry.score))
                    .foregroundStyle(color(for: entry.score))
                    .symbolSize(60)
            }
            .chartYScale(domain: 1...10)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [1, 5, 10]) { v in
                    AxisValueLabel {
                        Text("\(v.as(Int.self) ?? 0)")
                            .font(.appMicro).foregroundColor(Color.appOnSurface.opacity(0.65))
                    }
                }
            }
            .frame(height: 72)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .glassCard(color: .teal, intensity: 0.05)
        .padding(.horizontal)
    }
}
