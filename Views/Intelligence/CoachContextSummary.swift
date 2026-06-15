import SwiftUI

private func yesterdayEntry(from history: [NutritionDayHistory]) -> NutritionDayHistory? {
    guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return nil }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    let yStr = fmt.string(from: yesterday)
    return history.first { $0.date == yStr }
}

struct CoachContextSummary: View {
    let lssData: LifeStressScore?
    let dashboard: DashboardData?
    let nutritionHistory: [NutritionDayHistory]

    private struct Bullet: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let color: Color
    }

    private var bullets: [Bullet] {
        var result: [Bullet] = []

        if let dash = dashboard {
            let dayAbbrev = String(dash.today.prefix(3))
            if let plan = dash.schedule[dayAbbrev], plan.lowercased() != "rest", !plan.isEmpty {
                if dash.alreadyLoggedToday {
                    result.append(Bullet(icon: "checkmark.circle.fill",
                                         text: "Séance \(plan) complétée aujourd'hui",
                                         color: .statusGreen))
                } else {
                    result.append(Bullet(icon: "dumbbell.fill",
                                         text: "Séance \(plan) prévue aujourd'hui",
                                         color: .statusPurple))
                }
            }
        }

        if let lss = lssData {
            let isAlert = lss.flags.hrvDrop || lss.flags.sleepDeprivation || lss.flags.trainingOverload
            if isAlert {
                let detail: String
                if lss.flags.hrvDrop { detail = "HRV en baisse" }
                else if lss.flags.sleepDeprivation { detail = "sommeil insuffisant" }
                else { detail = "charge élevée" }
                result.append(Bullet(icon: "exclamationmark.triangle.fill",
                                     text: "Récupération \(Int(lss.score))/100 — \(detail)",
                                     color: lss.score < 40 ? .statusRed : Color.forge))
            } else {
                result.append(Bullet(icon: "checkmark.shield.fill",
                                     text: "Récupération \(Int(lss.score))/100 — dans la norme",
                                     color: .statusGreen))
            }
        }

        if let yest = yesterdayEntry(from: nutritionHistory),
           let target = dashboard?.nutritionSettings?.proteines, target > 0 {
            let prot = yest.proteines
            if prot < target * 0.90 {
                result.append(Bullet(icon: "fork.knife",
                                     text: "Hier : \(Int(prot))g protéines sur \(Int(target))g objectif",
                                     color: prot < target * 0.70 ? .statusRed : Color.forge))
            } else {
                result.append(Bullet(icon: "fork.knife",
                                     text: "Nutrition d'hier sur cible",
                                     color: .statusGreen))
            }
        }

        return Array(result.prefix(3))
    }

    var body: some View {
        let b = bullets
        if !b.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ce que je sais de toi aujourd'hui")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color(white: 0.40))
                    .tracking(0.3)
                    .padding(.bottom, 9)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(b) { bullet in
                        HStack(spacing: 8) {
                            Image(systemName: bullet.icon)
                                .font(.appCaption)
                                .foregroundColor(bullet.color.opacity(0.8))
                                .frame(width: 16, alignment: .center)
                            Text(bullet.text)
                                .font(.appLabel)
                                .foregroundColor(Color(white: 0.60))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }

                Rectangle()
                    .fill(Color.appSurfaceInset)
                    .frame(height: 0.5)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.appSurfaceInset)
            .cornerRadius(10)
        }
    }
}
