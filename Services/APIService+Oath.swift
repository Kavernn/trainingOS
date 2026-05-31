import Foundation
import OSLog

private let oathLogger = Logger(subsystem: "TrainingOS", category: "api+oath")

extension APIService {

    func getCurrentOath() async throws -> OathModel? {
        let url  = try buildURL(path: "/api/oath/current")
        let data = try await fetchWithCache(url: url, key: "oath_current")
        if data.isEmpty || data == Data("{}".utf8) { return nil }
        return try JSONDecoder().decode(OathModel.self, from: data)
    }

    func getOathVersions() async throws -> [OathModel] {
        let url  = try buildURL(path: "/api/oath/versions")
        let data = try await fetchWithCache(url: url, key: "oath_versions")
        return try JSONDecoder().decode([OathModel].self, from: data)
    }

    func saveOath(text: String, wordCount: Int) async throws -> OathModel? {
        let body: [String: Any] = ["text": text, "word_count": wordCount]
        guard let data = try await offlinePost(endpoint: "/api/oath", payload: body) else { return nil }
        CacheInvalidation.oathUpdated.invalidate()
        return try JSONDecoder().decode(OathModel.self, from: data)
    }

    func logOathRecall(oathId: String, trigger: String) async throws {
        let body: [String: Any] = ["oath_id": oathId, "trigger": trigger]
        _ = try await offlinePost(endpoint: "/api/oath/recall", payload: body)
    }
}
