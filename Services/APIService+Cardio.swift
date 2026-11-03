import Foundation

/// Enveloppe du cache `cardio_data`. Exposée pour que le seed d'un
/// `Loadable<[CardioEntry]>` puisse decoder le payload stocké et
/// extraire `.cardioLog` côté appelant.
struct CardioDataResponse: Codable {
    let cardioLog: [CardioEntry]
    enum CodingKeys: String, CodingKey { case cardioLog = "cardio_log" }
}

extension APIService {
    static let cardioDataCacheKey    = "cardio_data"
    static let cardioMetricsCacheKey = "cardio_metrics"

    // MARK: - Cardio
    func fetchCardioData(forceRefresh: Bool = false) async throws -> [CardioEntry] {
        let url = try buildURL(path: "/api/cardio_data")
        let data = try await fetchWithCache(url: url, key: Self.cardioDataCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode(CardioDataResponse.self, from: data).cardioLog
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
        CacheInvalidation.cardioLogged.invalidate()
    }

    func fetchCardioMetrics(maxHR: Int, forceRefresh: Bool = false) async throws -> CardioMetrics {
        let url = try buildURL(path: "/api/cardio/metrics", queryItems: [URLQueryItem(name: "max_hr", value: "\(maxHR)")])
        let data = try await fetchWithCache(url: url, key: Self.cardioMetricsCacheKey, forceRefresh: forceRefresh)
        return try APIService.decoder.decode(CardioMetrics.self, from: data)
    }

    func deleteCardio(date: String, type: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_cardio",
                                  payload: ["date": date, "type": type])
        CacheInvalidation.cardioLogged.invalidate()
    }
}
