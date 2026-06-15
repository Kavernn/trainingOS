import SwiftUI

// MARK: - SleepDebtCard (Dashboard compact)

struct SleepDebtAnalyticsCard: View {
    let data: SleepDebtData

    private var debtColor: Color {
        guard let d = data.debt7d else { return Color.appOnSurface.opacity(0.40) }
        if d <= 0      { return .forge }
        if d < 3       { return Color.trendNeutral }
        return Color.trendNegative
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            metricsRow
            if let nights = data.nightsToRecover, nights > 0 {
                Text("~\(nights) nuit\(nights > 1 ? "s" : "") pour rembourser la dette 7J")
                    .font(.appMicro)
                    .foregroundColor(Color.appOnSurface.opacity(0.32))
            } else if data.debt7d ?? 1 <= 0 {
                Text("Pas de dette — tu es à jour.")
                    .font(.appMicro)
                    .foregroundColor(Color.forge.opacity(0.65))
            }
        }
        .padding(14)
        .glassCard()
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.zzz.fill")
                .font(.appMicro)
                .foregroundColor(Color.appOnSurface.opacity(0.35))
            Text("DETTE DE SOMMEIL")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(Color.appOnSurface.opacity(0.35))
            Spacer()
            TrendBadge(trend: data.trend)
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("7 DERNIÈRES NUITS")
                    .font(.appMicro).tracking(0.8)
                    .foregroundColor(Color.appOnSurface.opacity(0.28))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(data.formattedDebt7d)
                        .font(.appCardMetric)
                        .foregroundColor(debtColor)
                    Text(data.isInDebt ? "dette" : "surplus")
                        .font(.appCaption)
                        .foregroundColor(Color.appOnSurface.opacity(0.38))
                }
            }
            Spacer()
            if let avg = data.avgSleep7d {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("MOY. RÉELLE")
                        .font(.appMicro).tracking(0.8)
                        .foregroundColor(Color.appOnSurface.opacity(0.28))
                    Text(String(format: "%.1fh", avg))
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(Color.appOnSurface.opacity(0.65))
                    Text("/ \(Int(data.target))h cible")
                        .font(.appMicro)
                        .foregroundColor(Color.appOnSurface.opacity(0.28))
                }
            }
        }
    }
}

// MARK: - Trend Badge

private struct TrendBadge: View {
    let trend: String

    private var color: Color {
        switch trend {
        case "rembourser": return .forge
        case "creuser":    return Color.trendNegative
        default:           return Color.trendNeutral
        }
    }

    private var icon: String {
        switch trend {
        case "rembourser": return "arrow.down.circle.fill"
        case "creuser":    return "arrow.up.circle.fill"
        default:           return "equal.circle.fill"
        }
    }

    private var label: String {
        switch trend {
        case "rembourser": return "Remboursement"
        case "creuser":    return "En hausse"
        default:           return "Stable"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.appMicro.weight(.semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color.opacity(0.85))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}
