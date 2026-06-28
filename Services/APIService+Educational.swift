import Foundation

extension APIService {

    func fetchEducationalContent(
        category: String? = nil,
        limit: Int = 100
    ) async throws -> [EducationalCapsule] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let c = category, !c.isEmpty {
            items.append(URLQueryItem(name: "category", value: c))
        }
        let url  = try buildURL(path: "/api/educational/content", queryItems: items)
        let key  = "educational:\(category ?? "all")"
        let data = try await fetchWithCache(url: url, key: key)
        return try APIService.decoder.decode([EducationalCapsule].self, from: data)
    }
}
