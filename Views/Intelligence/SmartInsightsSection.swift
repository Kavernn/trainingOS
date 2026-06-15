import SwiftUI

struct SmartInsight {
    let icon: String
    let color: Color
    let title: String
    let detail: String
}

struct SmartInsightsSection: View {
    let dash: DashboardData
    let weightsData: [String: WeightData]
    let sessionsData: [String: SessionEntry]
    let recovery: RecoveryEntry?
    let recoveryLog: [RecoveryEntry]
    let nutritionHistory: [NutritionDayHistory]

    private var ago14: String {
        let base = Date().timeIntervalSince1970
        return DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: base - 14 * 86400))
    }

    private var insights: [SmartInsight] {
        var result: [SmartInsight] = []
        let ns = dash.nutritionSettings

        if result.count < 2, let protTarget = ns?.proteines, protTarget > 0, nutritionHistory.count >= 3 {
            let recent = Array(nutritionHistory.prefix(3))
            let avgProt = recent.map { $0.proteines }.reduce(0, +) / Double(recent.count)
            if avgProt < protTarget * 0.80 {
                let sessions14d = sessionsData.filter { $0.key >= ago14 }.count
                if sessions14d >= 4 {
                    result.append(SmartInsight(
                        icon: "fork.knife",
                        color: .statusYellow,
                        title: "Protéines insuffisantes",
                        detail: "Moy. \(Int(avgProt))g/j vs \(Int(protTarget))g · \(sessions14d) séances en 14j"
                    ))
                } else {
                    result.append(SmartInsight(
                        icon: "circle.hexagongrid.fill",
                        color: .statusCyan,
                        title: "Protéines en dessous",
                        detail: "Moy. \(Int(avgProt))g/j vs \(Int(protTarget))g objectif sur 3j"
                    ))
                }
            }
        }

        if result.count < 2, let calTarget = ns?.calories, calTarget > 0, nutritionHistory.count >= 5 {
            let avgCal = Array(nutritionHistory.prefix(7)).map { $0.calories }.reduce(0, +) / Double(min(nutritionHistory.count, 7))
            let calRatio = avgCal / calTarget
            if calRatio < 0.87 {
                let hrvVals = recoveryLog.compactMap { $0.hrv }
                if hrvVals.count >= 10 {
                    let recent7 = hrvVals.prefix(7).reduce(0, +) / 7.0
                    let prev7   = Array(hrvVals.dropFirst(7).prefix(7)).reduce(0, +) / 7.0
                    if prev7 > 0 && recent7 < prev7 * 0.88 {
                        let drop = Int((1 - recent7 / prev7) * 100)
                        result.append(SmartInsight(
                            icon: "heart.slash.fill",
                            color: .statusRed,
                            title: "Déficit + HRV en baisse",
                            detail: "\(Int(avgCal)) kcal/j (\(Int(calRatio * 100))%) · HRV −\(drop)% sur 7j"
                        ))
                    }
                }
            }
        }

        if result.count < 2 {
            if let sleep = recovery?.sleepHours, sleep < 6.5 {
                result.append(SmartInsight(
                    icon: "moon.zzz.fill",
                    color: .statusBlue,
                    title: "Récupération limitée",
                    detail: "\(String(format: "%.1f", sleep))h cette nuit — adapte l'intensité"
                ))
            }
        }

        if result.count < 2 {
            let scheduled = dash.schedule.count
            let logged = dash.sessions.count
            if scheduled >= 3 && logged < scheduled - 1 {
                result.append(SmartInsight(
                    icon: "calendar.badge.exclamationmark",
                    color: .statusYellow,
                    title: "Séances manquées",
                    detail: "\(logged)/\(scheduled) complétées cette semaine"
                ))
            }
        }

        return Array(result.prefix(2))
    }

    @ViewBuilder var body: some View {
        if !insights.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    HStack(spacing: 12) {
                        Image(systemName: insight.icon)
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(insight.color)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title)
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.appTextPrimary)
                            Text(insight.detail)
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(insight.color.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(insight.color.opacity(0.22), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
