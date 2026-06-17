import Foundation

struct WeeklyTonnageData: Codable {
    let volume: Int
}

extension APIService {
    func fetchWeeklyTonnage() async throws -> WeeklyTonnageData {
        let url  = try buildURL(path: "/api/weekly-tonnage")
        let data = try await fetchWithCache(url: url, key: "weekly_tonnage")
        return try APIService.decoder.decode(WeeklyTonnageData.self, from: data)
    }
}
