import Foundation

struct DailyInsight: Codable {
    let type: String    // "alert" | "opportunity" | "programme" | "ai_fallback" | "none"
    let icon: String
    let title: String
    let body: String
    let source: String
    let action: String  // "stats" | "seance" | "coach" | "programme"
    let priority: Int

    var isEmpty: Bool { type == "none" || title.isEmpty }
}

struct PostSessionData: Codable {
    let volumeDeltaPct: Int?
    let avgRpe: Double?
    let rpeInterpretation: String
    let nutritionAdvice: String
    let sessionId: String?
    let sessionName: String?

    enum CodingKeys: String, CodingKey {
        case volumeDeltaPct    = "volume_delta_pct"
        case avgRpe            = "avg_rpe"
        case rpeInterpretation = "rpe_interpretation"
        case nutritionAdvice   = "nutrition_advice"
        case sessionId         = "session_id"
        case sessionName       = "session_name"
    }
}
