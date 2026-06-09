import Foundation

struct OverloadExercise: Codable {
    let name: String
    let pct: Double
    let recent: Double
    let prior: Double
}

struct ProgressiveOverloadData: Codable {
    let hasData: Bool
    let topGainers: [OverloadExercise]
    let stalled: [OverloadExercise]
    let exercisesTracked: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData           = "has_data"
        case topGainers        = "top_gainers"
        case stalled
        case exercisesTracked  = "exercises_tracked"
        case message
    }
}
