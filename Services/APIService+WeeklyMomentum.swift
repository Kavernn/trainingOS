import Foundation

extension APIService {
    func fetchWeeklyMomentum() async throws -> WeeklyMomentumData {
        let url  = try buildURL(path: "/api/weekly_momentum")
        let data = try await fetchWithCache(url: url, key: "weekly_momentum")
        return try APIService.decoder.decode(WeeklyMomentumData.self, from: data)
    }
}
