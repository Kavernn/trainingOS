import Foundation
import SwiftUI
import Combine

// MARK: - Private Codable models

private struct NHLMonthSchedule: Codable {
    let games: [NHLAPIGame]?
}

private struct NHLAPIGame: Codable {
    let gameDate: String
    let startTimeUTC: String?
    let gameState: String
    let awayTeam: NHLAPITeam
    let homeTeam: NHLAPITeam
    let periodDescriptor: NHLAPIPeriod?
    let clock: NHLAPIClock?
}

private struct NHLAPITeam: Codable {
    let abbrev: String
    let score: Int?
}

private struct NHLAPIPeriod: Codable {
    let number: Int?
    let periodType: String?
}

private struct NHLAPIClock: Codable {
    let timeRemaining: String?
}

// MARK: - Public model

struct HabsGame {
    enum Status {
        case upcoming(dateLabel: String)
        case live(period: String, timeRemaining: String?)
        case final_
    }
    let status: Status
    let opponent: String
    let habsScore: Int?
    let oppScore: Int?

    var habsWon: Bool? {
        guard case .final_ = status, let h = habsScore, let o = oppScore else { return nil }
        return h > o
    }
}

// MARK: - Service

@MainActor
final class NHLService: ObservableObject {
    @Published private(set) var liveGame: HabsGame?
    @Published private(set) var lastGame: HabsGame?
    @Published private(set) var nextGame: HabsGame?
    @Published private(set) var isLoading   = false
    @Published private(set) var failed      = false
    @Published private(set) var isOffSeason = false

    private var lastFetch: Date = .distantPast

    func fetchIfNeeded() async {
        guard Date().timeIntervalSince(lastFetch) > 300 else { return }
        await fetch()
    }

    func fetch() async {
        isLoading = true
        failed = false
        defer { isLoading = false; lastFetch = Date() }
        guard let url = URL(string: "https://api-web.nhle.com/v1/club-schedule/MTL/month/now") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let schedule = try JSONDecoder().decode(NHLMonthSchedule.self, from: data)
            process(schedule.games ?? [])
        } catch {
            failed = true
        }
    }

    private func process(_ games: [NHLAPIGame]) {
        let now = Date()
        var liveResult: HabsGame?
        var completed: [HabsGame] = []
        var upcoming: [(date: Date, game: HabsGame)] = []

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()

        for g in games {
            let isMTLHome = g.homeTeam.abbrev == "MTL"
            let opponent   = isMTLHome ? g.awayTeam.abbrev  : g.homeTeam.abbrev
            let habsScore  = isMTLHome ? g.homeTeam.score   : g.awayTeam.score
            let oppScore   = isMTLHome ? g.awayTeam.score   : g.homeTeam.score
            let gameDate: Date? = g.startTimeUTC.flatMap { isoFull.date(from: $0) ?? isoBasic.date(from: $0) }
            let state = g.gameState.uppercased()

            switch state {
            case "LIVE", "CRIT":
                liveResult = HabsGame(
                    status: .live(period: periodLabel(g.periodDescriptor), timeRemaining: g.clock?.timeRemaining),
                    opponent: opponent, habsScore: habsScore, oppScore: oppScore
                )
            case "OFF", "FINAL":
                completed.append(HabsGame(status: .final_, opponent: opponent, habsScore: habsScore, oppScore: oppScore))
            case "FUT", "PRE":
                if let d = gameDate, d.timeIntervalSince(now) > -7200 {
                    upcoming.append((d, HabsGame(
                        status: .upcoming(dateLabel: dateLabel(d)),
                        opponent: opponent, habsScore: nil, oppScore: nil
                    )))
                }
            default: break
            }
        }

        liveGame    = liveResult
        lastGame    = completed.last
        nextGame    = upcoming.min(by: { $0.date < $1.date })?.game
        isOffSeason = liveResult == nil && completed.isEmpty && upcoming.isEmpty
    }

    private func periodLabel(_ p: NHLAPIPeriod?) -> String {
        if p?.periodType == "OT" { return "Prolongation" }
        if p?.periodType == "SO" { return "Tirs de barrage" }
        switch p?.number {
        case 1: return "1re pér."
        case 2: return "2e pér."
        case 3: return "3e pér."
        default: return "En jeu"
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let tz = TimeZone.current.secondsFromGMT()
        let nowDay  = (Int(Date().timeIntervalSince1970) + tz) / 86400
        let gameDay = (Int(date.timeIntervalSince1970)   + tz) / 86400

        let tf = DateFormatter()
        tf.locale = Locale(identifier: "fr_CA")
        tf.timeStyle = .short
        tf.timeZone = TimeZone.current
        let timeStr = tf.string(from: date)

        switch gameDay - nowDay {
        case 0:  return "Aujourd'hui · \(timeStr)"
        case 1:  return "Demain · \(timeStr)"
        default:
            let df = DateFormatter()
            df.locale = Locale(identifier: "fr_CA")
            df.dateFormat = "EEE d MMM"
            df.timeZone = TimeZone.current
            return "\(df.string(from: date)) · \(timeStr)"
        }
    }
}
