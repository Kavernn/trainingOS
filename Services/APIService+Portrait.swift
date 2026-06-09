import Foundation

extension APIService {
    func fetchPortraitJ90() async throws -> PortraitData {
        let url  = try buildURL(path: "/api/portrait_j90")
        let data = try await fetchWithCache(url: url, key: "portrait_j90")
        return try APIService.decoder.decode(PortraitData.self, from: data)
    }
}
