import Foundation

extension APIService {
    func fetchTemporalPatterns() async throws -> TemporalPatterns {
        let url  = try buildURL(path: "/api/temporal_patterns")
        let data = try await fetchWithCache(url: url, key: "temporal_patterns")
        return try APIService.decoder.decode(TemporalPatterns.self, from: data)
    }
}
