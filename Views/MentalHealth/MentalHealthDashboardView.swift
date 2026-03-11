import SwiftUI

struct MentalHealthDashboardView: View {
    @State private var summary7: MentalHealthSummary?
    @State private var summary30: MentalHealthSummary?
    @State private var selectedDays = 7
    @State private var isLoading = true

    private var current: MentalHealthSummary? {
        selectedDays == 7 ? summary7 : summary30
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: .purple)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Picker("Période", selection: $selectedDays) {
                        Text("7 jours").tag(7)
                        Text("30 jours").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedDays) { _ in
                        Task { await loadMissing() }
                    }

                    if isLoading {
                        ProgressView().tint(.white)
                            .padding(.top, 60)
                    } else if let s = current {
                        dashboardContent(s)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
        }
        .navigationTitle("Résumé mental")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
    }

    @ViewBuilder
    private func dashboardContent(_ s: MentalHealthSummary) -> some View {

        // KPI row
        HStack(spacing: 0) {
            MHKPICell(label: "Humeur moy.", value: s.avgMood.map { String(format: "%.1f", $0) } ?? "–",
                      unit: "/10", color: moodColor(s.avgMood))
            Divider().background(Color.white.opacity(0.1))
            MHKPICell(label: "Séances BW", value: "\(s.breathworkSessions)",
                      unit: "sessions", color: .green)
            Divider().background(Color.white.opacity(0.1))
            MHKPICell(label: "Self-Care", value: "\(Int(s.selfCareRate * 100))",
                      unit: "%", color: s.selfCareRate >= 0.7 ? .green : .orange)
            Divider().background(Color.white.opacity(0.1))
            MHKPICell(label: "Journal", value: "\(s.journalEntries)",
                      unit: "entrées", color: .indigo)
        }
        .frame(height: 72)
        .glassCard()
        .padding(.horizontal)

        // Mood chart
        if !s.moodHistory.isEmpty {
            MHSectionCard(title: "Tendance de l'humeur", icon: "chart.line.uptrend.xyaxis") {
                MoodSparklineChart(entries: Array(s.moodHistory.prefix(14).reversed()))
                    .frame(height: 80)
            }
        }

        // Top émotions
        if !s.topEmotions.isEmpty {
            MHSectionCard(title: "Émotions fréquentes", icon: "heart.text.square.fill") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(s.topEmotions, id: \.self) { em in
                            Text(em)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.yellow.opacity(0.15))
                                .cornerRadius(20)
                        }
                    }
                }
            }
        }

        // Insights
        if !s.insights.isEmpty {
            MHSectionCard(title: "Insights", icon: "lightbulb.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(s.insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkle")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            Text(insight)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }

        // Corrélations
        if !s.correlations.isEmpty {
            MHSectionCard(title: "Corrélations", icon: "arrow.triangle.branch") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(s.correlations, id: \.self) { corr in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "link")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text(corr)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }

        // Streaks
        if !s.topStreaks.isEmpty {
            MHSectionCard(title: "Top Streaks", icon: "flame.fill") {
                VStack(spacing: 8) {
                    ForEach(s.topStreaks) { streak in
                        HStack {
                            Image(systemName: streak.habitIcon)
                                .foregroundColor(.orange)
                                .frame(width: 20)
                            Text(streak.habitName)
                                .font(.subheadline)
                            Spacer()
                            Text("🔥 \(streak.currentStreak) j")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }

        // PSS
        if let pssScore = s.pssScore, let cat = s.pssCategory {
            MHSectionCard(title: "Stress PSS récent", icon: "brain.head.profile") {
                HStack {
                    Text("Score \(pssScore)")
                        .font(.title2.bold())
                    Spacer()
                    Text(cat.capitalized)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(pssColor(cat))
                        .cornerRadius(8)
                }
            }
        }
    }

    private func moodColor(_ avg: Double?) -> Color {
        guard let avg else { return .gray }
        if avg >= 7 { return .green }
        if avg >= 5 { return .yellow }
        return .red
    }

    private func pssColor(_ cat: String) -> Color {
        switch cat {
        case "low":    return .green
        case "high":   return .red
        default:       return .orange
        }
    }

    private func loadData() async {
        let s7 = try? await APIService.shared.fetchMentalHealthSummary(days: 7)
        await MainActor.run {
            summary7  = s7
            isLoading = false
        }
    }

    private func loadMissing() async {
        if selectedDays == 30 && summary30 == nil {
            let s30 = try? await APIService.shared.fetchMentalHealthSummary(days: 30)
            await MainActor.run { summary30 = s30 }
        }
    }
}

// MARK: - Shared components

private struct MHKPICell: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(color)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sparkline Chart

private struct MoodSparklineChart: View {
    let entries: [MoodEntry]

    private func color(for score: Int) -> Color {
        if score >= 8 { return .green }
        if score >= 5 { return .yellow }
        return .red
    }

    var body: some View {
        let maxScore = entries.map(\.score).max().map { Double($0) } ?? 10
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(entries.enumerated()), id: \.0) { i, entry in
                let pct = maxScore > 0 ? Double(entry.score) / maxScore : 0
                let isLast = i == entries.count - 1
                VStack(spacing: 2) {
                    if isLast {
                        Text("\(entry.score)")
                            .font(.system(size: 8))
                            .foregroundColor(color(for: entry.score))
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: entry.score).opacity(isLast ? 1.0 : 0.5))
                        .frame(height: max(CGFloat(pct) * 60, 4))
                    Text(String(entry.date.suffix(5)))
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct MHSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.white)
            content()
        }
        .padding(16)
        .glassCard()
        .padding(.horizontal)
    }
}
