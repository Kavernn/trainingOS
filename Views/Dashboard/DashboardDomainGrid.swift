import SwiftUI

// MARK: - Domain Tile (contenu pur, pas de tap propre)
private struct DomainTile: View {
    let icon: String
    let title: String
    let value: String
    let subtext: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.appMicro.weight(.semibold))
                    .tracking(1.2)
                    .foregroundColor(.appTextSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.appTextTertiary)
            }
            Text(value)
                .font(.appHeadline.weight(.bold))
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtext)
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, .appCardInsetH)
        .padding(.vertical, .appCardInsetV)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: .appCardRadius)
                .stroke(Color.appSeparator, lineWidth: .appHairline)
        )
        .cornerRadius(.appCardRadius)
    }
}

// MARK: - Domain Grid 2×2
struct DashboardDomainGrid: View {
    let dash: DashboardData
    let hrvAnalysis: HRVAnalysis?
    /// Même règle que la streak et l'alerte « semaine en jeu » (weekly_streaks.py, cible 5).
    let streak: StreakResponse?
    let budgetStatus: BudgetStatus?
    var onOpenSession: (() -> Void)? = nil
    var onOpenHealth:  (() -> Void)? = nil
    var onOpenNutrition: () -> Void

    /// « x / 5 jours actifs » ; « — » tant que la streak n'est pas chargée (build 8).
    static func trainingValue(_ streak: StreakResponse?) -> String {
        guard let s = streak else { return "—" }
        return "\(s.currentWeek.daysActive) / \(s.weeklyTarget) jours actifs"
    }

    // Nutrition — règle anti-fantôme : "0 / —" si cible nil, jamais un chiffre inventé.
    private var nutritionValue: String {
        let consumed = Int(dash.nutritionTotals.calories ?? 0)
        if let tc = dash.targetCalories { return "\(consumed) / \(tc)" }
        return "\(consumed) / —"
    }
    private var nutritionSubtext: String {
        let consumed = Int(dash.nutritionTotals.calories ?? 0)
        if consumed == 0 { return "Aucun repas loggé" }
        if let tc = dash.targetCalories {
            let remaining = max(0, tc - consumed)
            return "\(remaining) kcal restants"
        }
        return "Cible non configurée"
    }

    // Récupération — TENDANCE 7 j (build 9) ; la valeur du jour vit dans le hero seulement.
    static func recoveryValue(_ hrv: HRVAnalysis?) -> String {
        guard let avg = hrv?.hrv7dAvg else { return "HRV 7 j : —" }
        return "HRV 7 j : \(Int(avg.rounded())) ms"
    }
    static func recoverySubtext(_ hrv: HRVAnalysis?) -> String {
        switch hrv?.hrvTrend {
        case "up":     return "En hausse sur 7 j"
        case "down":   return "En baisse sur 7 j"
        case "stable": return "Stable sur 7 j"
        default:       return "Tendance insuffisante"
        }
    }

    // Finances — état vide honnête si budgetStatus nil. Formatage AU SITE d'affichage.
    private var financeValue: String {
        guard let bs = budgetStatus else { return "—" }
        return BudgetFormat.dollars(bs.totalVariableCents)
    }
    private var financeSubtext: String {
        guard let bs = budgetStatus else { return "Budget indisponible" }
        return "Paie dans \(bs.daysToNextPayday) j"
    }

    var body: some View {
        VStack(spacing: .appCardSpacing) {
            HStack(spacing: .appCardSpacing) {
                Button { onOpenSession?() } label: {
                    DomainTile(
                        icon: "dumbbell.fill",
                        title: "ENTRAÎNEMENT",
                        value: Self.trainingValue(streak),
                        subtext: "Cette semaine",
                        tint: Color.domainAccent(.training)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onOpenNutrition) {
                    DomainTile(
                        icon: "fork.knife",
                        title: "NUTRITION",
                        value: nutritionValue,
                        subtext: nutritionSubtext,
                        tint: Color.domainAccent(.nutrition)
                    )
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: .appCardSpacing) {
                Button { onOpenHealth?() } label: {
                    DomainTile(
                        icon: "heart.text.square.fill",
                        title: "RÉCUPÉRATION",
                        value: Self.recoveryValue(hrvAnalysis),
                        subtext: Self.recoverySubtext(hrvAnalysis),
                        tint: Color.domainAccent(.recovery)
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { BudgetView() } label: {
                    DomainTile(
                        icon: "dollarsign.circle.fill",
                        title: "FINANCES",
                        value: financeValue,
                        subtext: financeSubtext,
                        tint: Color.domainAccent(.finance)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
