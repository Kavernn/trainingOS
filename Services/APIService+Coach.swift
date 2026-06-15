import Foundation

private struct InsightsResponse: Codable { let insights: [InsightEntry] }

extension APIService {
    func fetchInsights() async throws -> [InsightEntry] {
        let url = try buildURL(path: "/api/insights")
        let data = try await fetchWithCache(url: url, key: "insights")
        return try APIService.decoder.decode(InsightsResponse.self, from: data).insights
    }

    func fetchCorrelations() async throws -> CorrelationsData {
        let url  = try buildURL(path: "/api/insights/correlations")
        let data = try await fetchWithCache(url: url, key: "insights_correlations")
        return try APIService.decoder.decode(CorrelationsData.self, from: data)
    }

    func fetchDailyInsight() async throws -> DailyInsight {
        let url = try buildURL(path: "/api/coach/daily_insight")
        let data = try await fetchWithCache(url: url, key: "daily_insight")
        return try APIService.decoder.decode(DailyInsight.self, from: data)
    }

    func fetchIntelligenceInsights() async throws -> [ProactiveInsightItem] {
        let url = try buildURL(path: "/api/coach/intelligence_insights")
        let data = try await fetchWithCache(url: url, key: "intelligence_insights")
        return try APIService.decoder.decode(IntelligenceInsightsResponse.self, from: data).insights
    }

    func fetchProactiveInsights(readinessScore: Double? = nil) async throws -> ProactiveInsightsResponse {
        var items: [URLQueryItem] = []
        if let score = readinessScore {
            items.append(URLQueryItem(name: "readiness_score", value: String(score)))
        }
        let url = try buildURL(path: "/api/coach/proactive_insights", queryItems: items)
        let data = try await fetchWithCache(url: url, key: "proactive_insights")
        return try APIService.decoder.decode(ProactiveInsightsResponse.self, from: data)
    }

    func fetchDailyBrief() async throws -> DailyBrief {
        let url  = try buildURL(path: "/api/coach/daily_brief")
        let data = try await URLSession.authed.data(from: url).0
        return try APIService.decoder.decode(DailyBrief.self, from: data)
    }

    func fetchPostSession(date: String? = nil) async throws -> PostSessionData {
        let today = DateFormatter.isoDate.string(from: Date())
        let key = "post_session_\(date ?? today)"
        let items: [URLQueryItem] = date.map { [URLQueryItem(name: "date", value: $0)] } ?? []
        let url = try buildURL(path: "/api/coach/post_session", queryItems: items)
        let data = try await fetchWithCache(url: url, key: key)
        return try APIService.decoder.decode(PostSessionData.self, from: data)
    }
}
