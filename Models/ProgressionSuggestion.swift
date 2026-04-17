import Foundation

struct ProgressionSuggestion: Codable, Identifiable {
    var id: String { exerciseName }

    let exerciseName: String
    let loadProfile: String?
    let suggestionType: String   // "increase_weight" | "increase_sets" | "deload" | "maintain" | "regression" | "rep_progress"
    let currentWeight: Double?
    let suggestedWeight: Double?
    let currentScheme: String?
    let suggestedScheme: String?
    let reason: String
    let fatigueWarning: Bool

    enum CodingKeys: String, CodingKey {
        case exerciseName    = "exercise_name"
        case loadProfile     = "load_profile"
        case suggestionType  = "suggestion_type"
        case currentWeight   = "current_weight"
        case suggestedWeight = "suggested_weight"
        case currentScheme   = "current_scheme"
        case suggestedScheme = "suggested_scheme"
        case reason
        case fatigueWarning  = "fatigue_warning"
    }
}

struct ProgressionSuggestionsResponse: Codable {
    let suggestions: [ProgressionSuggestion]
}
