import Foundation

extension APIService {
    func fetchVelocity() async throws -> VelocityData {
        let url  = try buildURL(path: "/api/velocity")
        let data = try await fetchWithCache(url: url, key: "velocity")
        return try APIService.decoder.decode(VelocityData.self, from: data)
    }
}
