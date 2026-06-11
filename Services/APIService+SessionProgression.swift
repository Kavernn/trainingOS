import Foundation

extension APIService {
    func fetchSessionProgression() async throws -> SessionProgressionData {
        let url  = try buildURL(path: "/api/session-progression")
        let data = try await fetchWithCache(url: url, key: "session_progression")
        return try APIService.decoder.decode(SessionProgressionData.self, from: data)
    }
}
