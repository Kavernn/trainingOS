import Foundation

struct StressLoadWeek: Codable {
    let weekStart: String
    let trainingStress: Int
    let pssStress: Int?
    let combined: Int

    enum CodingKeys: String, CodingKey {
        case weekStart       = "week_start"
        case trainingStress  = "training_stress"
        case pssStress       = "pss_stress"
        case combined
    }
}

struct StressLoadData: Codable {
    let hasData: Bool
    let weeks: [StressLoadWeek]
    let currentTrainingStress: Int?
    let currentPssStress: Int?
    let dominant: String?
    let trend: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData              = "has_data"
        case weeks
        case currentTrainingStress = "current_training_stress"
        case currentPssStress     = "current_pss_stress"
        case dominant
        case trend
        case message
    }
}
