import Foundation

extension APIService {
    func fetchReadiness() async throws -> ReadinessResponse {
        let url  = try buildURL(path: "/api/readiness")
        let data = try await fetchWithCache(url: url, key: "readiness")
        return try APIService.decoder.decode(ReadinessResponse.self, from: data)
    }

    func fetchStreaks(date: String? = nil) async throws -> StreakResponse {
        let items: [URLQueryItem] = date.map { [URLQueryItem(name: "date", value: $0)] } ?? []
        let url  = try buildURL(path: "/api/stats/streaks", queryItems: items)
        let data = try await fetchWithCache(url: url, key: "streak_data")
        return try APIService.decoder.decode(StreakResponse.self, from: data)
    }
}
