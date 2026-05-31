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

    func fetchSleepToday() async throws -> SleepEntry? {
        let url = try buildURL(path: "/api/sleep/today")
        let data = try await fetchWithCache(url: url, key: "sleep_today")
        if let entry = try? APIService.decoder.decode(SleepEntry.self, from: data) {
            return entry
        } else if !data.isEmpty && data != Data("null".utf8) {
            sleepLogger.warning("⚠️ fetchSleepToday decode failed — may indicate API schema change")
        }
        return nil
    }

    func fetchSleepStats() async throws -> SleepStats {
        let url = try buildURL(path: "/api/sleep/stats")
        let data = try await fetchWithCache(url: url, key: "sleep_stats")
        return try APIService.decoder.decode(SleepStats.self, from: data)
    }

    func logSleep(bedtime: String, wakeTime: String, quality: Int,
                  notes: String?, date: String? = nil) async throws -> SleepEntry {
        var body: [String: Any] = ["bedtime": bedtime, "wake_time": wakeTime, "quality": quality]
        if let notes = notes, !notes.isEmpty { body["notes"] = notes }
        if let d = date { body["date"] = d }
        guard let data = try await offlinePost(endpoint: "/api/sleep/log", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheInvalidation.sleepMutated.invalidate()
        return try APIService.decoder.decode(SleepEntry.self, from: data)
    }

    func deleteSleepEntry(id: String) async throws {
        _ = try await offlinePost(endpoint: "/api/sleep/delete", payload: ["id": id])
        CacheInvalidation.sleepMutated.invalidate()
    }
}
