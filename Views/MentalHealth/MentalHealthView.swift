import SwiftUI

struct MentalHealthView: View {
    @State private var moodDue: MoodDueStatus?
    @State private var summary: MentalHealthSummary?
    @State private var isLoading = true
    @State private var showMoodSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .mint)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {

                        // Avertissement médical
                        DisclaimerBanner()
                            .appearAnimation(delay: 0)

                        // Nudge mood si non loggué
                        if moodDue?.isDue == true {
                            MoodNudgeBanner { showMoodSheet = true }
                                .appearAnimation(delay: 0.03)
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
                MoodLogSheet()
            }
            .task { await loadData() }
        }
    }

    private func loadData() async {
        async let due     = try? APIService.shared.checkMoodDue()
        async let summary = try? APIService.shared.fetchMentalHealthSummary(days: 7)
        let (d, s) = await (due, summary)
        await MainActor.run {
            moodDue       = d
            self.summary  = s
            isLoading     = false
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
}

// MARK: - Composants

private struct DisclaimerBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
            Text("Cette section est un outil d'auto-suivi. Elle ne remplace pas un professionnel de santé mentale.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(12)
        .glassCard(color: .blue, intensity: 0.06)
        .padding(.horizontal)
    }
}

private struct MoodNudgeBanner: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundColor(.yellow)
                Text("Prends 30 secondes pour noter ton humeur")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.yellow)
            }
            .padding(12)
            .glassCard(color: .yellow, intensity: 0.08)
        }
        .buttonStyle(SpringButtonStyle())
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
