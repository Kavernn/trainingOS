import SwiftUI

struct WeekMomentumStrip: View {
    let dash: DashboardData

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

    private var streak: Int {
        guard let todayMidnight = Self.isoFmt.date(from: dash.todayDate) else { return 0 }
        let base = todayMidnight.timeIntervalSince1970
        var count = 0
        for i in 0..<365 {
            let d = Date(timeIntervalSince1970: base - Double(i) * 86400)
            let str = Self.isoFmt.string(from: d)
            if dash.sessions[str] != nil { count += 1 } else { break }
        }
        return count
    }

    private var weekCount: Int { dots.filter { $0.hasSession }.count }

    private var streakMessage: String {
        if streak >= 30 { return "🏆 \(streak)j — légende en cours" }
        if streak >= 14 { return "🔥 \(streak)j — 2 semaines non-stop !" }
        if streak >= 7  { return "🔥 \(streak)j de suite — semaine parfaite !" }
        if streak >= 5  { return "🔥 \(streak)j d'affilée — momentum solide" }
        return ""
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(dot.hasSession ? Color.orange : Color.white.opacity(0.07))
                                    .frame(width: 30, height: 30)
                                if dot.isToday {
                                    Circle()
                                        .stroke(Color.orange.opacity(0.65), lineWidth: 1.5)
                                        .frame(width: 30, height: 30)
                                }
                                if dot.hasSession {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.black)
                                }
                            }
                            Text(dot.letter)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(dot.isToday ? .orange : Color.white.opacity(0.3))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("\(streak)j streak")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(streak >= 5 ? .orange : .white)
                    }
                    Text("\(weekCount)/7 jours")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.38))
                }
            }

            if !streakMessage.isEmpty {
                Text(streakMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            streak >= 5
                ? Color.orange.opacity(0.06)
                : Color(white: 0.07).opacity(0.7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(streak >= 5 ? Color.orange.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
