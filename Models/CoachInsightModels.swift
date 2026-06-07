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

struct ProactiveInsightItem: Codable {
    let dimension: String
    let level: Int
    let title: String
    let message: String
    let action: String
    let icon: String
    let color: String

    func asDailyInsight() -> DailyInsight {
        let mappedAction: String
        switch action {
        case "open_seance":   mappedAction = "seance"
        case "open_recovery": mappedAction = "stats"
        default:              mappedAction = "coach"
        }
        return DailyInsight(
            type: level == 1 ? "alert" : "opportunity",
            icon: icon,
            title: title,
            body: message,
            source: "proactive",
            action: mappedAction,
            priority: level == 1 ? 10 : 5
        )
    }
}

struct IntelligenceInsightsResponse: Codable {
    let insights: [ProactiveInsightItem]
    let computedAt: String
    enum CodingKeys: String, CodingKey {
        case insights   = "insights"
        case computedAt = "computed_at"
    }
}

struct ProactiveInsightsResponse: Codable {
    let pushInsight:          ProactiveInsightItem?
    let dashboardInsight:     ProactiveInsightItem?
    let intelligenceInsights: [ProactiveInsightItem]
    let computedAt:           String

    enum CodingKeys: String, CodingKey {
        case pushInsight          = "push_insight"
        case dashboardInsight     = "dashboard_insight"
        case intelligenceInsights = "intelligence_insights"
        case computedAt           = "computed_at"
    }
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
