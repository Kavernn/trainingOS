import Foundation

extension APIService {
    func fetchSessionQuality() async throws -> SessionQualityData {
        let url  = try buildURL(path: "/api/session-quality")
        let data = try await fetchWithCache(url: url, key: "session_quality")
        return try APIService.decoder.decode(SessionQualityData.self, from: data)
    }
}
