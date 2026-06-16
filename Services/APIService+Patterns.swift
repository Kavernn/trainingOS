import Foundation

extension APIService {

    func fetchPatterns() async throws -> PatternResponse {
        let url  = try buildURL(path: "/api/patterns/daily")
        let data = try await fetchWithCache(url: url, key: "patterns_daily")
        return try APIService.decoder.decode(PatternResponse.self, from: data)
    }

    func pinPattern(id: String) async throws {
        _ = try await offlinePost(
            endpoint: "/api/patterns/pin",
            payload: ["pattern_id": id]
        )
        CacheInvalidation.patternsPinMutated.invalidate()
    }

    func unpinPattern(id: String) async throws {
        _ = try await offlinePost(
            endpoint: "/api/patterns/pin/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)",
            method: "DELETE",
            payload: [:]
        )
        CacheInvalidation.patternsPinMutated.invalidate()
    }

}
