import SwiftUI

struct DashboardView: View {
    @StateObject private var api = APIService.shared

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()

                if api.isLoading && api.dashboard == nil {
                    ProgressView()
                        .tint(.orange)
                } else if let dash = api.dashboard {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Header
                            HeaderView(dash: dash)

                            // Today card
                            TodayCardView(dash: dash)

                            // Heatmap 30j
                            HeatmapView(sessions: dash.sessions)

                            // Week grid
                            WeekGridView(schedule: dash.schedule, sessions: dash.sessions)

                            // Nutrition
                            NutritionSummaryView(totals: dash.nutritionTotals)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                } else if let err = api.error {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Connexion impossible")
                            .foregroundColor(.white)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Button("Réessayer") {
                            Task { await api.fetchDashboard() }
                        }
                        .foregroundColor(.orange)
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
        .task { await api.fetchDashboard() }
    }
}

// MARK: - Header
struct HeaderView: View {
    let dash: DashboardData

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: Date()).capitalized
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TRAINING")
                    .font(.system(size: 13, weight: .black))
                    .tracking(4)
                    .foregroundColor(.gray) +
                Text("OS")
                    .font(.system(size: 13, weight: .black))
                    .tracking(4)
                    .foregroundColor(.orange)
                Text(formattedDate)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SEMAINE \(dash.week)")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.gray)
                if dash.alreadyLoggedToday {
                    Label("Loggé", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Today Card
struct TodayCardView: View {
    let dash: DashboardData

    var todayColor: Color {
        switch dash.today {
        case "Upper A", "Upper B", "Lower": return .orange
        case "HIIT 1", "HIIT 2":           return .red
        case "Yoga":                        return .purple
        case "Recovery":                    return .green
        default:                            return .gray
        }
    }

    var todayIcon: String {
        switch dash.today {
        case "Upper A", "Upper B", "Lower": return "dumbbell.fill"
        case "HIIT 1", "HIIT 2":           return "figure.run"
        case "Yoga":                        return "figure.mind.and.body"
        case "Recovery":                    return "heart.fill"
        default:                            return "moon.fill"
        }
    }

    var exercises: [(String, String)] {
        guard let program = dash.fullProgram[dash.today] else { return [] }
        return program.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: todayIcon)
                    .foregroundColor(todayColor)
                    .font(.system(size: 16, weight: .semibold))
                Text("AUJOURD'HUI")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.gray)
                Spacer()
                Text(dash.today)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(todayColor)
            }

            Divider().background(Color.white.opacity(0.07))

            if exercises.isEmpty {
                Text("Repos / jour libre")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .italic()
            } else {
                ForEach(exercises, id: \.0) { ex, sets in
                    HStack {
                        Text(ex)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(sets)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        if let suggestion = dash.suggestions[ex],
                           let w = suggestion.weight {
                            Text("\(Int(w)) lbs")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(todayColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(todayColor.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            if !dash.alreadyLoggedToday {
                NavigationLink(destination: SeanceView()) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Logger la séance")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(todayColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(todayColor.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}

// MARK: - Heatmap
struct HeatmapView: View {
    let sessions: [String: SessionEntry]

    private var last30Days: [(String, Bool)] {
        (0..<30).reversed().map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let key = DateFormatter.isoDate.string(from: date)
            return (key, sessions[key] != nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("30 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                ForEach(last30Days, id: \.0) { _, hasSession in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(hasSession ? Color.orange : Color(hex: "191926"))
                        .frame(height: 22)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }
}

// MARK: - Week Grid
struct WeekGridView: View {
    let schedule: [String: String]
    let sessions: [String: SessionEntry]

    private let days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    private func dateForDay(_ index: Int) -> String {
        let calendar = Calendar(identifier: .iso8601)
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today)!
        let day = calendar.date(byAdding: .day, value: index, to: monday)!
        return DateFormatter.isoDate.string(from: day)
    }

    private func isToday(_ index: Int) -> Bool {
        let calendar = Calendar(identifier: .iso8601)
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        return index == daysSinceMonday
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CETTE SEMAINE")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let dayKey = String(i)
                    let seance = schedule[dayKey] ?? "Repos"
                    let dateStr = dateForDay(i)
                    let done = sessions[dateStr] != nil
                    let today = isToday(i)

                    VStack(spacing: 4) {
                        Text(days[i])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(today ? .orange : .gray)
                        Text(seanceShort(seance))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(seanceColor(seance))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        done ? seanceColor(seance).opacity(0.15) :
                        today ? Color.orange.opacity(0.08) :
                        Color(hex: "191926")
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(today ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }

    private func seanceShort(_ s: String) -> String {
        switch s {
        case "Upper A": return "UP A"
        case "Upper B": return "UP B"
        case "Lower":   return "LOW"
        case "HIIT 1":  return "HIIT"
        case "HIIT 2":  return "HIIT"
        case "Yoga":    return "YGA"
        case "Recovery":return "REC"
        default:        return "—"
        }
    }

    private func seanceColor(_ s: String) -> Color {
        switch s {
        case "Upper A", "Upper B", "Lower": return .orange
        case "HIIT 1", "HIIT 2":            return .red
        case "Yoga":                         return .purple
        case "Recovery":                     return .green
        default:                             return .gray
        }
    }
}

// MARK: - Nutrition Summary
struct NutritionSummaryView: View {
    let totals: NutritionTotals

    var body: some View {
        HStack(spacing: 0) {
            NutritionItem(value: Int(totals.calories ?? 0), label: "kcal", color: .orange)
            Divider().background(Color.white.opacity(0.07)).frame(height: 40)
            NutritionItem(value: Int(totals.protein ?? 0), label: "prot", color: .blue)
            Divider().background(Color.white.opacity(0.07)).frame(height: 40)
            NutritionItem(value: Int(totals.carbs ?? 0), label: "carbs", color: .yellow)
            Divider().background(Color.white.opacity(0.07)).frame(height: 40)
            NutritionItem(value: Int(totals.fat ?? 0), label: "lip", color: .pink)
        }
        .padding(.vertical, 12)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }
}

struct NutritionItem: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}
