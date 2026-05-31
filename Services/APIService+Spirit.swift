import Foundation

extension APIService {

    // MARK: Config

    func getSpiritConfig() async throws -> SpiritConfig {
        let url  = try buildURL(path: "/api/spirit/config")
        let data = try await fetchWithCache(url: url, key: "spirit_config")
        return try JSONDecoder().decode(SpiritConfig.self, from: data)
    }

    func updateSpiritConfig(_ fields: [String: Any]) async throws {
        _ = try await offlinePost(endpoint: "/api/spirit/config", payload: fields)
        CacheService.shared.clear(for: "spirit_config")
    }

    // MARK: Breathwork

    func getSpiritBreathSessions(limit: Int = 60) async throws -> [SpiritBreathSession] {
        let url  = try buildURL(path: "/api/spirit/breathwork", queryItems: [URLQueryItem(name: "limit", value: "\(limit)")])
        let data = try await fetchWithCache(url: url, key: "spirit_breathwork")
        return try JSONDecoder().decode([SpiritBreathSession].self, from: data)
    }

    func logBreathwork(
        protocol p: BreathworkProtocol,
        durationSec: Int,
        cycles: Int,
        triggeredFrom: String = "standalone"
    ) async throws {
        let body: [String: Any] = [
            "protocol":       p.rawValue,
            "duration_sec":   durationSec,
            "cycles":         cycles,
            "triggered_from": triggeredFrom,
        ]
        _ = try await offlinePost(endpoint: "/api/spirit/breathwork", payload: body)
        CacheService.shared.clear(for: "spirit_breathwork")
    }

    // MARK: Meditation

    func getMeditationSessions(limit: Int = 60) async throws -> [MeditationSession] {
        let url  = try buildURL(path: "/api/spirit/meditation", queryItems: [URLQueryItem(name: "limit", value: "\(limit)")])
        let data = try await fetchWithCache(url: url, key: "spirit_meditation")
        return try JSONDecoder().decode([MeditationSession].self, from: data)
    }

    func logMeditation(plannedSec: Int, actualSec: Int, bellInterval: Int, completed: Bool) async throws {
        let body: [String: Any] = [
            "planned_sec":   plannedSec,
            "actual_sec":    actualSec,
            "bell_interval": bellInterval,
            "completed":     completed,
        ]
        _ = try await offlinePost(endpoint: "/api/spirit/meditation", payload: body)
        CacheService.shared.clear(for: "spirit_meditation")
    }

    // MARK: Journal

    func getSpiritJournalStubs(limit: Int = 30) async throws -> [SpiritJournalStub] {
        let url  = try buildURL(path: "/api/spirit/journal", queryItems: [URLQueryItem(name: "limit", value: "\(limit)")])
        let data = try await fetchWithCache(url: url, key: "spirit_journal_list")
        return try JSONDecoder().decode([SpiritJournalStub].self, from: data)
    }

    func getSpiritJournalEntry(date: String) async throws -> SpiritJournalEntry? {
        guard let url = URL(string: "\(baseURL)/api/spirit/journal/\(date)") else { return nil }
        let cacheKey = "spirit_journal_\(date)"
        let data = try await fetchWithCache(url: url, key: cacheKey)
        if data.isEmpty || data == Data("{}".utf8) { return nil }
        return try? JSONDecoder().decode(SpiritJournalEntry.self, from: data)
    }

    func saveSpiritJournal(date: String, gratefulFor: String?, conquered: String?, haunting: String?) async throws {
        var body: [String: Any] = ["date": date]
        if let g = gratefulFor, !g.isEmpty { body["grateful_for"] = g }
        if let c = conquered,   !c.isEmpty { body["conquered"]    = c }
        if let h = haunting,    !h.isEmpty { body["haunting"]      = h }
        _ = try await offlinePost(endpoint: "/api/spirit/journal", payload: body)
        CacheService.shared.clear(for: "spirit_journal_list")
    }

    // MARK: Patterns

    func getSpiritPatterns() async throws -> SpiritPatterns {
        let url  = try buildURL(path: "/api/spirit/patterns")
        let data = try await fetchWithCache(url: url, key: "spirit_patterns")
        return try JSONDecoder().decode(SpiritPatterns.self, from: data)
    }
}
