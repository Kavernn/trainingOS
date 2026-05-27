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
                .background(Color.white.opacity(0.04))
                .cornerRadius(16)

                // DailyMetricsRow — 4 tiles
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: 6) {
                            SkeletonBar(width: 16, height: 16, radius: 8)
                            SkeletonBar(width: 32, height: 14)
                            SkeletonBar(width: 28, height: 9)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                    }
                }

                // WeekProgressStrip
                SkeletonBar(height: 48, radius: 12)

                // DailyStreakCard
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
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    opacity = 0.13
                }
            }
    }
}

// MARK: - Fatigue Score Gauge
struct FatigueScoreGauge: View {
    let score: Int

    private var gaugeColor: Color {
        if score >= 75 { return .red }
        if score >= 65 { return .orange }
        return .green
    }

    private var label: String {
        if score >= 75 { return "Critique" }
        if score >= 65 { return "Attention" }
        return "Modéré"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Score de fatigue")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("\(score)/100 — \(label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(gaugeColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                    Capsule()
                        .fill(gaugeColor)
                        .frame(width: geo.size.width * CGFloat(score) / 100, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Greeting Header
struct GreetingHeaderView: View {
    let dash: DashboardData
    @Binding var showChecklist: Bool

    var greeting: String {
        let hour = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
        if hour < 12 { return "Bon matin" }
        if hour < 18 { return "Bon après-midi" }
        return "Bonsoir"
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: Date()).capitalized
    }

    var streak: Int {
        // N'utilise PAS Calendar.startOfDay ni addingTimeInterval :
        // sur iOS 26 ces appels routent via Calendar.date(byAdding:wrappingComponents:true)
        // qui recurse infiniment dans _CalendarGregorian.dateComponents → crash 0x8BADF00D.
        let fmt = DateFormatter.isoDate
        let todayStr = fmt.string(from: Date())                     // dateComponents, pas date(byAdding:)
        guard let todayMidnight = fmt.date(from: todayStr) else { return 0 }  // parse → Date, pas date(byAdding:)
        let base = todayMidnight.timeIntervalSince1970              // secondes epoch
        var count = 0
        for i in 0..<365 {
            let checkDate = Date(timeIntervalSince1970: base - Double(i) * 86400.0) // arithmétique pure
            let key = fmt.string(from: checkDate)
            if dash.sessions[key] != nil {
                count += 1
            } else if i == 0 {
                continue // aujourd'hui pas encore loggé, on vérifie hier
            } else {
                break
            }
        }
        return count
    }

    var todayColor: Color {
        let low = dash.today.lowercased()
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") { return .green }
        if low.contains("pull")  { return .cyan }
        if low.contains("push") || low.contains("upper") { return .orange }
        if low.contains("legs") || low.contains("lower") { return .yellow }
        if low.contains("yoga")  { return .purple }
        return .blue
    }

    var todayIcon: String {
        let low = dash.today.lowercased()
        if low.contains("yoga")  { return "figure.mind.and.body" }
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") { return "moon.fill" }
        if low.contains("upper") || low.contains("lower") ||
           low.contains("push") || low.contains("pull") ||
           low.contains("legs") || low.contains("full body") { return "dumbbell.fill" }
        return "dumbbell.fill"
    }

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
            if dash.sessions[fmt.string(from: d)] != nil { count += 1 }
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(greeting + (dash.profile.name.map { ", \($0.components(separatedBy: " ").first ?? $0)" } ?? "") + " 👋")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text(formattedDate)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        // UX#2: Checklist button in header — out of main scroll
                        Button {
                            showChecklist = true
                        } label: {
                            Image(systemName: "checklist")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.orange)
                                .padding(8)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Text("Sem. \(dash.week)")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }

                    if streak > 1 {
                        StreakBadge(count: streak)
                    }
                }
            }

            // Workout badge + week progress
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: todayIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(todayColor)
                    Text(dash.today)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(todayColor)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(todayColor.opacity(0.12))
                .overlay(Capsule().stroke(todayColor.opacity(0.25), lineWidth: 1))
                .clipShape(Capsule())

                Spacer()

                if weekSessions > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.7))
                        Text("\(weekSessions) séance\(weekSessions != 1 ? "s" : "") cette sem.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.top, 12)
    }
}
