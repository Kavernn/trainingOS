import Foundation

extension APIService {
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

    func fetchProactiveInsights() async throws -> ProactiveInsightsResponse {
        let url = try buildURL(path: "/api/coach/proactive_insights")
        let data = try await fetchWithCache(url: url, key: "proactive_insights")
        return try APIService.decoder.decode(ProactiveInsightsResponse.self, from: data)
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
