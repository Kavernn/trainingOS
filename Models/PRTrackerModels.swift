import Foundation

struct RecentPR: Codable {
    let name: String
    let est1rm: Double
    let date: String
    let prevBest: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case est1rm   = "est_1rm"
        case date
        case prevBest = "prev_best"
    }
}

struct PRTrackerData: Codable {
    let hasData: Bool
    let recentPrs: [RecentPR]
    let totalPrs: Int
    let exercisesTracked: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData          = "has_data"
        case recentPrs        = "recent_prs"
        case totalPrs         = "total_prs"
        case exercisesTracked = "exercises_tracked"
        case message
    }
}
