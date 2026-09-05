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
    @State private var initialLoaded      = false
    @State private var lssFailed          = false
    @State private var moodHistoryFailed  = false
    @AppStorage("mh_disclaimer_dismissed") private var disclaimerDismissed = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AmbientBackground(color: .teal)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    SignalDuJourHeader(
                        lss: lss,
                        recentMoods: recentMoods,
                        initialLoaded: initialLoaded,
                        lssFailed: lssFailed,
                        moodHistoryFailed: moodHistoryFailed
                    )
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    MesuresContent(
                        summary: summary,
                        recentMoods: recentMoods,
                        moodDue: moodDue,
                        cachedEmotions: cachedEmotions,
                        lss: lss,
                        initialLoaded: initialLoaded,
                        lssFailed: lssFailed,
                        moodHistoryFailed: moodHistoryFailed,
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
        let e = try? await APIService.shared.fetchMoodEmotions()

        var mFailed = false
        let m: PagedResponse<MoodEntry>?
        do    { m = try await APIService.shared.fetchMoodHistory(days: 14, limit: 7) }
        catch { m = nil; mFailed = true }

        var lFailed = false
        let l: LifeStressScore?
        do    { l = try await APIService.shared.fetchLifeStressScore() }
        catch { l = nil; lFailed = true }

        await MainActor.run {
            moodDue        = d
            summary        = s
            if let items = m?.items { recentMoods = items }
            if let list  = e, !list.isEmpty { cachedEmotions = list }
            lss            = l
            lssFailed          = lFailed
            moodHistoryFailed  = mFailed
            initialLoaded      = true
        }
    }
}

// MARK: - Signal du jour header

private struct SignalDuJourHeader: View {
    let lss: LifeStressScore?
    let recentMoods: [MoodEntry]
    let initialLoaded: Bool
    let lssFailed: Bool
    let moodHistoryFailed: Bool

    private var todayMood: MoodEntry? {
        let today = String(Date().ISO8601Format().prefix(10))
        return recentMoods.first { $0.date.hasPrefix(today) }
    }

    private var lssColor: Color {
        guard let s = lss?.score else { return .appTextMuted }
        return s >= 70 ? Color.appSuccess : s >= 40 ? Color.appWarning : Color.appDanger
    }

    private var lssLabel: String {
        guard let s = lss?.score else { return "—" }
        return s >= 70 ? "Équilibre" : s >= 40 ? "Vigilance" : "Stress élevé"
    }

    private var moodColor: Color {
        guard let s = todayMood?.score else { return .appTextMuted }
        return Color.moodColor(for: s)
    }

    private var lssScoreText: String {
        if !initialLoaded { return "…" }
        if lss == nil     { return "—" }
        return "\(lss!.score)"
    }

    private var lssStatusText: String {
        if !initialLoaded            { return "" }
        if lss == nil && lssFailed   { return "Indisponible" }
        return lssLabel
    }

    private var moodScoreText: String {
        if !initialLoaded { return "…" }
        return todayMood.map { "\($0.score)" } ?? "—"
    }

    private var moodStatusText: String {
        if !initialLoaded                            { return "" }
        if todayMood == nil && moodHistoryFailed     { return "Indisponible" }
        return todayMood != nil ? "Aujourd'hui" : "Non loggé"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ÉQUILIBRE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.appOnSurface.opacity(0.4))
                    .tracking(2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(lssScoreText)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(lss != nil ? lssColor : Color.appOnSurface.opacity(0.4))
                    if lss != nil {
                        Text("/ 100")
                            .font(.appMicro.weight(.light))
                            .foregroundStyle(Color.appOnSurface.opacity(0.4))
                    }
                }
                Text(lssStatusText)
                    .font(.appMicro.weight(.medium))
                    .foregroundStyle(lss != nil ? lssColor.opacity(0.8) : Color.appOnSurface.opacity(0.4))
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
                    Text(moodScoreText)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(todayMood != nil ? moodColor : Color.appOnSurface.opacity(0.4))
                    if todayMood != nil {
                        Text("/ 10")
                            .font(.appMicro.weight(.light))
                            .foregroundStyle(Color.appOnSurface.opacity(0.4))
                    }
                }
                Text(moodStatusText)
                    .font(.appMicro.weight(.medium))
                    .foregroundStyle(todayMood != nil ? moodColor.opacity(0.8) : Color.appTextMuted.opacity(0.5))
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
    let lss: LifeStressScore?
    let initialLoaded: Bool
    let lssFailed: Bool
    let moodHistoryFailed: Bool
    @Binding var disclaimerDismissed: Bool
    @Binding var showMoodSheet: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if !disclaimerDismissed {
                    DisclaimerBanner(onDismiss: { disclaimerDismissed = true })
                }

                LifeStressBreakdownCard(
                    lss: lss,
                    initialLoaded: initialLoaded,
                    lssFailed: lssFailed
                )
                .appearAnimation(delay: 0.02)

                MoodQuickLogCard(
                    moodDue: moodDue,
                    recentMoods: recentMoods,
                    cachedEmotions: cachedEmotions,
                    initialLoaded: initialLoaded,
                    moodHistoryFailed: moodHistoryFailed,
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
                        Image(systemName: "chevron.right").foregroundColor(.appTextMuted)
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
                        Image(systemName: "chevron.right").foregroundColor(.appTextMuted)
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
                        Image(systemName: "chevron.right").foregroundColor(.appTextMuted)
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
                        Image(systemName: "chevron.right").foregroundColor(.appTextMuted)
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
            Text("Auto-suivi — consulte un professionnel de santé mentale si tu en as besoin.")
                .font(.caption).foregroundColor(Color.appOnSurface.opacity(0.7))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.appCaption.weight(.medium)).foregroundColor(.appTextMuted)
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
    let initialLoaded: Bool
    let moodHistoryFailed: Bool
    let onLog: () -> Void

    private var todayEntry: MoodEntry? {
        let today = String(Date().ISO8601Format().prefix(10))
        return recentMoods.first { $0.date.hasPrefix(today) }
    }

    private var scoreColor: Color {
        guard let s = todayEntry?.score else { return Color.forge }
        return Color.moodColor(for: s)
    }

    private var isLoadingState: Bool { !initialLoaded }
    private var isErrorState:   Bool { initialLoaded && todayEntry == nil && moodHistoryFailed }

    var body: some View {
        Button(action: onLog) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(scoreColor.opacity(0.15)).frame(width: 48, height: 48)
                    if let entry = todayEntry {
                        Text("\(entry.score)")
                            .font(.system(size: 20, weight: .bold)).foregroundColor(scoreColor)
                    } else if isLoadingState {
                        Text("…")
                            .font(.system(size: 20, weight: .bold)).foregroundColor(Color.appOnSurface.opacity(0.4))
                    } else if isErrorState {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 20)).foregroundColor(Color.appOnSurface.opacity(0.4))
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
                    } else if isLoadingState {
                        Text("Chargement…")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.appOnSurface.opacity(0.6))
                        Text(" ")
                            .font(.caption)
                    } else if isErrorState {
                        Text("Indisponible")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.appOnSurface.opacity(0.6))
                        Text("Réessaie plus tard")
                            .font(.caption).foregroundColor(Color.appOnSurface.opacity(0.5))
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
        .disabled(isLoadingState || isErrorState)
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

// MARK: - Life Stress Breakdown Card (Équilibre enrichi — composantes + coverage + reco)

private struct LifeStressBreakdownCard: View {
    let lss: LifeStressScore?
    let initialLoaded: Bool
    let lssFailed: Bool

    private struct Item: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    private var items: [Item] {
        guard let c = lss?.components else { return [] }
        let raw: [(String, Double?)] = [
            ("Sommeil",                c.sleepQuality),
            ("Variabilité cardiaque",  c.hrvTrend),
            ("FC repos",               c.rhrTrend),
            ("Tension perçue",         c.subjectiveStress),
            ("Charge d'entraînement",  c.trainingFatigue),
        ]
        return raw.compactMap { name, v -> Item? in
            guard let v = v else { return nil }
            return Item(name: name, value: v)
        }
    }

    private var visible: [Item] {
        let sorted = items.sorted { $0.value < $1.value }
        switch sorted.count {
        case 0:      return []
        case 1, 2:   return sorted
        default:
            let mid = sorted.count / 2
            return [sorted.first!, sorted[mid], sorted.last!]
        }
    }

    private func componentColor(_ v: Double) -> Color {
        v >= 70 ? Color.appSuccess : v >= 40 ? Color.appWarning : Color.appDanger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMPOSANTES")
                .font(.appMicro.weight(.medium))
                .foregroundStyle(Color.appOnSurface.opacity(0.4))
                .tracking(2)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var content: some View {
        if !initialLoaded {
            Text("…")
                .font(.appLabel.weight(.medium))
                .foregroundStyle(Color.appOnSurface.opacity(0.4))
        } else if lss == nil && lssFailed {
            Text("Indisponible")
                .font(.appLabel.weight(.medium))
                .foregroundStyle(Color.appOnSurface.opacity(0.5))
        } else if let lss = lss {
            loadedContent(lss)
        } else {
            Text("Indisponible")
                .font(.appLabel.weight(.medium))
                .foregroundStyle(Color.appOnSurface.opacity(0.5))
        }
    }

    @ViewBuilder
    private func loadedContent(_ lss: LifeStressScore) -> some View {
        if visible.isEmpty {
            emptyDataContent
        } else {
            componentsList
            footer(lss)
        }
    }

    private var emptyDataContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connecte ta Watch ou logge ta récup pour activer ce signal.")
                .font(.appCaption)
                .foregroundStyle(Color.appOnSurface.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(destination: RecoveryView()) {
                HStack(spacing: 6) {
                    Text("Ouvrir Recovery")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    Image(systemName: "chevron.right")
                        .font(.appMicro.weight(.semibold))
                        .foregroundColor(.appTextMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.appInfo.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appInfo.opacity(0.25), lineWidth: 1))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
        }
    }

    private var componentsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(visible) { item in
                componentRow(item)
            }
        }
    }

    private func componentRow(_ item: Item) -> some View {
        let color = componentColor(item.value)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name)
                    .font(.appLabel.weight(.medium))
                    .foregroundStyle(Color.appOnSurface.opacity(0.85))
                Spacer()
                Text("\(Int(item.value))/100")
                    .font(.appLabel.weight(.medium))
                    .foregroundStyle(color)
            }
            segmentBar(value: item.value, color: color)
        }
    }

    private func segmentBar(value: Double, color: Color) -> some View {
        let filled = min(10, max(0, Int(value / 10)))
        return HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < filled ? color : Color.appTextMuted.opacity(0.18))
                    .frame(height: 6)
            }
        }
    }

    private func footer(_ lss: LifeStressScore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(coverageBadge(lss.dataCoverage))
                .font(.appMicro)
                .foregroundStyle(Color.appTextMuted)
            Text(footerMessage(lss))
                .font(.appCaption)
                .foregroundStyle(Color.appOnSurface.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func coverageBadge(_ coverage: Double) -> String {
        let pct = Int((coverage * 100).rounded())
        if coverage >= 0.8 { return "Basé sur \(pct) % de tes données" }
        if coverage >= 0.4 { return "Basé sur \(pct) % de tes données ⓘ" }
        return "Basé sur \(pct) % de tes données ⚠"
    }

    private func footerMessage(_ lss: LifeStressScore) -> String {
        if lss.dataCoverage < 0.4 {
            return "Ajoute des logs ou active la synchro Watch pour un signal plus complet."
        }
        if let first = lss.recommendations.first { return first }
        return "Équilibre stable, rien à ajuster."
    }
}
