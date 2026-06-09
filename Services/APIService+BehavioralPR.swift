import Foundation

extension APIService {
    func fetchBehavioralPRs() async throws -> BehavioralPRsData {
        let url  = try buildURL(path: "/api/behavioral_prs")
        let data = try await fetchWithCache(url: url, key: "behavioral_prs")
        return try APIService.decoder.decode(BehavioralPRsData.self, from: data)
    }
}
