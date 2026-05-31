import Foundation

extension APIService {
    func fetchReadiness() async throws -> ReadinessResponse {
        let url  = try buildURL(path: "/api/readiness")
        let data = try await fetchWithCache(url: url, key: "readiness")
        return try APIService.decoder.decode(ReadinessResponse.self, from: data)
    }
}
