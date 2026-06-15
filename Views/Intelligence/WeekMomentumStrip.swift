import SwiftUI

struct WeekMomentumStrip: View {
    let dash: DashboardData
    var streakData: StreakResponse? = nil

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private struct DayDot {
        let letter: String
        let hasSession: Bool
        let isToday: Bool
    }

    private var dots: [DayDot] {
        guard let todayMidnight = Self.isoFmt.date(from: dash.todayDate) else { return [] }
        let base = todayMidnight.timeIntervalSince1970
        return (0..<7).reversed().map { i in
            let d = Date(timeIntervalSince1970: base - Double(i) * 86400)
            let str = Self.isoFmt.string(from: d)
            let letter = Self.dayFmt.string(from: d).uppercased()
            return DayDot(
                letter: letter,
                hasSession: dash.sessions[str] != nil,
                isToday: str == dash.todayDate
            )
        }
    }

    private var streak: Int { streakData?.currentStreak ?? 0 }

    private var weekCount: Int { dots.filter { $0.hasSession }.count }


    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(dot.hasSession ? Color.forge : Color.white.opacity(0.07))
                                    .frame(width: 30, height: 30)
                                if dot.isToday {
                                    Circle()
                                        .stroke(Color.forge.opacity(0.65), lineWidth: 1.5)
                                        .frame(width: 30, height: 30)
                                }
                                if dot.hasSession {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.black)
                                }
                            }
                            Text(dot.letter)
                                .font(.appMicro.weight(.medium))
                                .foregroundColor(dot.isToday ? Color.forge : Color.white.opacity(0.3))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(Color.forge)
                        Text("\(streak)j streak")
                            .font(.appLabel.weight(.bold))
                            .foregroundColor(streak >= 5 ? Color.forge : .white)
                    }
                    Text("\(weekCount)/7 jours")
                        .font(.appCaption)
                        .foregroundColor(Color.white.opacity(0.38))
                }
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            streak >= 5
                ? Color.forge.opacity(0.06)
                : Color(white: 0.07).opacity(0.7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(streak >= 5 ? Color.forge.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
