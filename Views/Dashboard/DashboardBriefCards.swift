import SwiftUI

// MARK: - UX#1 — Readiness Strip (before TodayCard)

struct ReadinessStripView: View {
    let brief: MorningBriefData?
    let recovery: RecoveryEntry?

    private var accent: Color {
        switch brief?.recommendation {
        case "defer":      return .red
        case "reduce":     return .orange
        case "go_caution": return .yellow
        default:           return .green
        }
    }

    private var label: String {
        switch brief?.recommendation {
        case "defer":      return "Repos recommandé"
        case "reduce":     return "Volume réduit aujourd'hui"
        case "go_caution": return "Entraîne-toi avec prudence"
        default:           return "Prêt à performer"
        }
    }

    private var icon: String {
        switch brief?.recommendation {
        case "defer":      return "exclamationmark.triangle.fill"
        case "reduce":     return "arrow.down.circle.fill"
        case "go_caution": return "exclamationmark.circle.fill"
        default:           return "bolt.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("READINESS")
                    .font(.system(size: 9, weight: .bold)).tracking(2)
                    .foregroundColor(.gray)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
            }
            Spacer()
            if let rec = recovery {
                HStack(spacing: 14) {
                    if let hrv = rec.hrv {
                        VStack(spacing: 0) {
                            Text("\(Int(hrv))")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.green)
                            Text("HRV")
                                .font(.system(size: 8)).foregroundColor(.gray)
                        }
                    }
                    if let rhr = rec.restingHr {
                        VStack(spacing: 0) {
                            Text("\(Int(rhr))")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.red.opacity(0.85))
                            Text("FC")
                                .font(.system(size: 8)).foregroundColor(.gray)
                        }
                    }
                    if let sleep = rec.sleepHours {
                        VStack(spacing: 0) {
                            Text(String(format: "%.1fh", sleep))
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.blue)
                            Text("Sommeil")
                                .font(.system(size: 8)).foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - UX#4 — Week Progress Strip (right under TodayCard)

struct WeekProgressStripView: View {
    let dash: DashboardData

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
            let d = Date(timeIntervalSince1970: base - Double(i) * 86400.0)
            let dateStr = fmt.string(from: d)
            // sessions dict = completed sessions (completed=true en DB)
            // Pour aujourd'hui, alreadyLoggedToday est la source la plus fraîche
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
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 14))
                .foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(weekSessions) / \(weekTarget) séances cette semaine")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
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
        .padding(.vertical, 10)
        .glassCard(color: .cyan, intensity: 0.04)
        .cornerRadius(12)
    }
}

// MARK: - Recovery Snapshot Strip

struct RecoverySnapshotView: View {
    let recovery:    RecoveryEntry
    var hrvAnalysis: HRVAnalysis? = nil

    var body: some View {
        HStack(spacing: 0) {
            if let sleep = recovery.sleepHours {
                SnapMetric(icon: "moon.zzz.fill", value: String(format: "%.1fh", sleep), label: "Sommeil", color: .blue)
            }
            if let rhr = recovery.restingHr {
                SnapMetric(icon: "heart.fill", value: "\(Int(rhr))", label: "FC repos", color: .red)
            }
            if let hrv = recovery.hrv {
                let zoneColor = hrvAnalysis?.zoneColor ?? .green
                let arrow     = hrvAnalysis != nil ? " \(hrvAnalysis!.trendArrow)" : ""
                SnapMetric(
                    icon:  "waveform.path.ecg",
                    value: "\(Int(hrv))ms\(arrow)",
                    label: "HRV",
                    color: zoneColor
                )
            }
            if let steps = recovery.steps {
                let stepsStr = steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000.0) : "\(steps)"
                SnapMetric(icon: "figure.walk", value: stepsStr, label: "Pas", color: .blue)
            }
        }
        .padding(.vertical, 12)
        .glassCard(color: .blue, intensity: 0.05)
        .cornerRadius(16)
    }
}

struct SnapMetric: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 15, weight: .black))
                .foregroundColor(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(0.3)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UX#3 — Morning Brief Compact (always shown when "go" + no flags)

struct MorningBriefCompactView: View {
    let data: MorningBriefData

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 30, height: 30)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
            }
            Text("Brief du matin")
                .font(.system(size: 9, weight: .bold)).tracking(2)
                .foregroundColor(.gray)
            Text("Terrain favorable. Attaque.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.15), lineWidth: 1))
        .cornerRadius(10)
    }
}

// MARK: - Smart Day Banner

struct SmartDayBannerView: View {
    let recommendation: SmartDayRecommendation

    private var accentColor: Color {
        switch recommendation.intensity {
        case "normale": return .green
        case "réduite": return .orange
        default:        return .red
        }
    }
    private var icon: String {
        switch recommendation.intensity {
        case "normale": return "bolt.fill"
        case "réduite": return "tortoise.fill"
        default:        return "moon.zzz.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.cta)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accentColor)
                Text(recommendation.reason)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer()
            if let session = recommendation.suggestedSession {
                Text(session)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accentColor.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(color: accentColor, intensity: 0.07)
        .cornerRadius(14)
    }
}

// MARK: - Great Day Card
struct GreatDayCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            Text("Récupération optimale — séance complète")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(color: .green, intensity: 0.06)
    }
}

// MARK: - Morning Brief Card
struct MorningBriefCardView: View {
    let data: MorningBriefData
    var lssTrend: [LifeStressScore] = []
    var lastSessionDate: String? = nil

    private var accentColor: Color {
        switch data.recommendation {
        case "defer":      return .red
        case "reduce":     return .orange
        case "go_caution": return .yellow
        default:           return .green
        }
    }

    private var iconName: String {
        switch data.recommendation {
        case "defer":      return "exclamationmark.triangle.fill"
        case "reduce":     return "arrow.down.circle.fill"
        case "go_caution": return "exclamationmark.circle.fill"
        default:           return "checkmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(accentColor.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("COACH DU MATIN")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    Text(data.sessionToday)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                Spacer()
                CardInfoButton(title: "Coach du matin", entries: InfoEntry.lssEntries)
                if let lss = data.lss {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(lss))")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(accentColor)
                        Text("LSS")
                            .font(.system(size: 9, weight: .bold)).tracking(1)
                            .foregroundColor(.gray)
                    }
                }
            }

            // LSS gauge
            if let lss = data.lss {
                LSSGauge(score: lss, color: accentColor)
            }

            // Message
            Text(data.message)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            // Flags actifs
            let activeFlags = flagChips
            if !activeFlags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(activeFlags, id: \.label) { chip in
                        HStack(spacing: 4) {
                            Image(systemName: chip.icon)
                                .font(.system(size: 9, weight: .bold))
                            Text(chip.label)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(chip.color)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(chip.color.opacity(0.12))
                        .overlay(Capsule().stroke(chip.color.opacity(0.3), lineWidth: 0.5))
                        .clipShape(Capsule())
                    }
                }
            }

            // F4: Phoenix ritual context
            if let streak = data.phoenixStreak, streak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 10)).foregroundColor(Color(hex: "FF2D20"))
                    Text("Streak Phoenix \(streak)j")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "FF2D20").opacity(0.85))
                    if let rate = data.ritualRate7d {
                        Text("· \(Int(rate * 100))% rituel 7j")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(hex: "FF2D20").opacity(0.08))
                .overlay(Capsule().stroke(Color(hex: "FF2D20").opacity(0.2), lineWidth: 0.5))
                .clipShape(Capsule())
            }

            // Ajustements
            if !data.adjustments.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(data.adjustments, id: \.self) { adj in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(accentColor.opacity(0.7))
                                .padding(.top, 2)
                            Text(adj)
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            // Composantes LSS
            if let comp = data.components {
                LSSComponentsRow(components: comp)
            }

            // LSS sparkline + delta vs semaine
            if lssTrend.count >= 3 {
                LSSSparklineRow(trend: lssTrend, currentLss: data.lss, accentColor: accentColor)
            }

            // Contexte temporel
            let hour = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
            if let lastDate = lastSessionDate,
               let last = DateFormatter.isoDate.date(from: lastDate) {
                let hours = Int(Date().timeIntervalSince(last) / 3600)
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.system(size: 10)).foregroundColor(.gray)
                    Text("Dernière séance il y a \(hours)h")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            if hour >= 20 {
                HStack(spacing: 5) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 10)).foregroundColor(.blue)
                    Text("Séance tardive. Le sommeil qui suit compte double.")
                        .font(.system(size: 11)).foregroundColor(.blue.opacity(0.8))
                }
            }

            // Couverture de données insuffisante — Fix #16: direct action link
            if data.dataCoverage < 0.6 {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text("Vision réduite — \(Int(data.dataCoverage * 100))% des données disponibles.")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    NavigationLink(destination: RecoveryView()) {
                        Text("Compléter →")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
            }

            // Lien vers la vue Stress détaillée
            Divider().background(Color.white.opacity(0.06))
            NavigationLink { PSSView() } label: {
                HStack {
                    Text("Voir le détail Stress")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10)).foregroundColor(.gray.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(accentColor.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accentColor.opacity(0.28), lineWidth: 1))
        .cornerRadius(16)
    }

    private struct FlagChip {
        let icon: String
        let label: String
        let color: Color
    }

    private var flagChips: [FlagChip] {
        var chips: [FlagChip] = []
        if data.flags.hrvDrop        { chips.append(.init(icon: "waveform.path.ecg", label: "HRV bas",          color: .orange)) }
        if data.flags.sleepDeprivation { chips.append(.init(icon: "moon.zzz.fill",  label: "Manque sommeil",   color: .blue)) }
        if data.flags.trainingOverload { chips.append(.init(icon: "flame.fill",      label: "Surcharge",       color: .red)) }
        return chips
    }
}
