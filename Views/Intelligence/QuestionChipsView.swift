import SwiftUI

struct QuestionChipsView: View {
    let lssData: LifeStressScore?
    let dashboard: DashboardData?
    let nutritionHistory: [NutritionDayHistory]
    var onTap: (String) -> Void

    private var chips: [String] {
        var result: [String] = []

        if let dash = dashboard {
            let dayAbbrev = String(dash.today.prefix(3))
            if let plan = dash.schedule[dayAbbrev],
               plan.lowercased() != "rest", !plan.isEmpty,
               !dash.alreadyLoggedToday {
                result.append("Prépare-moi pour ma séance")
                result.append("Quel volume aujourd'hui ?")
            }
        }

        if let lss = lssData {
            if lss.flags.hrvDrop || lss.flags.sleepDeprivation || lss.flags.trainingOverload || lss.score < 40 {
                result.append("Comment récupérer plus vite ?")
                result.append("Dois-je m'entraîner aujourd'hui ?")
            }
        }

        if let yest = yesterdayEntry(from: nutritionHistory),
           let target = dashboard?.nutritionSettings?.proteines, target > 0,
           yest.proteines < target * 0.80 {
            result.append("Comment atteindre mes protéines ?")
            result.append("Suggère un repas riche en protéines")
        }

        let defaults = ["Analyse ma semaine", "Que faire aujourd'hui ?",
                        "Optimise ma récupération", "Comment progresser plus vite ?"]
        for d in defaults {
            if result.count >= 6 { break }
            if !result.contains(d) { result.append(d) }
        }

        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button { onTap(chip) } label: {
                        Text(chip)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.purple.opacity(0.9))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Color.purple.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule()
                                .stroke(Color.purple.opacity(0.28), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(Color.appBg)
    }
}

func yesterdayEntry(from history: [NutritionDayHistory]) -> NutritionDayHistory? {
    guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return nil }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    let yStr = fmt.string(from: yesterday)
    return history.first { $0.date == yStr }
}
