import Foundation

extension APIService {

    func fetchCapsuleSnapshot() async throws -> CapsuleSnapshot {
        let url = URL(string: "\(baseURL)/api/time_capsule/snapshot")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.authed.data(for: req)
        guard (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(CapsuleSnapshot.self, from: data)
    }

    func fetchTimeCapsules() async throws -> [TimeCapsule] {
        let url  = URL(string: "\(baseURL)/api/time_capsule")!
        let data = try await fetchWithCache(url: url, key: "time_capsules")
        return try JSONDecoder().decode(TimeCapsuleListResponse.self, from: data).capsules
    }

    func createTimeCapsule(durationMonths: Int, message: String?) async throws -> TimeCapsule {
        let url = URL(string: "\(baseURL)/api/time_capsule")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["duration_months": durationMonths]
        if let msg = message, !msg.isEmpty { body["message"] = msg }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.authed.data(for: req)
        guard (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw URLError(.badServerResponse)
        }
        CacheService.shared.clear(for: "time_capsules")
        CacheService.shared.clear(for: "capsule_snapshot")
        return try JSONDecoder().decode(TimeCapsule.self, from: data)
    }

    func openTimeCapsule(id: String) async throws -> TimeCapsule {
        let url = URL(string: "\(baseURL)/api/time_capsule/\(id)/open")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        let (data, response) = try await URLSession.authed.data(for: req)
        guard (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw URLError(.badServerResponse)
        }
        CacheService.shared.clear(for: "time_capsules")
        return try JSONDecoder().decode(TimeCapsule.self, from: data)
    }
}
