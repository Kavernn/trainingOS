import SwiftUI
import Charts

// MARK: - Entry point

struct MentalAmeView: View {
    @StateObject private var spiritVM = SpiritViewModel()
    @State private var tab: MentalAmeTab = .mesures
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
                // Background transite entre les deux tabs
                Group {
                    if tab == .pratique {
                        Color.voidBg
                    } else {
                        AmbientBackground(color: .teal)
                    }
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: tab)

                VStack(spacing: 0) {
                    SignalDuJourHeader(lss: lss, recentMoods: recentMoods, tab: tab)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    MentalAmePillBar(tab: $tab)
                        .padding(.horizontal)
                        .padding(.bottom, 4)

                    ZStack {
                        if tab == .mesures {
                            MesuresTab(
                                summary: summary,
                                recentMoods: recentMoods,
                                moodDue: moodDue,
                                cachedEmotions: cachedEmotions,
                                disclaimerDismissed: $disclaimerDismissed,
                                showMoodSheet: $showMoodSheet
                            )
                            .transition(.opacity)
                        } else {
                            PratiqueTab(vm: spiritVM, lss: lss, recentMoods: recentMoods)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: tab)
                }
            }
            .navigationTitle("Mental & Âme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if tab == .pratique {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { SpiritSettingsView(vm: spiritVM) } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(Color.moonlight.opacity(0.4))
                                .font(.system(size: 14))
                        }
                    }
                }
            }
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
        await spiritVM.loadSummary()
    }
}

// MARK: - Tab enum

enum MentalAmeTab { case mesures, pratique }

// MARK: - Pill bar

private struct MentalAmePillBar: View {
    @Binding var tab: MentalAmeTab

    var body: some View {
        HStack(spacing: 2) {
            pill("Mesures", icon: "chart.bar.fill", t: .mesures)
            pill("Pratique", icon: "moon.fill",     t: .pratique)
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    private func pill(_ label: String, icon: String, t: MentalAmeTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { tab = t }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.appLabel)
            }
            .foregroundStyle(tab == t
                ? (t == .mesures ? Color.teal : Color.moonlight)
                : Color.white.opacity(0.35)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                tab == t ? Color.white.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Signal du jour header (toujours visible)

private struct SignalDuJourHeader: View {
    let lss: LifeStressScore?
    let recentMoods: [MoodEntry]
    let tab: MentalAmeTab

    private var todayMood: MoodEntry? {
        let today = String(Date().ISO8601Format().prefix(10))
        return recentMoods.first { $0.date.hasPrefix(today) }
    }

    private var lssColor: Color {
        guard let s = lss?.score else { return .gray }
        return s >= 70 ? .green : s >= 40 ? .yellow : .red
    }

    private var lssLabel: String {
        guard let s = lss?.score else { return "—" }
        return s >= 70 ? "Équilibre" : s >= 40 ? "Vigilance" : "Stress élevé"
    }

    private var moodColor: Color {
        guard let s = todayMood?.score else { return .gray }
        return s >= 8 ? .green : s >= 5 ? .yellow : .red
    }

    private var isVoid: Bool { tab == .pratique }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ÉQUILIBRE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(isVoid ? Color.moonlight.opacity(0.3) : Color.white.opacity(0.4))
                    .tracking(2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(lss.map { "\($0.score)" } ?? "—")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(lssColor)
                    if lss != nil {
                        Text("/ 100")
                            .font(.appMicro.weight(.light))
                            .foregroundStyle(isVoid ? Color.moonlight.opacity(0.3) : Color.white.opacity(0.4))
                    }
                }
                Text(lssLabel)
                    .font(.appMicro.weight(.medium))
                    .foregroundStyle(lssColor.opacity(0.8))
                Text("Sommeil · HRV · Fatigue")
                    .font(.system(size: 8, weight: .light))
                    .foregroundStyle(isVoid ? Color.moonlight.opacity(0.2) : Color.white.opacity(0.25))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(isVoid ? Color.moonlight.opacity(0.08) : Color.white.opacity(0.1))
                .frame(width: 0.5)
                .padding(.vertical, 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text("HUMEUR")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(isVoid ? Color.moonlight.opacity(0.3) : Color.white.opacity(0.4))
                    .tracking(2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(todayMood.map { "\($0.score)" } ?? "—")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(moodColor)
                    if todayMood != nil {
                        Text("/ 10")
                            .font(.appMicro.weight(.light))
                            .foregroundStyle(isVoid ? Color.moonlight.opacity(0.3) : Color.white.opacity(0.4))
                    }
                }
                Text(todayMood != nil ? "Aujourd'hui" : "Non loggé")
                    .font(.appMicro.weight(.medium))
                    .foregroundStyle(todayMood != nil ? moodColor.opacity(0.8) : Color.gray.opacity(0.5))
                Text("Humeur subjective /10")
                    .font(.system(size: 8, weight: .light))
                    .foregroundStyle(isVoid ? Color.moonlight.opacity(0.2) : Color.white.opacity(0.25))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(isVoid ? Color.moonlight.opacity(0.04) : Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isVoid ? Color.moonlight.opacity(0.08) : Color.white.opacity(0.08),
                            lineWidth: 0.5
                        )
                }
        }
        .animation(.easeInOut(duration: 0.4), value: tab)
    }
}

// MARK: - Mesures tab

private struct MesuresTab: View {
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
                            .font(.title2).foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stress & PSS")
                                .font(.headline).foregroundColor(.white)
                            Text(stressSubtitle)
                                .font(.caption).foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.4))
                    }
                    .padding(14)
                    .glassCardAccent(.purple)
                    .padding(.horizontal)
                }
                .appearAnimation(delay: 0.06)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    NavigationLink { MoodTrackerView() } label: {
                        MHMenuCard(icon: "face.smiling.fill", color: .yellow,
                                   title: "Humeur", subtitle: moodSubtitle)
                    }
                    NavigationLink { SelfCareView() } label: {
                        MHMenuCard(icon: "heart.fill", color: .pink,
                                   title: "Self-Care", subtitle: selfCareSubtitle)
                    }
                    NavigationLink { JournalView() } label: {
                        MHMenuCard(icon: "book.pages.fill", color: .teal,
                                   title: "Journal", subtitle: "Réflexion guidée IA")
                    }
                }
                .padding(.horizontal)
                .appearAnimation(delay: 0.07)

                NavigationLink { MentalHealthDashboardView() } label: {
                    HStack {
                        Label("Résumé & insights", systemImage: "chart.bar.fill")
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.4))
                    }
                    .padding()
                    .glassCard(color: .teal, intensity: 0.08)
                    .padding(.horizontal)
                }
                .appearAnimation(delay: 0.09)

                NavigationLink { CrisisResourcesView() } label: {
                    HStack {
                        Image(systemName: "phone.fill").foregroundColor(.red)
                        Text("Ressources en cas de crise")
                            .foregroundColor(.red).fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.4))
                    }
                    .padding()
                    .glassCard(color: .red, intensity: 0.06)
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

    private var selfCareSubtitle: String {
        if let rate = summary?.selfCareRate { return "\(Int(rate * 100))% complété" }
        return "Habitudes"
    }
}

// MARK: - Pratique tab (The Void intégré)

private struct PratiqueTab: View {
    @ObservedObject var vm: SpiritViewModel
    let lss: LifeStressScore?
    let recentMoods: [MoodEntry]
    @State private var spiritTab: SpiritTab = .breath

    private var hint: String? {
        if let score = lss?.score, score < 40 {
            return "Stress élevé — Calm Storm recommandé"
        }
        let recent = recentMoods.prefix(3).map(\.score)
        if !recent.isEmpty {
            let avg = Double(recent.reduce(0, +)) / Double(recent.count)
            if avg < 5 { return "Humeur basse ces derniers jours — le journal peut aider" }
        }
        if !vm.journalStubs.isEmpty {
            let today = String(Date().ISO8601Format().prefix(10))
            if !vm.journalStubs.contains(where: { $0.date == today }) {
                return "Journal non écrit aujourd'hui"
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let h = hint {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.appCaption.weight(.light))
                        .foregroundStyle(Color.moonlight.opacity(0.5))
                    Text(h)
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(Color.moonlight.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            // Tab bar Spirit (inchangé visuellement)
            HStack(spacing: 0) {
                ForEach(SpiritTab.allCases, id: \.self) { t in
                    Button { spiritTab = t } label: {
                        VStack(spacing: 2) {
                            Image(systemName: t.icon)
                                .font(.system(size: 14, weight: spiritTab == t ? .medium : .light))
                            Text(t.label)
                                .font(.system(size: 10, weight: spiritTab == t ? .medium : .light))
                            Text(t.subtitle)
                                .font(.system(size: 8, weight: .light))
                                .opacity(0.6)
                        }
                        .foregroundStyle(spiritTab == t ? Color.moonlight : Color.moonlight.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if spiritTab == t {
                                Rectangle()
                                    .fill(Color.moonlight.opacity(0.4))
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
            }
            .background(Color.voidBg)

            Group {
                switch spiritTab {
                case .breath:   SpiritBreathTabView(vm: vm)
                case .meditate: SpiritMeditationTabView(vm: vm)
                case .journal:  SpiritJournalGateView(vm: vm)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: spiritTab)
        }
    }
}

// MARK: - Composants Mesures

private struct DisclaimerBanner: View {
    let onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundColor(.blue)
            Text("Cette section est un outil d'auto-suivi. Elle ne remplace pas un professionnel de santé mentale.")
                .font(.caption).foregroundColor(.white.opacity(0.7))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.appCaption.weight(.medium)).foregroundColor(.gray)
            }
        }
        .padding(12)
        .glassCard(color: .blue, intensity: 0.06)
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
        guard let s = todayEntry?.score else { return .yellow }
        return s >= 8 ? .green : s >= 5 ? .yellow : .red
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
                            .font(.system(size: 22)).foregroundColor(.yellow)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let entry = todayEntry {
                        Text("Humeur loggée")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        if !entry.emotions.isEmpty {
                            Text(entry.emotions.prefix(3).joined(separator: " · "))
                                .font(.caption).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                        } else {
                            Text("Appuie pour modifier")
                                .font(.caption).foregroundColor(.white.opacity(0.6))
                        }
                    } else {
                        Text(moodDue?.isDue == true ? "Note ton humeur" : "Comment tu te sens ?")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        Text("30 secondes · émotions + score")
                            .font(.caption).foregroundColor(.white.opacity(0.6))
                    }
                }
                Spacer()
                Image(systemName: todayEntry == nil ? "plus.circle.fill" : "pencil.circle")
                    .font(.system(size: 22))
                    .foregroundColor(todayEntry == nil ? .yellow : .white.opacity(0.4))
            }
            .padding(14)
            .glassCard(color: todayEntry != nil ? scoreColor : .yellow, intensity: 0.08)
        }
        .buttonStyle(SpringButtonStyle())
        .padding(.horizontal)
    }
}

private struct MoodSparklineCard: View {
    let entries: [MoodEntry]

    private var last7: [MoodEntry] { Array(entries.prefix(7).reversed()) }

    private func color(for score: Int) -> Color {
        score >= 8 ? .green : score >= 5 ? .yellow : .red
    }

    var body: some View {
        let avg = last7.isEmpty ? 5.0 : Double(last7.map(\.score).reduce(0, +)) / Double(last7.count)
        let lineColor = color(for: Int(avg.rounded()))

        VStack(alignment: .leading, spacing: 10) {
            Text("Humeur — 7 derniers jours")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
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
                            .font(.appMicro).foregroundColor(.white.opacity(0.65))
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

// MARK: - MHMenuCard (partagé avec Dashboard)

struct MHMenuCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text(title).font(.headline).foregroundColor(.white)
            Text(subtitle).font(.caption).foregroundColor(.white.opacity(0.6)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCardAccent(color)
    }
}
