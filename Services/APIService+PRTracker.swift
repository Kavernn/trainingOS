import Foundation

extension APIService {
    func fetchPRTracker() async throws -> PRTrackerData {
        let url  = try buildURL(path: "/api/pr-tracker")
        let data = try await fetchWithCache(url: url, key: "pr_tracker")
        return try APIService.decoder.decode(PRTrackerData.self, from: data)
    }
}
