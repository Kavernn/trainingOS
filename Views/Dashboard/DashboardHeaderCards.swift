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

// MARK: - Dashboard Status Bar
struct DashboardStatusBar: View {
    let dash: DashboardData
    var streakData: StreakResponse? = nil
    @Binding var showChecklist: Bool

    private var dateShort: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "EEE d MMM"
        return f.string(from: Date()).capitalized
    }

    private var currentStreak: Int {
        if let s = streakData { return s.currentStreak }
        // iOS 26 : pas de Calendar.startOfDay — arithmétique pure (évite crash 0x8BADF00D)
        let fmt = DateFormatter.isoDate
        let todayStr = fmt.string(from: Date())
        guard let todayMidnight = fmt.date(from: todayStr) else { return 0 }
        let base = todayMidnight.timeIntervalSince1970
        var count = 0
        for i in 0..<365 {
            let key = fmt.string(from: Date(timeIntervalSince1970: base - Double(i) * 86400.0))
            if dash.sessions[key] != nil { count += 1 }
            else if i == 0 { continue }
            else { break }
        }
        return count
    }

    private var isLoggedToday: Bool {
        dash.alreadyLoggedToday || dash.sessions[dash.todayDate] != nil
    }

    private var todayColor: Color {
        let low = dash.today.lowercased()
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") { return .green }
        if low.contains("pull")  { return .cyan }
        if low.contains("push") || low.contains("upper") { return .orange }
        if low.contains("legs") || low.contains("lower") { return .yellow }
        if low.contains("yoga")  { return .purple }
        return .blue
    }

    private var dotColor: Color {
        if isLoggedToday { return .green }
        let low = dash.today.lowercased()
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") {
            return Color.secondary
        }
        return todayColor
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(dateShort)
                .font(.appLabel.weight(.medium))
                .foregroundColor(.white)

            Spacer()

            HStack(spacing: 10) {
                if currentStreak > 0 {
                    HStack(spacing: 3) {
                        Text("🔥")
                            .font(.appCaption)
                        Text("\(currentStreak)j")
                            .font(.appCaption.weight(.bold))
                            .foregroundColor(Color.forge)
                    }
                    Text("·")
                        .font(.appCaption)
                        .foregroundColor(.gray.opacity(0.5))
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                    Text(dash.today)
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }

                Text("·")
                    .font(.appCaption)
                    .foregroundColor(.gray.opacity(0.5))

                Button {
                    showChecklist = true
                } label: {
                    Image(systemName: "checklist")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.orange)
                        .padding(7)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }
}
