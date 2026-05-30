import Foundation

extension APIService {
    // MARK: - Cardio
    func fetchCardioData() async throws -> [CardioEntry] {
        let url = URL(string: "\(baseURL)/api/cardio_data")!
        let data = try await fetchWithCache(url: url, key: "cardio_data")
        struct Resp: Codable {
            let cardioLog: [CardioEntry]
            enum CodingKeys: String, CodingKey { case cardioLog = "cardio_log" }
        }
        return try JSONDecoder().decode(Resp.self, from: data).cardioLog
    }

    func logCardio(type: String, durationMin: Double?, distanceKm: Double?,
                   avgPace: String?, avgHr: Double?, cadence: Double?,
                   calories: Double?, rpe: Double?, notes: String,
                   startTime: String? = nil, endTime: String? = nil,
                   paceAvgSeconds: Int? = nil,
                   gpsPoints: [[String: Double]]? = nil,
                   coachNote: String? = nil) async throws {
        var body: [String: Any] = ["type": type, "notes": notes]
        if let v = durationMin      { body["duration_min"]      = v }
        if let v = distanceKm       { body["distance_km"]       = v }
        if let v = avgPace          { body["avg_pace"]           = v }
        if let v = avgHr            { body["avg_hr"]             = v }
        if let v = cadence          { body["cadence"]            = v }
        if let v = calories         { body["calories"]           = v }
        if let v = rpe              { body["rpe"]                = v }
        if let v = startTime        { body["start_time"]         = v }
        if let v = endTime          { body["end_time"]           = v }
        if let v = paceAvgSeconds   { body["pace_avg_seconds"]   = v }
        if let v = gpsPoints        { body["gps_points"]         = v }
        if let v = coachNote        { body["coach_note"]         = v }
        _ = try await offlinePost(endpoint: "/api/log_cardio", payload: body)
    }

    func fetchCardioMetrics() async throws -> CardioMetrics {
        let url = URL(string: "\(baseURL)/api/cardio/metrics")!
        let data = try await fetchWithCache(url: url, key: "cardio_metrics")
        return try JSONDecoder().decode(CardioMetrics.self, from: data)
    }

    func deleteCardio(date: String, type: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_cardio",
                                  payload: ["date": date, "type": type])
        CacheService.shared.clear(for: "cardio_history")
        CacheService.shared.clear(for: "stats_cardio")
    }
}
