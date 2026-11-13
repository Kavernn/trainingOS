import Foundation
import OSLog
import UserNotifications

private let nutritionLogger = Logger(subsystem: "TrainingOS", category: "api+nutrition")

extension APIService {
    // MARK: - Nutrition
    func fetchNutritionHistory() async throws -> [NutritionDayHistory] {
        let url = try buildURL(path: "/api/nutrition_data")
        let data = try await fetchWithCache(url: url, key: "nutrition_data")
        return try APIService.decoder.decode(NutritionDataResponse.self, from: data).history
    }

    /// Full nutrition payload — expose `todayType` (source unique serveur) en plus de l'historique.
    /// Même cache key que `fetchNutritionHistory` → un seul roundtrip pour les deux consommateurs.
    func fetchNutritionDetail() async throws -> NutritionDataResponse {
        let url = try buildURL(path: "/api/nutrition_data")
        let data = try await fetchWithCache(url: url, key: "nutrition_data")
        return try APIService.decoder.decode(NutritionDataResponse.self, from: data)
    }

    func fetchNutritionDay(date: String, includeTarget: Bool = false) async throws -> NutritionDaySummary {
        let url = try buildURL(path: "/api/nutrition",
                               queryItems: [URLQueryItem(name: "date", value: date),
                                            URLQueryItem(name: "include_target", value: includeTarget ? "true" : "false")])
        let (data, _) = try await URLSession.authed.data(from: url)
        return try APIService.decoder.decode(NutritionDaySummary.self, from: data)
    }

    /// Historique nutrition sur `days` jours — macros + target_calories par jour.
    /// Fail loud : erreur → throw. L'appelant distingue "chargement" / "erreur" /
    /// "données" via l'état iOS (pas de try? silencieux côté caller).
    func fetchStatsNutritionHistory(days: Int) async throws -> [DayNutritionHistory] {
        let url = try buildURL(path: "/api/stats/nutrition_history",
                               queryItems: [URLQueryItem(name: "days", value: String(days))])
        let (data, _) = try await URLSession.authed.data(from: url)
        return try APIService.decoder.decode([DayNutritionHistory].self, from: data)
    }

    func postYesterdayEstimate(estimate: NutritionCatchupEstimate, pctCalories: Double, pctProteines: Double) async throws {
        // Bypass offlinePost : conserver le retry manuel de cette écriture datée.
        // Fail loud sur réseau ; le sheet gère le retry manuel.
        let url = try buildURL(path: "/api/nutrition/estimate_yesterday")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "date": estimate.date,
            "calories": estimate.calories,
            "proteines": estimate.proteines,
            "pct_calories":  pctCalories,
            "pct_proteines": pctProteines,
        ])
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.authed.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let parsed = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let msg = (parsed["error"] as? String)
                  ?? (parsed["message"] as? String)
                  ?? "HTTP \(http.statusCode)"
            throw APIError.serverError(http.statusCode, msg)
        }
        CacheInvalidation.nutritionLogged.invalidate()
    }

    func deleteNutritionEntry(id: String) async throws {
        _ = try await offlinePost(endpoint: "/api/nutrition/delete", payload: ["id": id])
        CacheInvalidation.nutritionLogged.invalidate()
    }

    func addNutritionEntry(name: String, calories: Double, proteines: Double,
                           glucides: Double, lipides: Double, mealType: String? = nil,
                           source: String = "manual", date: String? = nil) async throws {
        var payload: [String: Any] = [
            "nom": name, "calories": calories,
            "proteines": proteines, "glucides": glucides, "lipides": lipides,
            "source": source
        ]
        if let mt = mealType { payload["meal_type"] = mt }
        if let d  = date     { payload["date"] = d }
        _ = try await offlinePost(endpoint: "/api/nutrition/add", payload: payload)
        CacheInvalidation.nutritionLogged.invalidate()
        UserDefaults.standard.set(DateFormatter.isoDate.string(from: Date()), forKey: "nutrition.last.log.date")
        NotificationService.cancelNutritionReminder()
        BehaviorTracker.shared.record(.nutritionLog)
    }

    func updateNutritionSettings(calories: Double, proteines: Double,
                                  dayTypeTargets: [String: [String: Int]]? = nil,
                                  nutritionEndTime: String? = nil) async throws {
        var payload: [String: Any] = [
            "limite_calories":    Int(calories),
            "objectif_proteines": Int(proteines),
        ]
        if let dtt = dayTypeTargets { payload["day_type_targets"] = dtt }
        if let t   = nutritionEndTime { payload["nutrition_end_time"] = t }
        _ = try await offlinePost(endpoint: "/api/nutrition/settings", payload: payload)
        // Targets changent → toutes les données dérivées (nutrition_data, dashboard,
        // readiness, morning_brief) doivent être recalculées.
        CacheInvalidation.nutritionLogged.invalidate()
    }

}

