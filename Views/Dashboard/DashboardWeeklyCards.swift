import SwiftUI

// MARK: - Weekly Report Teaser (tap to open full view)

struct WeeklyReportTeaser: View {
    let report: WeeklyReport

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("RAPPORT DE LA SEMAINE")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5)
                    .foregroundColor(.gray)
                HStack(spacing: 16) {
                    Label("\(report.sessionCount) séances", systemImage: "flame.fill")
                    if report.prCount > 0 {
                        Label("\(report.prCount) limite\(report.prCount > 1 ? "s" : "") détruite\(report.prCount > 1 ? "s" : "")", systemImage: "trophy.fill")
                            .foregroundColor(.yellow)
                    }
                    if report.totalVolumeLbs > 0 {
                        Label("\(Int(report.totalVolumeLbs / 1000))k lbs", systemImage: "scalemass.fill")
                            .foregroundColor(.orange)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12)).foregroundColor(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(color: .purple, intensity: 0.06)
        .cornerRadius(14)
    }
}

// MARK: - Weekly Report Full View

struct WeeklyReportView: View {
    let report: WeeklyReport
    @ObservedObject private var units = UnitSettings.shared

    private var shareText: String {
        var lines = ["📊 Rapport semaine TrainingOS"]
        lines.append("Séances : \(report.sessionCount)")
        if report.prCount > 0 { lines.append("🏆 Limites détruites : \(report.prCount)") }
        if report.totalVolumeLbs > 0 {
            lines.append("Volume : \(Int(report.totalVolumeLbs / 1000))k lbs")
        }
        if let r = report.avgRecoveryScore { lines.append("Récupération moy. : \(String(format: "%.1f", r))/10") }
        if let s = report.avgSleepHours   { lines.append("Sommeil moy. : \(String(format: "%.1f", s))h") }
        if let c = report.nutritionCompliance { lines.append("Compliance nutrition : \(c)%") }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: .orange)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 4) {
                        Text("RAPPORT SEMAINE")
                            .font(.system(size: 11, weight: .bold)).tracking(2)
                            .foregroundColor(.gray)
                        Text("\(report.weekStart) → \(report.weekEnd)")
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 8)

                    // KPI grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        WeeklyKPI(value: "\(report.sessionCount)", label: "Séances", icon: "flame.fill", color: .orange)
                        WeeklyKPI(value: "\(report.prCount)", label: "Limites détruites", icon: "trophy.fill", color: .yellow)
                        if report.totalVolumeLbs > 0 {
                            WeeklyKPI(value: "\(Int(report.totalVolumeLbs / 1000))k", label: "Volume (lbs)", icon: "scalemass.fill", color: .cyan)
                        }
                        if let r = report.avgRecoveryScore {
                            WeeklyKPI(value: String(format: "%.1f/10", r), label: "Récup. moy.", icon: "heart.fill", color: .green)
                        }
                        if let s = report.avgSleepHours {
                            WeeklyKPI(value: String(format: "%.1fh", s), label: "Sommeil moy.", icon: "moon.fill", color: .blue)
                        }
                        if let steps = report.avgSteps {
                            WeeklyKPI(value: "\(steps / 1000)k", label: "Pas/jour", icon: "figure.walk", color: .teal)
                        }
                        if let hrv = report.avgHrv {
                            WeeklyKPI(value: String(format: "%.0f ms", hrv), label: "HRV moy.", icon: "waveform.path.ecg", color: .cyan)
                        }
                        if let c = report.nutritionCompliance {
                            WeeklyKPI(value: "\(c)%", label: "Nutrition", icon: "fork.knife", color: .green)
                        }
                    }

                    // Weekly score ring
                    if let score = report.weeklyScore {
                        let scoreColor: Color = score >= 75 ? .green : score >= 50 ? .orange : .red
                        HStack(spacing: 20) {
                            ZStack {
                                Circle().stroke(Color.white.opacity(0.07), lineWidth: 8).frame(width: 70, height: 70)
                                Circle()
                                    .trim(from: 0, to: CGFloat(score) / 100)
                                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .frame(width: 70, height: 70)
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 0) {
                                    Text("\(score)").font(.system(size: 20, weight: .black)).foregroundColor(.white)
                                    Text("/100").font(.system(size: 9)).foregroundColor(.gray)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SCORE SEMAINE").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.gray)
                                Text(score >= 75 ? "Excellente semaine" : score >= 50 ? "Bonne semaine" : "Semaine à améliorer")
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                if let rpe = report.avgRpe {
                                    Text("RPE moy. \(String(format: "%.1f", rpe))/10")
                                        .font(.system(size: 12)).foregroundColor(.gray)
                                }
                            }
                            Spacer()
                        }
                        .padding(14)
                        .glassCard(color: scoreColor, intensity: 0.06)
                        .cornerRadius(14)
                    }

                    if let top = report.topExercise {
                        HStack(spacing: 10) {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("EXERCICE PHARE").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.gray)
                                Text(top).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .glassCard(color: .yellow, intensity: 0.07)
                        .cornerRadius(14)
                    }

                    // PRs list
                    if !report.prs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("RECORDS PERSONNELS", systemImage: "trophy.fill")
                                .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.yellow)
                            ForEach(report.prs, id: \.self) { exo in
                                HStack(spacing: 8) {
                                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.yellow.opacity(0.8))
                                    Text(exo).font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                                    Spacer()
                                }
                            }
                        }
                        .padding(14)
                        .glassCard(color: .yellow, intensity: 0.05)
                        .cornerRadius(14)
                    }

                    // Focus next week
                    if !report.focusNextWeek.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("FOCUS SEMAINE PROCHAINE", systemImage: "target")
                                .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundColor(.purple)
                            ForEach(Array(report.focusNextWeek.enumerated()), id: \.offset) { _, tip in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 11)).foregroundColor(.purple)
                                    Text(tip).font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                }
                            }
                        }
                        .padding(14)
                        .glassCard(color: .purple, intensity: 0.05)
                        .cornerRadius(14)
                    }

                    ShareLink(item: shareText) {
                        Label("Partager ce rapport", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.purple.opacity(0.7))
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Semaine")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WeeklyKPI: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(color)
            Text(value)
                .font(.system(size: 18, weight: .black)).foregroundColor(color)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .medium)).tracking(1).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard(color: color, intensity: 0.05)
        .cornerRadius(14)
    }
}

// MARK: - Quick Log Bar
struct QuickLogBar: View {
    let alreadyLogged: Bool
    let sleepLogged: Bool
    let moodDone: Bool
    var onSleepTap: () -> Void
    var onMoodTap: () -> Void
    var onSessionTap: () -> Void
    var onNutritionTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            QuickLogChip(icon: "dumbbell.fill",    label: "Séance",  done: alreadyLogged, color: .orange,                                   action: onSessionTap)
            QuickLogChip(icon: "moon.fill",         label: "Sommeil", done: sleepLogged,  color: Color(red: 0.45, green: 0.35, blue: 0.95), action: onSleepTap)
            QuickLogChip(icon: "face.smiling.fill", label: "Humeur",  done: moodDone,     color: .yellow,                                   action: onMoodTap)
            QuickLogChip(icon: "fork.knife",        label: "Repas +", done: false,        color: .green,                                    action: onNutritionTap ?? {})
            Spacer(minLength: 0)
        }
    }
}

struct QuickLogChip: View {
    let icon: String
    let label: String
    let done: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(done ? .green : color)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(done ? Color.gray : .white)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(done ? Color.white.opacity(0.05) : color.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(done ? Color.white.opacity(0.08) : color.opacity(0.3), lineWidth: 1))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Ring Card
struct ActivityRingCard: View {
    let steps: Int
    private let goal = 10_000

    private var progress: Double { min(1.0, Double(steps) / Double(goal)) }
    private var ringColor: Color {
        switch progress {
        case 0.75...: return .green
        case 0.5...:   return .yellow
        default:      return .orange
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.8), value: steps)
                VStack(spacing: 0) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("OBJECTIF PAS")
                    .font(.system(size: 9, weight: .bold)).tracking(1.5)
                    .foregroundColor(.gray)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(steps.formatted())")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("/ \(goal.formatted()) pas")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                let remaining = max(0, goal - steps)
                if remaining > 0 {
                    Text("encore \(remaining.formatted()) pas")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                } else {
                    Label("Objectif atteint", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
    }
}

// MARK: - Optimal Training Window Card
struct OptimalWindowCard: View {
    let wakeTime: Date

    private var windowStart: Date {
        let candidate = wakeTime.addingTimeInterval(3 * 3600)
        let tz = TimeZone.current.secondsFromGMT()
        let localSecs = Int(candidate.timeIntervalSince1970) + tz
        let hour = (localSecs / 3600) % 24
        if hour < 10 {
            let startOfDay = localSecs - (localSecs % 86400)
            return Date(timeIntervalSince1970: TimeInterval(startOfDay + 10 * 3600 - tz))
        }
        return candidate
    }

    private var windowEnd: Date {
        wakeTime.addingTimeInterval(8 * 3600)
    }

    private var isWindowNow: Bool {
        let now = Date()
        return now >= windowStart && now <= windowEnd
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH'h'"
        return f
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.cyan.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.cyan)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("FENÊTRE OPTIMALE")
                    .font(.system(size: 9, weight: .bold)).tracking(1.5)
                    .foregroundColor(.gray)
                HStack(spacing: 4) {
                    Text("\(timeFormatter.string(from: windowStart))–\(timeFormatter.string(from: windowEnd))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    if isWindowNow {
                        Text("• MAINTENANT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.cyan.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
        .cornerRadius(12)
    }
}
