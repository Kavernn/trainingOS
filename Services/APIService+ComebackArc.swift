import Foundation

extension APIService {
    func fetchComebackArc() async throws -> ComebackArcData {
        let url  = try buildURL(path: "/api/comeback_arc")
        let data = try await fetchWithCache(url: url, key: "comeback_arc")
        return try APIService.decoder.decode(ComebackArcData.self, from: data)
    }
}
