import Foundation

extension APIService {

    func fetchPatterns() async throws -> PatternResponse {
        let url  = URL(string: "\(baseURL)/api/patterns/daily")!
        let data = try await fetchWithCache(url: url, key: "patterns_daily")
        return try JSONDecoder().decode(PatternResponse.self, from: data)
    }

    func pinPattern(id: String) async throws {
        _ = try await offlinePost(
            endpoint: "/api/patterns/pin",
            payload: ["pattern_id": id]
        )
        CacheService.shared.clear(for: "patterns_daily")
    }

    func unpinPattern(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/patterns/pin/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(APIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        _ = try await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "patterns_daily")
    }
}
