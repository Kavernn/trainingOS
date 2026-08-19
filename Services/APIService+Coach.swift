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
        let today = DateFormatter.isoDate.string(from: Date())
        let url   = try buildURL(path: "/api/coach/daily_brief")
        let data  = try await fetchWithCache(url: url, key: "daily_brief_\(today)")
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

    // MARK: - Coach analytics cards (bilan)

    func fetchOvertrainingRisk() async throws -> OvertrainingRisk {
        let url  = try buildURL(path: "/api/overtraining_risk")
        let data = try await fetchWithCache(url: url, key: "overtraining_risk")
        return try APIService.decoder.decode(OvertrainingRisk.self, from: data)
    }

    func fetchMesocycleStatus() async throws -> MesocycleStatus {
        let url  = try buildURL(path: "/api/mesocycle_status")
        let data = try await fetchWithCache(url: url, key: "mesocycle_status")
        return try APIService.decoder.decode(MesocycleStatus.self, from: data)
    }

    func fetchPainJournal() async throws -> PainJournalResponse {
        let url  = try buildURL(path: "/api/pain_journal")
        let data = try await fetchWithCache(url: url, key: "pain_journal")
        return try APIService.decoder.decode(PainJournalResponse.self, from: data)
    }

    func fetchOneRMProgramming() async throws -> OneRMResponse {
        let url  = try buildURL(path: "/api/one_rm_programming")
        let data = try await fetchWithCache(url: url, key: "one_rm_programming")
        return try APIService.decoder.decode(OneRMResponse.self, from: data)
    }
}
