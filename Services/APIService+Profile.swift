import Foundation

extension APIService {
    // MARK: - Body Weight / Profil
    func fetchProfilData() async throws -> (profile: UserProfile, bodyWeight: [BodyWeightEntry], tendance: String) {
        let url = URL(string: "\(baseURL)/api/profil_data")!
        let data = try await fetchWithCache(url: url, key: "profil_data")
        struct ProfilResponse: Codable {
            let profile: UserProfile
            let bodyWeight: [BodyWeightEntry]
            let tendance: String
            enum CodingKeys: String, CodingKey {
                case profile; case bodyWeight = "body_weight"; case tendance
            }
        }
        let r = try JSONDecoder().decode(ProfilResponse.self, from: data)
        return (r.profile, r.bodyWeight, r.tendance)
    }

    func addBodyWeight(date: String, weight: Double, bodyFat: Double?,
                       waistCm: Double?, neckCm: Double? = nil,
                       armsCm: Double? = nil, chestCm: Double? = nil,
                       thighsCm: Double? = nil, hipsCm: Double? = nil) async throws {
        var body: [String: Any] = ["poids": weight]
        if let v = bodyFat  { body["body_fat"]  = v }
        if let v = waistCm  { body["waist_cm"]  = v }
        if let v = neckCm   { body["neck_cm"]   = v }
        if let v = armsCm   { body["arms_cm"]   = v }
        if let v = chestCm  { body["chest_cm"]  = v }
        if let v = thighsCm { body["thighs_cm"] = v }
        if let v = hipsCm   { body["hips_cm"]   = v }
        _ = try await offlinePost(endpoint: "/api/body_weight", payload: body)
        CacheService.shared.clear(for: "profil_data")
        await BodyCompService.shared.refresh()
    }

    func updateBodyWeight(date: String, oldWeight: Double, newWeight: Double,
                          bodyFat: Double?, waistCm: Double?, neckCm: Double? = nil,
                          armsCm: Double? = nil, chestCm: Double? = nil,
                          thighsCm: Double? = nil, hipsCm: Double? = nil) async throws {
        var body: [String: Any] = ["date": date, "old_poids": oldWeight, "poids": newWeight]
        if let v = bodyFat  { body["body_fat"]  = v }
        if let v = waistCm  { body["waist_cm"]  = v }
        if let v = neckCm   { body["neck_cm"]   = v }
        if let v = armsCm   { body["arms_cm"]   = v }
        if let v = chestCm  { body["chest_cm"]  = v }
        if let v = thighsCm { body["thighs_cm"] = v }
        if let v = hipsCm   { body["hips_cm"]   = v }
        _ = try await offlinePost(endpoint: "/api/body_weight/update", payload: body)
        CacheService.shared.clear(for: "profil_data")
        await BodyCompService.shared.refresh()
    }

    func deleteBodyWeight(date: String, weight: Double) async throws {
        _ = try await offlinePost(endpoint: "/api/body_weight/delete",
                                  payload: ["date": date, "poids": weight])
        CacheService.shared.clear(for: "profil_data")
        await BodyCompService.shared.refresh()
    }

    func updateProfile(name: String?, weight: Double?, height: Double?, age: Int?,
                       goal: String?, level: String?, sex: String?) async throws {
        var body: [String: Any] = [:]
        if let v = name   { body["name"]   = v }
        if let v = weight { body["weight"] = v }
        if let v = height { body["height"] = v }
        if let v = age    { body["age"]    = v }
        if let v = goal   { body["goal"]   = v }
        if let v = level  { body["level"]  = v }
        if let v = sex    { body["sex"]    = v }
        _ = try await offlinePost(endpoint: "/api/update_profile", payload: body)
    }

    // MARK: - Weights
    func fetchWeights() async throws -> [String: WeightData] {
        let url = URL(string: "\(baseURL)/api/weights")!
        let data = try await fetchWithCache(url: url, key: "weights")
        return try JSONDecoder().decode([String: WeightData].self, from: data)
    }

    func fetchExerciseWeightData(name: String) async throws -> WeightData? {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "\(baseURL)/api/weights?exercise=\(encoded)") else { return nil }
        let (data, _) = try await URLSession.authed.data(from: url)
        let dict = try JSONDecoder().decode([String: WeightData].self, from: data)
        return dict[name]
    }

    func saveExercise(name: String, type: String, muscles: [String],
                      pattern: String, scheme: String, category: String) async throws {
        let payload: [String: Any] = [
            "name": name, "type": type, "muscles": muscles,
            "pattern": pattern, "default_scheme": scheme, "category": category,
        ]
        _ = try await offlinePost(endpoint: "/api/save_exercise", payload: payload)
        CacheService.shared.clear(for: "seance_data")
    }

    func setAllRestSeconds(_ seconds: Int) async throws {
        _ = try await offlinePost(endpoint: "/api/exercises/set_all_rest", payload: ["seconds": seconds])
    }

    func normalizeSchemes(maxSets: Int = 3) async throws {
        _ = try await offlinePost(endpoint: "/api/exercises/normalize_schemes", payload: ["max_sets": maxSets])
    }

    // MARK: - Wearable Sync
    func syncWearableData(_ snapshot: WearableSnapshot) async throws {
        var body: [String: Any] = ["date": snapshot.date]
        if let v = snapshot.steps         { body["steps"]           = v }
        if let v = snapshot.sleepHours    { body["sleep_hours"]     = v }
        if let v = snapshot.restingHr     { body["resting_hr"]      = v }
        if let v = snapshot.hrv           { body["hrv"]             = v }
        if let v = snapshot.activeEnergy  { body["active_energy"]   = v }
        if let v = snapshot.hrMorning     { body["hr_morning"]      = Int(v) }
        if let v = snapshot.hrPostWorkout { body["hr_post_workout"] = Int(v) }
        if let v = snapshot.hrEvening     { body["hr_evening"]      = Int(v) }
        let workouts: [[String: Any]] = snapshot.workouts.map { w in
            var entry: [String: Any] = ["type": w.type, "duration_min": w.durationMin]
            if let v = w.distanceKm { entry["distance_km"] = v }
            if let v = w.calories   { entry["calories"]    = v }
            if let v = w.avgHr      { entry["avg_hr"]      = v }
            if let v = w.avgPace    { entry["avg_pace"]    = v }
            return entry
        }
        body["workouts"] = workouts
        _ = try await offlinePost(endpoint: "/api/wearable/sync", payload: body)
        CacheService.shared.clear(for: "recovery_data")
        CacheService.shared.clear(for: "cardio_data")
    }

    // MARK: - Health Dashboard
    func fetchDailyHealthSummary(date: String? = nil) async throws -> DailyHealthSummary {
        var urlStr = "\(baseURL)/api/health/daily_summary"
        if let date { urlStr += "?date=\(date)" }
        let url = URL(string: urlStr)!
        let data = try await fetchWithCache(url: url, key: "health_daily_\(date ?? "today")")
        return try JSONDecoder().decode(DailyHealthSummary.self, from: data)
    }

    func fetchWeeklyHealthSummary(days: Int = 7) async throws -> [DailyHealthSummary] {
        let url = URL(string: "\(baseURL)/api/health/weekly_summary?days=\(days)")!
        let data = try await fetchWithCache(url: url, key: "health_weekly_\(days)")
        return try JSONDecoder().decode([DailyHealthSummary].self, from: data)
    }
}
