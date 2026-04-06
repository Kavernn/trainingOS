import SwiftUI
import Charts

struct MentalHealthView: View {
    @State private var moodDue: MoodDueStatus?
    @State private var summary: MentalHealthSummary?
    @State private var recentMoods: [MoodEntry] = []
    @State private var cachedEmotions: [MoodEmotion] = []
    @State private var isLoading = true
    @State private var showMoodSheet = false
    @AppStorage("mh_disclaimer_dismissed") private var disclaimerDismissed = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .mint)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {

                        // Avertissement médical
                        if !disclaimerDismissed {
                            DisclaimerBanner(onDismiss: { disclaimerDismissed = true })
                                .appearAnimation(delay: 0)
                        }

                        // Fix 3 — Mood logger permanent (1-tap, toujours visible)
                        MoodQuickLogCard(
                            moodDue: moodDue,
                            recentMoods: recentMoods,
                            cachedEmotions: cachedEmotions,
                            onLog: { showMoodSheet = true }
                        )
                        .appearAnimation(delay: 0.03)

                        // Fix 4 — Sparkline 7 jours (visible seulement si données)
                        if recentMoods.count >= 2 {
                            MoodSparklineCard(entries: recentMoods)
                                .appearAnimation(delay: 0.05)
                        }

                        // Cartes de navigation
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            NavigationLink { MoodTrackerView() } label: {
                                MHMenuCard(icon: "face.smiling.fill", color: .yellow, title: "Humeur", subtitle: moodSubtitle)
                            }
                            NavigationLink { JournalView() } label: {
                                MHMenuCard(icon: "book.fill", color: .indigo, title: "Journal", subtitle: journalSubtitle)
                            }
                            NavigationLink { BreathworkView() } label: {
                                MHMenuCard(icon: "lungs.fill", color: .green, title: "Respiration", subtitle: bwSubtitle)
                            }
                            NavigationLink { SelfCareView() } label: {
                                MHMenuCard(icon: "heart.fill", color: .pink, title: "Self-Care", subtitle: selfCareSubtitle)
                            }
                        }
                        .padding(.horizontal)
                        .appearAnimation(delay: 0.06)

                        // Stress card full-width
                        NavigationLink { PSSView() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "brain.head.profile")
                                    .font(.title2).foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Stress")
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
                        .appearAnimation(delay: 0.075)

                        // Dashboard résumé
                        NavigationLink { MentalHealthDashboardView() } label: {
                            HStack {
                                Label("Résumé de la semaine", systemImage: "chart.bar.fill")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .padding()
                            .glassCard(color: .mint, intensity: 0.08)
                            .padding(.horizontal)
                        }
                        .appearAnimation(delay: 0.09)

                        // Ressources de crise
                        NavigationLink { CrisisResourcesView() } label: {
                            HStack {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.red)
                                Text("Ressources en cas de crise")
                                    .foregroundColor(.red)
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .padding()
                            .glassCard(color: .red, intensity: 0.06)
                            .padding(.horizontal)
                        }
                        .appearAnimation(delay: 0.12)

                        Spacer(minLength: 40)
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Santé Mentale")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showMoodSheet, onDismiss: { Task { await loadData() } }) {
                MoodLogSheet(emotions: cachedEmotions)
            }
            .task { await loadData() }
        }
    }

    private func loadData() async {
        async let due      = try? APIService.shared.checkMoodDue()
        async let summary  = try? APIService.shared.fetchMentalHealthSummary(days: 7)
        async let moods    = try? APIService.shared.fetchMoodHistory(days: 14, limit: 7)
        async let emotions = try? APIService.shared.fetchMoodEmotions()
        let (d, s, m, e) = await (due, summary, moods, emotions)
        await MainActor.run {
            moodDue          = d
            self.summary     = s
            if let items = m?.items { recentMoods = items }
            if let list  = e, !list.isEmpty { cachedEmotions = list }
            isLoading        = false
        }
    }

    private var moodSubtitle: String {
        if let avg = summary?.avgMood {
            return String(format: "Moy. %.1f/10", avg)
        }
        return moodDue?.isDue == true ? "À loguer aujourd'hui" : "À jour"
    }

    private var journalSubtitle: String {
        if let n = summary?.journalEntries, n > 0 {
            return "\(n) entrée\(n > 1 ? "s" : "") cette semaine"
        }
        return "Écrire"
    }

    private var bwSubtitle: String {
        if let n = summary?.breathworkSessions, n > 0 {
            return "\(n) session\(n > 1 ? "s" : "") cette semaine"
        }
        return "Commencer"
    }

    private var selfCareSubtitle: String {
        if let rate = summary?.selfCareRate {
            return "\(Int(rate * 100))% complété"
        }
        return "Habitudes"
    }

    private var stressSubtitle: String {
        if let score = summary?.pssScore, let cat = summary?.pssCategory {
            let label = cat == "low" ? "Stress faible" : cat == "moderate" ? "Stress modéré" : "Stress élevé"
            return "Dernier PSS : \(score)/40 · \(label)"
        }
        return "Bilan mensuel + score automatique"
    }
}

// MARK: - Composants

private struct DisclaimerBanner: View {
    let onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundColor(.blue)
            Text("Cette section est un outil d'auto-suivi. Elle ne remplace pas un professionnel de santé mentale.")
                .font(.caption).foregroundColor(.white.opacity(0.7))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundColor(.gray)
            }
        }
        .padding(12)
        .glassCard(color: .blue, intensity: 0.06)
        .padding(.horizontal)
    }
}

// MARK: - Fix 3: Mood Quick-Log Card (permanent, 1-tap)

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
        if s >= 8 { return .green }
        if s >= 5 { return .yellow }
        return .red
    }

    var body: some View {
        Button(action: onLog) {
            HStack(spacing: 14) {
                // Score ring ou icône
                ZStack {
                    Circle().fill(scoreColor.opacity(0.15)).frame(width: 48, height: 48)
                    if let entry = todayEntry {
                        Text("\(entry.score)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(scoreColor)
                    } else {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 22))
                            .foregroundColor(.yellow)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let entry = todayEntry {
                        Text("Humeur loggée")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        if !entry.emotions.isEmpty {
                            Text(entry.emotions.prefix(3).joined(separator: " · "))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        } else {
                            Text("Appuie pour modifier")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    } else {
                        Text(moodDue?.isDue == true ? "Note ton humeur" : "Comment tu te sens ?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("30 secondes · émotions + score")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
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

// MARK: - Fix 4: Mood Sparkline 7 jours

private struct MoodSparklineCard: View {
    let entries: [MoodEntry]

    private var last7: [MoodEntry] {
        Array(entries.prefix(7).reversed())
    }

    private func color(for score: Int) -> Color {
        if score >= 8 { return .green }
        if score >= 5 { return .yellow }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Humeur — 7 derniers jours")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 16)

            Chart(last7) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Score", entry.score)
                )
                .foregroundStyle(Color.yellow.opacity(0.7))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", entry.date),
                    y: .value("Score", entry.score)
                )
                .foregroundStyle(color(for: entry.score))
                .symbolSize(60)
            }
            .chartYScale(domain: 1...10)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [1, 5, 10]) { v in
                    AxisValueLabel {
                        Text("\(v.as(Int.self) ?? 0)")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }
            .frame(height: 72)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .glassCard(color: .yellow, intensity: 0.05)
        .padding(.horizontal)
    }
}

struct MHMenuCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCardAccent(color)
    }
}
