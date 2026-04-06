import SwiftUI

struct XPView: View {
    @StateObject private var api = APIService.shared
    @State private var hiitLog: [HIITEntry] = []
    @State private var weights: [String: WeightData] = [:]
    @State private var isLoading = true

    var totalSessions: Int { (api.dashboard?.sessions.count ?? 0) + hiitLog.count }
    var totalExercices: Int { weights.filter { $0.value.history?.isEmpty == false }.count }

    var xp: Int { totalSessions * 100 + totalExercices * 50 }
    var level: Int { max(1, xp / 1000 + 1) }
    var xpInLevel: Int { xp % 1000 }
    var xpToNextLevel: Int { 1000 }

    var levelTitle: String {
        switch level {
        case 1: return "Débutant"
        case 2: return "Athlète"
        case 3: return "Warrior"
        case 4: return "Élite"
        case 5...: return "Légende"
        default: return "Débutant"
        }
    }

    var badges: [(String, String, Color, Bool)] {
        [
            ("dumbbell.fill",       "Premier lift",     .orange,  totalExercices >= 1),
            ("flame.fill",          "10 séances",       .red,     totalSessions >= 10),
            ("star.fill",           "25 séances",       .yellow,  totalSessions >= 25),
            ("bolt.fill",           "Premier HIIT",     .red,     !hiitLog.isEmpty),
            ("chart.line.uptrend.xyaxis", "50 séances", .purple,  totalSessions >= 50),
            ("crown.fill",          "100 séances",      .yellow,  totalSessions >= 100),
            ("figure.run",          "10 HIIT",          .orange,  hiitLog.count >= 10),
            ("trophy.fill",         "Niveau 5",         .yellow,  level >= 5),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .yellow)
                if isLoading {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // Level card
                            VStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.15))
                                        .frame(width: 100, height: 100)
                                    VStack(spacing: 2) {
                                        Text("LVL")
                                            .font(.system(size: 10, weight: .bold))
                                            .tracking(2)
                                            .foregroundColor(.orange)
                                        Text("\(level)")
                                            .font(.system(size: 44, weight: .black))
                                            .foregroundColor(.orange)
                                    }
                                }

                                Text(levelTitle)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)

                                VStack(spacing: 6) {
                                    HStack {
                                        Text("\(xp) XP total")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                        Spacer()
                                        Text("\(xpInLevel) / \(xpToNextLevel) XP")
                                            .font(.system(size: 12))
                                            .foregroundColor(.orange)
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color(hex: "191926")).frame(height: 8)
                                            Capsule()
                                                .fill(
                                                    LinearGradient(colors: [.orange, .red],
                                                                   startPoint: .leading, endPoint: .trailing)
                                                )
                                                .frame(width: geo.size.width * Double(xpInLevel) / Double(xpToNextLevel), height: 8)
                                        }
                                    }
                                    .frame(height: 8)
                                }
                                .padding(.horizontal, 8)
                            }
                            .padding(20)
                            .glassCardAccent(.orange)
                            .cornerRadius(20)
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.05)

                            // Stats
                            HStack(spacing: 12) {
                                KPICard(value: "\(totalSessions)", label: "Séances", color: .orange)
                                KPICard(value: "\(hiitLog.count)", label: "HIIT", color: .red)
                                KPICard(value: "\(totalExercices)", label: "Exercices", color: .blue)
                            }
                            .padding(.horizontal, 16)

                            // Badges
                            VStack(alignment: .leading, spacing: 12) {
                                Text("BADGES")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 16)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(badges, id: \.0) { icon, label, color, unlocked in
                                        BadgeCell(icon: icon, label: label, color: color, unlocked: unlocked)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("XP & Niveau")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        if api.dashboard == nil { await api.fetchDashboard() }
        hiitLog = (try? await APIService.shared.fetchHIITData()) ?? []
        weights = (try? await APIService.shared.fetchWeights()) ?? [:]
        isLoading = false
    }
}

struct BadgeCell: View {
    let icon: String
    let label: String
    let color: Color
    let unlocked: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(unlocked ? color.opacity(0.15) : Color(hex: "191926"))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(unlocked ? color : .gray.opacity(0.3))
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(unlocked ? .white : .gray.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .scaleEffect(unlocked ? 1.0 : 0.9)
        .opacity(unlocked ? 1.0 : 0.45)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: unlocked)
    }
}
