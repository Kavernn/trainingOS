import Foundation
import SwiftUI
import Combine

// MARK: - Private Codable models

private struct NHLMonthSchedule: Codable {
    let games: [NHLAPIGame]?
}

private struct NHLAPIGame: Codable {
    let id: Int
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

private struct NHLBoxscore: Codable {
    let awayTeam: NHLBoxscoreTeam
    let homeTeam: NHLBoxscoreTeam
    let playerByGameStats: NHLPlayerByGameStats?
}

private struct NHLBoxscoreTeam: Codable {
    let sog: Int?
}

private struct NHLPlayerByGameStats: Codable {
    let awayTeam: NHLTeamPlayers
    let homeTeam: NHLTeamPlayers
}

private struct NHLTeamPlayers: Codable {
    let forwards: [NHLPlayerStat]
    let defense: [NHLPlayerStat]
}

private struct NHLPlayerStat: Codable {
    let hits: Int?
    let blockedShots: Int?
}

// MARK: - Public model

struct HabsGameStats {
    let habsShots: Int
    let oppShots: Int
    let habsHits: Int
    let oppHits: Int
    let habsBlocked: Int
    let oppBlocked: Int
}

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
    let stats: HabsGameStats?

    init(status: Status, opponent: String, habsScore: Int?, oppScore: Int?, stats: HabsGameStats? = nil) {
        self.status = status
        self.opponent = opponent
        self.habsScore = habsScore
        self.oppScore = oppScore
        self.stats = stats
    }

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
        guard Date().timeIntervalSince(lastFetch) > (liveGame != nil ? 120 : 3600) else { return }
        await fetch()
    }

    func fetch() async {
        isLoading = true
        failed = false
        defer { isLoading = false; lastFetch = Date() }
        guard let url = URL(string: "https://api-web.nhle.com/v1/club-schedule/MTL/month/now") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let schedule = try APIService.decoder.decode(NHLMonthSchedule.self, from: data)
            let (liveId, lastId) = process(schedule.games ?? [])

            if let (id, isMTLHome) = liveId, let g = liveGame {
                let stats = await fetchBoxscore(gameId: id, isMTLHome: isMTLHome)
                liveGame = HabsGame(status: g.status, opponent: g.opponent, habsScore: g.habsScore, oppScore: g.oppScore, stats: stats)
            }
            if let (id, isMTLHome) = lastId, let g = lastGame {
                let stats = await fetchBoxscore(gameId: id, isMTLHome: isMTLHome)
                lastGame = HabsGame(status: g.status, opponent: g.opponent, habsScore: g.habsScore, oppScore: g.oppScore, stats: stats)
            }
        } catch {
            failed = true
        }
    }

    private func process(_ games: [NHLAPIGame]) -> (liveId: (Int, Bool)?, lastId: (Int, Bool)?) {
        let now = Date()
        var liveResult: HabsGame?
        var liveId: (Int, Bool)?
        var completed: [(game: HabsGame, id: Int, isMTLHome: Bool)] = []
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
                liveId = (g.id, isMTLHome)
            case "OFF", "FINAL":
                completed.append((
                    game: HabsGame(status: .final_, opponent: opponent, habsScore: habsScore, oppScore: oppScore),
                    id: g.id,
                    isMTLHome: isMTLHome
                ))
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
        lastGame    = completed.last?.game
        nextGame    = upcoming.min(by: { $0.date < $1.date })?.game
        isOffSeason = liveResult == nil && completed.isEmpty && upcoming.isEmpty

        return (liveId, completed.last.map { ($0.id, $0.isMTLHome) })
    }

    private func fetchBoxscore(gameId: Int, isMTLHome: Bool) async -> HabsGameStats? {
        guard let url = URL(string: "https://api-web.nhle.com/v1/gamecenter/\(gameId)/boxscore") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let box = try? APIService.decoder.decode(NHLBoxscore.self, from: data) else { return nil }

        let habsTeam   = isMTLHome ? box.homeTeam : box.awayTeam
        let oppTeam    = isMTLHome ? box.awayTeam : box.homeTeam
        let habsPlayers = isMTLHome ? box.playerByGameStats?.homeTeam : box.playerByGameStats?.awayTeam
        let oppPlayers  = isMTLHome ? box.playerByGameStats?.awayTeam : box.playerByGameStats?.homeTeam

        func sum(_ team: NHLTeamPlayers?, _ kp: KeyPath<NHLPlayerStat, Int?>) -> Int {
            ((team?.forwards ?? []) + (team?.defense ?? [])).reduce(0) { $0 + ($1[keyPath: kp] ?? 0) }
        }

        return HabsGameStats(
            habsShots:   habsTeam.sog ?? 0,
            oppShots:    oppTeam.sog  ?? 0,
            habsHits:    sum(habsPlayers, \.hits),
            oppHits:     sum(oppPlayers,  \.hits),
            habsBlocked: sum(habsPlayers, \.blockedShots),
            oppBlocked:  sum(oppPlayers,  \.blockedShots)
        )
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
