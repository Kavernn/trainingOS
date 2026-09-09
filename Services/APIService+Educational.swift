import Foundation

extension APIService {

    /// - Parameter bypassCache: si true, requête réseau directe (ignore le cache
    ///   disque 24h). Le pool live remplace la copie cachée et est réécrit dans
    ///   la cache pour cohérence future. Utilisé pour vérifier l'épuisement
    ///   avant d'afficher "tu as tout parcouru" — sinon le calcul repose sur
    ///   une source figée jusqu'à 24h.
    func fetchEducationalContent(
        category: String? = nil,
        limit: Int = 100,
        bypassCache: Bool = false
    ) async throws -> [EducationalCapsule] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let c = category, !c.isEmpty {
            items.append(URLQueryItem(name: "category", value: c))
        }
        let url = try buildURL(path: "/api/educational/content", queryItems: items)
        // Séparateur "_" pour aligner sur la convention TTL par préfixe (CacheService.swift:114).
        let key = "educational_\(category ?? "all")"
        let data: Data
        if bypassCache {
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (fresh, resp) = try await URLSession.authed.data(for: req)
            guard (200...299).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else {
                throw URLError(.badServerResponse)
            }
            CacheService.shared.save(fresh, for: key)
            data = fresh
        } else {
            data = try await fetchWithCache(url: url, key: key)
        }
        return try APIService.decoder.decode([EducationalCapsule].self, from: data)
    }
}
