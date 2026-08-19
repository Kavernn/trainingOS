import SwiftUI

// MARK: - Dashboard Skeleton (fix #5)
struct DashboardSkeletonView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Greeting
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBar(width: 80, height: 10)
                        SkeletonBar(width: 200, height: 26)
                        SkeletonBar(width: 140, height: 12)
                    }
                    Spacer()
                    SkeletonBar(width: 36, height: 36, radius: 18)
                }
                .padding(.top, 12)

                // TodayCard (~120pt height)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        SkeletonBar(width: 36, height: 36, radius: 18)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBar(width: 70, height: 9)
                            SkeletonBar(width: 130, height: 16)
                        }
                        Spacer()
                    }
                    SkeletonBar(height: 48, radius: 12)
                    SkeletonBar(width: 180, height: 12)
                }
                .padding(16)
                .background(Color.appSurfaceInset)
                .cornerRadius(16)

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 6) {
                            SkeletonBar(width: 14, height: 14, radius: 7)
                            SkeletonBar(width: 44, height: 13)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color.appSurfaceInset)
                        .cornerRadius(20)
                    }
                    Spacer(minLength: 0)
                }

                SkeletonBar(height: 48, radius: 12)
                SkeletonBar(height: 60, radius: 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var radius: CGFloat = 6
    @State private var opacity: Double = 0.04

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.appOnSurface.opacity(opacity))
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    opacity = 0.13
                }
            }
    }
}

// MARK: - Dashboard Status Bar
struct DashboardStatusBar: View {
    let dash: DashboardData

    private var dateShort: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "EEE d MMM"
        return f.string(from: Date()).capitalized
    }

    private var isLoggedToday: Bool {
        dash.alreadyLoggedToday || dash.sessions[dash.todayDate] != nil
    }

    private var dotColor: Color {
        if isLoggedToday { return Color.statusGreen }
        let low = dash.today.lowercased()
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") {
            return Color.secondary
        }
        return Color.sessionTypeColor(dash.today)
    }

    var body: some View {
        let accent = Color.sessionTypeColor(dash.today)
        // Point 2 — Wash accent + liseré bas : la StatusBar devient "le panneau du jour".
        // Réversible via DashboardAccentRadiance.statusBarFill / statusBarRule.
        return HStack(spacing: 0) {
            Text(dateShort)
                .font(.appLabel.weight(.medium))
                .foregroundColor(.appTextPrimary)

            Spacer()

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                    Text(dash.today)
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(Color.appOnSurface.opacity(0.85))
                        .lineLimit(1)
                }

            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(accent.opacity(DashboardAccentRadiance.statusBarFill))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(DashboardAccentRadiance.statusBarRule))
                .frame(height: 0.5)
        }
        .padding(.top, 12)
    }
}

// MARK: - Daily Status Stack — 3 mini-cards "où j'en suis aujourd'hui"

struct DailyStatusStack: View {
    let dash: DashboardData
    let brief: MorningBriefData?
    let recovery: RecoveryEntry?
    let hrv: HRVAnalysis?
    let todayNutritionType: String?

    var body: some View {
        VStack(spacing: 8) {
            trainingRow
            nutritionRow
            recoveryRow
        }
    }

    // MARK: Entraînement

    private var trainingRow: some View {
        let low = dash.today.lowercased()
        let isRest = low.contains("repos") || low.contains("rest") || low.contains("recovery")
        let isLogged = dash.alreadyLoggedToday || dash.sessions[dash.todayDate] != nil
        let accent = Color.sessionTypeColor(dash.today)

        let statusText: String
        let statusIcon: String?
        let statusColor: Color
        if isRest {
            statusText = "Repos"; statusIcon = "moon.zzz.fill"; statusColor = .secondary
        } else if isLogged {
            statusText = "Fait"; statusIcon = "checkmark.circle.fill"; statusColor = .statusGreen
        } else if dash.hasPartialLogs {
            statusText = "En cours"; statusIcon = "hourglass"; statusColor = accent
        } else {
            statusText = "À faire"; statusIcon = "circle"; statusColor = accent
        }

        return DailyStatusRow(
            icon: "dumbbell.fill",
            iconColor: statusColor,
            title: "Entraînement",
            statusText: statusText,
            statusIcon: statusIcon,
            statusColor: statusColor,
            subtext: dash.today.isEmpty ? "—" : dash.today
        )
    }

    // MARK: Nutrition

    private var nutritionRow: some View {
        let totals = dash.nutritionTotals
        let consumed = Int(totals.calories ?? 0)
        let target = dash.nutritionSettings?.dayTypeTargets?.target(for: todayNutritionType)
        let targetCal = target.map { Int($0.calories) }

        // ponytail: jamais de cible inventée — tiret explicite si data absente.
        let valueText = targetCal.map { "\(consumed)/\($0)" } ?? "\(consumed)/—"

        let subtext: String
        if consumed == 0 {
            subtext = "Aucun repas loggé"
        } else if let tc = targetCal {
            let remaining = max(0, tc - consumed)
            subtext = "\(remaining) kcal restants"
        } else {
            let prot = Int(totals.proteines ?? 0)
            subtext = prot > 0 ? "\(prot)g protéines" : "Cible non configurée"
        }

        let color: Color = {
            guard let tc = targetCal, tc > 0, consumed > 0 else { return .secondary }
            let pct = Double(consumed) / Double(tc)
            if pct >= 0.85 && pct <= 1.15 { return .statusGreen }
            if pct > 1.15 { return Color.forge }
            return Color.sessionTypeColor(dash.today)
        }()

        return DailyStatusRow(
            icon: "fork.knife",
            iconColor: color,
            title: "Nutrition",
            statusText: valueText,
            statusIcon: nil,
            statusColor: color,
            subtext: subtext
        )
    }

    // MARK: Récupération

    private var recoveryRow: some View {
        let (label, color): (String, Color) = {
            switch brief?.recommendation {
            case "go":         return ("Prêt", .statusGreen)
            case "go_caution": return ("OK, prudence", .yellow)
            case "reduce":     return ("Réduire", .orange)
            case "defer":      return ("Repos requis", .red)
            default:           return ("—", .secondary)
            }
        }()

        var subParts: [String] = []
        if let ms = hrv?.todayRmssd { subParts.append("HRV \(Int(ms))ms") }
        if let h = recovery?.sleepHours { subParts.append(String(format: "%.1fh sommeil", h)) }
        let subtext = subParts.isEmpty ? "Données indisponibles" : subParts.joined(separator: " · ")

        return DailyStatusRow(
            icon: "bolt.heart.fill",
            iconColor: color,
            title: "Récupération",
            statusText: label,
            statusIcon: nil,
            statusColor: color,
            subtext: subtext
        )
    }
}

// MARK: - Daily Status Row (mini-card réutilisable)

private struct DailyStatusRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let statusText: String
    let statusIcon: String?
    let statusColor: Color
    let subtext: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.appBody.weight(.semibold))
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.appCaption.weight(.medium))
                    .foregroundColor(Color.appOnSurface.opacity(0.55))
                Text(subtext)
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                if let statusIcon {
                    Image(systemName: statusIcon)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(statusColor)
                }
                Text(statusText)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appSeparator, lineWidth: 0.5)
        )
        .cornerRadius(14)
    }
}
