import Foundation

struct WarRoomHistory: Decodable {
    let battles: [WarRoomBattle]
    let complete: Bool
    let startDate: String?
    let context: String
    let throughDate: String
    enum CodingKeys: String, CodingKey {
        case battles, complete, context
        case startDate = "start_date"
        case throughDate = "through_date"
    }
}

// One pure projection: no points, writes, or interpretation of missing days as losses.
struct WarRoomProgress {
    enum DayState: String { case victory, recorded, unreported, ongoing, outside }
    struct Day: Identifiable {
        let date: Date
        let key: String
        let state: DayState
        let battle: WarRoomBattle?
        let cumulative: Int
        let isToday: Bool
        var id: String { key }
        var label: String {
            switch state {
            case .victory: return "Victoire enregistrée"
            case .recorded: return "Résultat renseigné sans victoire"
            case .unreported: return "Non renseigné"
            case .ongoing: return "En cours, sans résultat définitif"
            case .outside: return "Hors période de suivi connue"
            }
        }
    }
    struct Week: Identifiable {
        let date: Date
        let days: [Day]
        let partial: Bool
        var id: Date { date }
        var victories: Int { days.filter { $0.state == .victory }.count }
        var recorded: Int { days.filter { $0.state == .victory || $0.state == .recorded }.count }
    }
    struct Badge: Identifiable {
        let id: String
        let title: String
        let requirement: String
        let date: String?
        var earned: Bool { date != nil }
    }
    static let thresholds = [1, 7, 15, 30, 60, 100]
    let history: WarRoomHistory
    let calendar: Calendar
    let days: [Day]
    let weeks: [Week]
    let calendarWeeks: [[Day]]
    let curve: [Day]
    let victories: Int
    let badges: [Badge]
    let today: String
    var complete: Bool { history.complete }
    var level: Int? { complete ? Self.thresholds.filter { victories >= $0 }.count : nil }
    var levelTitle: String {
        guard let level else { return "Historique partiel" }
        return ["Premier pas à venir", "En mouvement", "Fondations", "Bâtisseur", "Persévérance", "Solidité", "Cent victoires"][level]
    }
    var nextThreshold: Int? { complete ? Self.thresholds.first { $0 > victories } : nil }
    var progressFraction: Double {
        guard let next = nextThreshold else { return complete ? 1 : 0 }
        let previous = Self.thresholds.last { $0 <= victories } ?? 0
        return Double(victories - previous) / Double(next - previous)
    }
    var lastBadge: Badge? { badges.filter(\.earned).sorted { ($0.date ?? "") < ($1.date ?? "") }.last }
    var nextBadge: Badge? { complete ? badges.first { !$0.earned && $0.id != "return" } : nil }
    var victories30: Int { curve.filter { $0.state == .victory }.count }
    var coverage: String {
        if complete { return "Toutes les journées enregistrées" }
        let firstKnown = history.battles.map(\.date).filter { $0 <= today }.min() ?? history.throughDate
        return "Historique partiel · depuis le \(firstKnown). Total et paliers indisponibles."
    }
    var totalLabel: String { complete ? "\(victories) journées de victoire" : "\(victories) victoires dans l’historique reçu" }

    init(history: WarRoomHistory, calendar inputCalendar: Calendar, formatter: DateFormatter, today: Date) {
        self.history = history
        var calendar = inputCalendar
        calendar.timeZone = formatter.timeZone
        calendar.firstWeekday = 2
        self.calendar = calendar
        let end = calendar.startOfDay(for: today)
        let endKey = formatter.string(from: end)
        self.today = endKey
        // updated_at is authoritative for duplicate responses; date UNIQUE in storage.
        var byDate: [String: WarRoomBattle] = [:]
        for battle in history.battles where battle.date <= endKey {
            guard formatter.date(from: battle.date) != nil else { continue }
            if let current = byDate[battle.date],
               (current.updatedAt ?? current.createdAt ?? "", current.id) > (battle.updatedAt ?? battle.createdAt ?? "", battle.id) { continue }
            byDate[battle.date] = battle
        }
        let ordered = byDate.values.sorted { $0.date < $1.date }
        let wins = ordered.filter { $0.status == .victory }
        victories = wins.count
        // A changed start setting cannot erase or reclassify older recorded results.
        let firstKey = [history.startDate, ordered.first?.date].compactMap { $0 }.min()
        let trackingStart = firstKey.flatMap { formatter.date(from: $0) }.map { calendar.startOfDay(for: $0) }
        let knownStart = history.complete ? trackingStart : ordered.first.flatMap { formatter.date(from: $0.date) }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: end)!.start
        let gridStart = calendar.date(byAdding: .weekOfYear, value: -11, to: weekStart)!
        let gridEnd = calendar.date(byAdding: .day, value: 83, to: gridStart)!
        let curveStart = calendar.date(byAdding: .day, value: -29, to: end)!
        let start = min(gridStart, curveStart)
        var cumulative = wins.filter { $0.date < formatter.string(from: start) }.count
        var all: [Day] = []
        var date = start
        while date <= gridEnd {
            let key = formatter.string(from: date)
            let battle = byDate[key]
            if battle?.status == .victory { cumulative += 1 }
            let state: DayState
            if date > end { state = .outside }
            else if battle?.status == .victory { state = .victory }
            else if battle?.status == .lost { state = .recorded }
            else if battle?.status == .active { state = .ongoing }
            else if let knownStart, date >= knownStart { state = date == end ? .ongoing : .unreported }
            else { state = .outside }
            all.append(Day(date: date, key: key, state: state, battle: battle, cumulative: cumulative, isToday: date == end))
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        days = all
        calendarWeeks = stride(from: 0, to: 84, by: 7).map { Array(all[$0..<($0 + 7)]) }
        weeks = calendarWeeks.suffix(8).map { week in
            Week(date: week[0].date, days: week, partial: week.contains { $0.isToday } || week.contains { $0.state == .outside })
        }
        curve = all.filter { $0.date >= curveStart && $0.date <= end }
        var sawRecorded = false
        var comeback: String?
        for battle in ordered {
            if battle.status == .lost { sawRecorded = true }
            if battle.status == .victory && sawRecorded && comeback == nil { comeback = battle.date }
        }
        func milestone(_ count: Int) -> String? { history.complete && wins.count >= count ? wins[count - 1].date : nil }
        badges = [
            Badge(id: "first", title: "Premier pas", requirement: "1 journée de victoire", date: milestone(1)),
            Badge(id: "week", title: "Une semaine construite", requirement: "7 victoires cumulées, pas forcément consécutives", date: milestone(7)),
            Badge(id: "return", title: "Le retour", requirement: "Une victoire après un résultat renseigné sans victoire", date: history.complete ? comeback : nil),
            Badge(id: "month", title: "Un mois de victoires", requirement: "30 journées de victoire", date: milestone(30))
        ]
    }
}

// Event-only eligibility. Reading/refreshing a history never invokes this gate.
struct WarRoomVictoryFeedback {
    private var deliveredDates: Set<String> = []
    mutating func accept(date: String, before: WarRoomProgress?, after: WarRoomProgress?) -> Bool {
        guard let before, let after, before.complete, after.complete,
              before.history.context == after.history.context,
              after.victories > before.victories,
              !before.history.battles.contains(where: { $0.date == date && $0.status == .victory }),
              after.history.battles.contains(where: { $0.date == date && $0.status == .victory }),
              deliveredDates.insert(date).inserted else { return false }
        return true
    }
}
