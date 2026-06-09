import Foundation

extension APIService {
    func fetchSleepHRV() async throws -> SleepHRVData {
        let url  = try buildURL(path: "/api/sleep-hrv")
        let data = try await fetchWithCache(url: url, key: "sleep_hrv")
        return try APIService.decoder.decode(SleepHRVData.self, from: data)
    }
}
