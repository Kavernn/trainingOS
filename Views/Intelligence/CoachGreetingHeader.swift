import SwiftUI

struct CoachGreetingHeader: View {
    let dash: DashboardData

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var firstName: String {
        dash.profile.name?.components(separatedBy: " ").first ?? "Athlète"
    }

    private var greeting: String {
        let h = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
        if h < 12 { return "Bonjour" }
        if h < 18 { return "Bon après-midi" }
        return "Bonsoir"
    }

    private var formattedDate: String {
        guard let d = Self.isoFmt.date(from: dash.todayDate) else { return dash.todayDate }
        return Self.dateFmt.string(from: d).capitalized
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting), \(firstName)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.appTextPrimary)
                Text(formattedDate + " · Sem. \(dash.week)")
                    .font(.appLabel)
                    .foregroundColor(Color.white.opacity(0.38))
            }
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(Color.purple.opacity(0.5))
        }
    }
}
