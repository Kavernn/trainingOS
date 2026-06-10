import Foundation

extension APIService {
    func fetchSleepQuality() async throws -> SleepQualityData {
        let url  = try buildURL(path: "/api/sleep-quality")
        let data = try await fetchWithCache(url: url, key: "sleep_quality")
        return try APIService.decoder.decode(SleepQualityData.self, from: data)
    }
}
