import Foundation

extension APIService {
    func fetchReadiness() async throws -> ReadinessResponse {
        let url  = try buildURL(path: "/api/readiness")
        let data = try await fetchWithCache(url: url, key: "readiness")
        return try APIService.decoder.decode(ReadinessResponse.self, from: data)
    }

    func fetchStreaks(date: String? = nil) async throws -> StreakResponse {
        var comps = URLComponents(string: "\(baseURL)/api/stats/streaks")!
        if let d = date { comps.queryItems = [URLQueryItem(name: "date", value: d)] }
        let url  = comps.url!
        let data = try await fetchWithCache(url: url, key: "streak_data")
        return try APIService.decoder.decode(StreakResponse.self, from: data)
    }
}
