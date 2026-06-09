import Foundation

extension APIService {
    func fetchIdealWeek() async throws -> IdealWeekData {
        let url  = try buildURL(path: "/api/ideal_week")
        let data = try await fetchWithCache(url: url, key: "ideal_week")
        return try APIService.decoder.decode(IdealWeekData.self, from: data)
    }
}
