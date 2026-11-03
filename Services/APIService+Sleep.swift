import Foundation
import OSLog

private let sleepLogger = Logger(subsystem: "TrainingOS", category: "api+sleep")

extension APIService {
    static func sleepHistoryCacheKey(offset: Int = 0) -> String {
        offset == 0 ? "sleep_history" : "sleep_history_\(offset)"
    }

    static let sleepStatsCacheKey = "sleep_stats"

    // MARK: - Sommeil
    func fetchSleepHistory(limit: Int = 20,
                           offset: Int = 0,
                           forceRefresh: Bool = false) async throws -> PagedResponse<SleepEntry> {
        let url = try buildURL(path: "/api/sleep/history", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        let data = try await fetchWithCache(url: url, key: Self.sleepHistoryCacheKey(offset: offset), forceRefresh: forceRefresh)
        return try APIService.decoder.decode(PagedResponse<SleepEntry>.self, from: data)
    }

    func fetchSleepStats(forceRefresh: Bool = false) async throws -> SleepStats {
        let url = try buildURL(path: "/api/sleep/stats")
        let data = try await fetchWithCache(url: url, key: Self.sleepStatsCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode(SleepStats.self, from: data)
    }


}
