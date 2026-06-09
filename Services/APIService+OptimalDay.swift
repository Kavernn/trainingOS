import Foundation

extension APIService {
    func fetchOptimalDay() async throws -> OptimalDayData {
        let url  = try buildURL(path: "/api/optimal_day")
        let data = try await fetchWithCache(url: url, key: "optimal_day")
        return try APIService.decoder.decode(OptimalDayData.self, from: data)
    }
}
