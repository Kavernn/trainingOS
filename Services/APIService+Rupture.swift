import Foundation

extension APIService {
    func fetchRuptureRisk() async throws -> RuptureRisk {
        let url  = try buildURL(path: "/api/rupture_risk")
        let data = try await fetchWithCache(url: url, key: "rupture_risk")
        return try APIService.decoder.decode(RuptureRisk.self, from: data)
    }
}
