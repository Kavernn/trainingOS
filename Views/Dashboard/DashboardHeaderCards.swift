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
