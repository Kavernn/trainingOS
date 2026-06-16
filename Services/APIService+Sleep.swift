import Foundation
import OSLog

private let sleepLogger = Logger(subsystem: "TrainingOS", category: "api+sleep")

extension APIService {
    // MARK: - Sommeil
    func fetchSleepHistory(limit: Int = 20,
                           offset: Int = 0) async throws -> PagedResponse<SleepEntry> {
        let cacheKey = offset == 0 ? "sleep_history" : "sleep_history_\(offset)"
        let url = try buildURL(path: "/api/sleep/history", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try APIService.decoder.decode(PagedResponse<SleepEntry>.self, from: data)
    }

    func fetchSleepStats() async throws -> SleepStats {
        let url = try buildURL(path: "/api/sleep/stats")
        let data = try await fetchWithCache(url: url, key: "sleep_stats")
        return try APIService.decoder.decode(SleepStats.self, from: data)
    }


}
