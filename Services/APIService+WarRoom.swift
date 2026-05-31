import Foundation

extension APIService {

    // MARK: Config

    func getWarRoomConfig() async throws -> WarRoomConfig {
        let url  = try buildURL(path: "/api/war_room/config")
        let data = try await fetchWithCache(url: url, key: "war_room_config")
        return try JSONDecoder().decode(WarRoomConfig.self, from: data)
    }

    func updateWarRoomConfig(_ fields: [String: Any]) async throws {
        _ = try await offlinePost(endpoint: "/api/war_room/config", payload: fields)
        CacheService.shared.clear(for: "war_room_config")
    }

    // MARK: Summary

    func getWarRoomSummary() async throws -> WarRoomSummary {
        let url  = try buildURL(path: "/api/war_room/summary")
        let data = try await fetchWithCache(url: url, key: "war_room_summary")
        return try JSONDecoder().decode(WarRoomSummary.self, from: data)
    }

    // MARK: Battles

    func getWarRoomBattles(limit: Int = 90) async throws -> [WarRoomBattle] {
        let url  = try buildURL(path: "/api/war_room/battles", queryItems: [URLQueryItem(name: "limit", value: "\(limit)")])
        let data = try await fetchWithCache(url: url, key: "war_room_battles")
        return try JSONDecoder().decode([WarRoomBattle].self, from: data)
    }

    func upsertBattle(date: String, status: BattleStatus, notes: String? = nil) async throws -> WarRoomSummary {
        var body: [String: Any] = ["date": date, "status": status.rawValue]
        if let notes { body["notes"] = notes }
        let data = try await offlinePost(endpoint: "/api/war_room/battle", payload: body)
        CacheService.shared.clear(for: "war_room_summary")
        CacheService.shared.clear(for: "war_room_battles")
        guard let data else { throw APIError.queuedOffline }
        let resp = try JSONDecoder().decode(BattleUpsertResponse.self, from: data)
        return resp.summary
    }

    // MARK: Triggers

    func getWarRoomTriggers(limit: Int = 90) async throws -> [WarRoomTrigger] {
        let url  = try buildURL(path: "/api/war_room/triggers", queryItems: [URLQueryItem(name: "limit", value: "\(limit)")])
        let data = try await fetchWithCache(url: url, key: "war_room_triggers")
        return try JSONDecoder().decode([WarRoomTrigger].self, from: data)
    }

    func logTrigger(
        context: TriggerContext,
        intensity: Int,
        yielded: Bool,
        contextNote: String? = nil,
        heldWith: [String] = []
    ) async throws -> String {
        var body: [String: Any] = [
            "context":   context.rawValue,
            "intensity": intensity,
            "yielded":   yielded,
            "held_with": heldWith,
        ]
        if let note = contextNote, !note.isEmpty { body["context_note"] = note }
        let data = try await offlinePost(endpoint: "/api/war_room/trigger", payload: body)
        CacheService.shared.clear(for: "war_room_triggers")
        guard let data else { return "" }
        let resp = try JSONDecoder().decode(TriggerLogResponse.self, from: data)
        return resp.id
    }

    // MARK: Arsenal

    func getWarRoomArsenal() async throws -> [WarRoomArsenalItem] {
        let url  = try buildURL(path: "/api/war_room/arsenal")
        let data = try await fetchWithCache(url: url, key: "war_room_arsenal")
        return try JSONDecoder().decode([WarRoomArsenalItem].self, from: data)
    }

    func addArsenalItem(label: String, category: ArsenalCategory, sortOrder: Int = 0) async throws -> String {
        let body: [String: Any] = [
            "label": label, "category": category.rawValue, "sort_order": sortOrder,
        ]
        let data = try await offlinePost(endpoint: "/api/war_room/arsenal", payload: body)
        CacheService.shared.clear(for: "war_room_arsenal")
        guard let data else { return "" }
        let resp = try JSONDecoder().decode(ArsenalAddResponse.self, from: data)
        return resp.id
    }

    func deleteArsenalItem(_ id: String) async throws {
        _ = try await offlinePost(endpoint: "/api/war_room/arsenal/\(id)", method: "DELETE", payload: [:])
        CacheService.shared.clear(for: "war_room_arsenal")
    }

    func deployArsenalItem(_ id: String) async throws {
        _ = try await offlinePost(endpoint: "/api/war_room/arsenal/\(id)/deploy", payload: [:])
        CacheService.shared.clear(for: "war_room_arsenal")
    }

    // MARK: Patterns

    func getWarRoomPatterns() async throws -> WarRoomPatterns {
        let url  = try buildURL(path: "/api/war_room/patterns")
        let data = try await fetchWithCache(url: url, key: "war_room_patterns")
        return try JSONDecoder().decode(WarRoomPatterns.self, from: data)
    }

    // MARK: War Map

    func getWarMap() async throws -> [WarMapMonth] {
        let url  = try buildURL(path: "/api/war_room/map")
        let data = try await fetchWithCache(url: url, key: "war_room_map")
        return try JSONDecoder().decode([WarMapMonth].self, from: data)
    }
}

// MARK: - Private response types

private struct BattleUpsertResponse: Codable {
    let ok: Bool
    let summary: WarRoomSummary
}

private struct TriggerLogResponse: Codable {
    let ok: Bool
    let id: String
}

private struct ArsenalAddResponse: Codable {
    let ok: Bool
    let id: String
}
