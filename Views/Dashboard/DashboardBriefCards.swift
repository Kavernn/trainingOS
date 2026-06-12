import SwiftUI

// MARK: - Recovery Trio Card (Readiness + HRV + Sommeil)

struct RecoveryTrioCard: View {
    let brief: MorningBriefData?
    let recovery: RecoveryEntry?
    var hrvAnalysis: HRVAnalysis? = nil

    private var accent: Color {
        switch brief?.recommendation {
        case "defer":      return .red
        case "reduce":     return .orange
        case "go_caution": return .yellow
        default:           return .green
        }
    }

    private var readinessLabel: String {
        switch brief?.recommendation {
        case "defer":      return "Repos"
        case "reduce":     return "Réduit"
        case "go_caution": return "Prudence"
        default:           return "Prêt"
        }
    }

    private var readinessIcon: String {
        switch brief?.recommendation {
        case "defer":      return "exclamationmark.triangle.fill"
        case "reduce":     return "arrow.down.circle.fill"
        case "go_caution": return "exclamationmark.circle.fill"
        default:           return "bolt.circle.fill"
        }
    }

    private var sleepLabel: String {
        guard let h = recovery?.sleepHours else { return "Sommeil" }
        if h >= 7.5 { return "Récupérateur" }
        if h >= 6.0 { return "Correct" }
        return "Insuffisant"
    }

    var body: some View {
        HStack(spacing: 0) {
            trioPill(icon: readinessIcon,
                     value: readinessLabel,
                     subLabel: "Récupération",
                     color: accent)

            pillDivider

            let hrvColor = hrvAnalysis?.zoneColor ?? Color.green
            let hrvTrend = hrvAnalysis.map { $0.trendArrow } ?? ""
            let hrvValue = recovery?.hrv.map { "\(Int($0))\(hrvTrend)" } ?? "–"
            let hrvSub   = recovery?.hrv != nil ? "HRV ms" : "HRV"
            trioPill(icon: "waveform.path.ecg",
                     value: hrvValue,
                     subLabel: hrvSub,
                     color: recovery?.hrv != nil ? hrvColor : .gray)

            pillDivider

            let sleepValue = recovery?.sleepHours.map { String(format: "%.1fh", $0) } ?? "–"
            trioPill(icon: "moon.zzz.fill",
                     value: sleepValue,
                     subLabel: sleepLabel,
                     color: recovery?.sleepHours != nil ? Color.blue : .gray)
        }
        .background(accent.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.18), lineWidth: 1))
        .cornerRadius(14)
    }

    private var pillDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1)
            .padding(.vertical, 10)
    }

    private func trioPill(icon: String, value: String, subLabel: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subLabel)
                .font(.appMicro)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Momentum Strip (Streak + WeekProgress fusion)

struct MomentumStripView: View {
    let dash: DashboardData
    var streakData: StreakResponse? = nil

    private var currentStreak: Int { streakData?.currentStreak ?? 0 }
    private var bestStreak: Int    { streakData?.bestStreak ?? 0 }
    private var showStreak: Bool   { currentStreak > 3 }

    var weekSessions: Int {
        let fmt = DateFormatter.isoDate
        let todayStr = fmt.string(from: Date())
        guard let todayMidnight = fmt.date(from: todayStr) else { return 0 }
        let base = todayMidnight.timeIntervalSince1970
        let epochDays = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 86400
        let weekday = ((epochDays + 4) % 7) + 1
        let daysSinceMonday = (weekday + 5) % 7
        var count = 0
        for i in 0...daysSinceMonday {
            let dateStr = fmt.string(from: Date(timeIntervalSince1970: base - Double(i) * 86400.0))
            let counted = dash.sessions[dateStr] != nil
                || (dateStr == dash.todayDate && dash.alreadyLoggedToday)
            if counted { count += 1 }
        }
        return count
    }

    var weekTarget: Int {
        let restWords = ["repos", "rest", "off", "récupération"]
        let active = dash.schedule.values.filter { val in
            let lower = val.lowercased()
            return !lower.isEmpty && !restWords.contains(where: { lower.contains($0) })
        }.count
        return max(active, 1)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colonne gauche — semaine
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(weekSessions) / \(weekTarget) séances")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07)).frame(height: 4)
                            Capsule()
                                .fill(weekSessions >= weekTarget ? Color.green : Color.cyan)
                                .frame(width: max(4, geo.size.width * min(Double(weekSessions) / Double(weekTarget), 1.0)), height: 4)
                                .animation(.easeOut(duration: 0.5), value: weekSessions)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showStreak {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1)
                    .padding(.vertical, 10)

                // Colonne droite — streak
                VStack(alignment: .center, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("🔥")
                            .font(.appBody)
                        Text("\(currentStreak)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.forge)
                            .contentTransition(.numericText())
                        Text("j")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.gray)
                    }
                    let gap = bestStreak - currentStreak
                    Text(currentStreak >= bestStreak && bestStreak > 0
                         ? "record ✓"
                         : gap <= 5 ? "-\(gap) record" : "meilleur: \(bestStreak)")
                        .font(.appMicro)
                        .foregroundColor(currentStreak >= bestStreak ? Color.forge.opacity(0.7) : .gray.opacity(0.55))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: 100)
            }
        }
        .glassCard(color: .cyan, intensity: 0.04)
        .cornerRadius(14)
    }
}
