import Foundation

extension APIService {
    func fetchSorenessFatigue() async throws -> SorenessFatigueData {
        let url  = try buildURL(path: "/api/soreness-fatigue")
        let data = try await fetchWithCache(url: url, key: "soreness_fatigue")
        return try APIService.decoder.decode(SorenessFatigueData.self, from: data)
    }
}
