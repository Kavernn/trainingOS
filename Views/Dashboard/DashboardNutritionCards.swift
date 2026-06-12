import SwiftUI

// MARK: - Nutrition Summary
struct NutritionSummaryView: View {
    let totals: NutritionTotals
    let settings: NutritionSettings?

    private var protTarget: Double { settings?.proteines ?? 160 }
    private var protCurrent: Double { totals.proteines ?? 0 }
    private var pct: Double { min(protCurrent / max(protTarget, 1), 1.0) }
    private var ringColor: Color {
        if protCurrent > protTarget { return .red }
        if protCurrent >= protTarget { return .green }
        return .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "NUTRITION AUJOURD'HUI", icon: "fork.knife")

            HStack(spacing: 16) {
                // Anneau protéines
                ZStack {
                    Circle().stroke(Color.appSurfaceInset, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: pct)
                    VStack(spacing: 0) {
                        Text("\(Int(protCurrent))")
                            .font(.appBody.weight(.black))
                            .foregroundColor(.appTextPrimary)
                        Text("g")
                            .font(.appMicro)
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 6) {
                    // Statut protéines
                    if protCurrent >= protTarget {
                        Label("Objectif atteint", systemImage: "checkmark.circle.fill")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.green)
                    } else {
                        Text("Encore \(Int(protTarget - protCurrent))g de prot")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.blue)
                    }

                    // Badges macros
                    HStack(spacing: 8) {
                        NutriBadge(value: "\(Int(totals.calories ?? 0))", unit: "kcal", color: Color.forge)
                        NutriBadge(value: "\(Int(totals.glucides ?? 0))", unit: "g carbs", color: .yellow)
                        NutriBadge(value: "\(Int(totals.lipides ?? 0))", unit: "g lip", color: .pink)
                    }
                }
            }

            // Barre de progression calories
            if let calTarget = settings?.calories, calTarget > 0 {
                let calCurrent = totals.calories ?? 0
                let calPct = min(calCurrent / calTarget, 1.0)
                let overTarget = calCurrent > calTarget
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Calories")
                            .font(.appCaption).foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(calCurrent)) / \(Int(calTarget)) kcal")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(overTarget ? .red : Color.forge)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                            Capsule()
                                .fill(overTarget ? Color.appDanger : Color.forge)
                                .frame(width: max(5, geo.size.width * calPct), height: 5)
                                .animation(.easeOut(duration: 0.6), value: calPct)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(16)
        .glassCard(color: Color.forge, intensity: 0.04)
        .cornerRadius(16)
    }
}

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

// MARK: - UX#5 — Nutrition Strip (compact, position 4)

struct NutritionStripView: View {
    let totals: NutritionTotals
    let settings: NutritionSettings?

    private var calTarget: Double { settings?.calories ?? 0 }
    private var calCurrent: Double { totals.calories ?? 0 }
    private var calPct: Double { calTarget > 0 ? min(calCurrent / calTarget, 1.0) : 0 }
    private var overCal: Bool { calTarget > 0 && calCurrent > calTarget }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.appCaption)
                    .foregroundColor(Color.forge)
                Text("NUTRITION")
                    .font(.appMicro.weight(.bold)).tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(Int(calCurrent))\(calTarget > 0 ? " / \(Int(calTarget))" : "") kcal")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(overCal ? .red : Color.forge)
            }

            HStack(spacing: 6) {
                NutriBadge(value: "\(Int(totals.proteines ?? 0))", unit: "prot", color: .blue)
                NutriBadge(value: "\(Int(totals.glucides ?? 0))", unit: "carbs", color: .yellow)
                NutriBadge(value: "\(Int(totals.lipides ?? 0))", unit: "lipides", color: .pink)
                if calTarget > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.06)).frame(height: 4)
                            Capsule()
                                .fill(overCal ? Color.appDanger : Color.forge)
                                .frame(width: max(4, geo.size.width * calPct), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .frame(maxWidth: 80)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(color: Color.forge, intensity: 0.04)
        .cornerRadius(12)
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
                                color: .blue,
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
                                color: .green,
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
                        .foregroundColor(above ? .green : .orange)
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
