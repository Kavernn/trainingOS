import SwiftUI

struct NutriBadge: View {
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.appBody.weight(.black))
                .foregroundColor(color)
                .contentTransition(.numericText())
            Text(unit)
                .font(.appMicro.weight(.medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15), lineWidth: 0.5))
        .cornerRadius(10)
    }
}

// MARK: - Data Gap Section

struct DataGapSection: View {
    let dash: DashboardData
    let recovery: RecoveryEntry?

    private var missingRecovery: Bool {
        recovery == nil ||
        (recovery?.sleepHours == nil && recovery?.hrv == nil && recovery?.restingHr == nil)
    }
    private var missingNutrition: Bool { (dash.nutritionTotals.calories ?? 0) < 1 }
    private var missingWeight: Bool    { (dash.profile.weight ?? 0) == 0 }
    var body: some View {
        let gaps = [missingRecovery, missingNutrition, missingWeight]
        if gaps.contains(true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("À COMPLÉTER")
                    .font(.appCaption.weight(.bold)).tracking(2)
                    .foregroundColor(.gray)
                    .padding(.leading, 2)

                VStack(spacing: 6) {
                    if missingRecovery {
                        NavigationLink(destination: RecoveryView()) {
                            DataGapCard(
                                icon: "moon.zzz.fill",
                                color: .statusBlue,
                                title: "Récupération du jour",
                                subtitle: "Sommeil, FC repos, HRV, courbatures"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if missingNutrition {
                        NavigationLink(destination: NutritionView()) {
                            DataGapCard(
                                icon: "fork.knife",
                                color: .statusGreen,
                                title: "Nutrition du jour",
                                subtitle: "Aucun repas enregistré aujourd'hui"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if missingWeight {
                        NavigationLink(destination: BodyCompView()) {
                            DataGapCard(
                                icon: "scalemass.fill",
                                color: Color.forge,
                                title: "Poids corporel",
                                subtitle: "Ajoute ton poids pour un suivi précis"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct DataGapCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.appHeadline)
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundColor(.gray)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.appTitle.weight(.regular))
                .foregroundColor(color.opacity(0.6))
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Macro Insight Card (Family C — Nutrition J-1 × Performance)
struct MacroInsightCard: View {
    let pattern: PatternEntry
    let yesterday: NutritionDayHistory
    let onTap: () -> Void

    private var threshold: MacroThreshold? { pattern.macroThreshold }

    private var yesterdayValue: Double? {
        guard let t = threshold else { return nil }
        switch t.macro {
        case "proteines": return yesterday.proteines > 0 ? yesterday.proteines : nil
        case "calories":  return yesterday.calories  > 0 ? yesterday.calories  : nil
        default:          return nil
        }
    }

    private var isAboveThreshold: Bool? {
        guard let t = threshold, let v = yesterdayValue else { return nil }
        return v >= t.value
    }

    private var macroLabel: String {
        switch threshold?.macro {
        case "proteines": return "protéines"
        case "glucides":  return "glucides"
        default:          return "calories"
        }
    }

    var body: some View {
        if let t = threshold, let v = yesterdayValue, let above = isAboveThreshold {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: above ? "fork.knife" : "exclamationmark.circle.fill")
                        .font(.appLabel)
                        .foregroundColor(above ? .statusGreen : .statusOrange)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        if above {
                            Text("Bonne nutrition hier — conditions optimales")
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                        } else {
                            Text("Hier : \(Int(v))\(t.unit) \(macroLabel) — sous ton seuil optimal (\(Int(t.value))\(t.unit))")
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        Text(above
                             ? "Macros à la hauteur · seuil \(Int(t.value))\(t.unit)"
                             : "Performance potentiellement réduite aujourd'hui")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(.gray.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(above ? Color.appSuccess.opacity(0.08) : Color.appWarning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(above ? Color.appSuccess.opacity(0.20) : Color.appWarning.opacity(0.20), lineWidth: 1)
                )
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}
