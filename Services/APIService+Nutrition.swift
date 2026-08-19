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

    func fetchNutritionDay(date: String) async throws -> NutritionDaySummary {
        let url = try buildURL(path: "/api/nutrition",
                               queryItems: [URLQueryItem(name: "date", value: date)])
        let (data, _) = try await URLSession.authed.data(from: url)
        return try APIService.decoder.decode(NutritionDaySummary.self, from: data)
    }

    func postYesterdayEstimate(pctCalories: Double, pctProteines: Double) async throws {
        // Bypass offlinePost : le serveur calcule "yesterday" à l'exécution.
        // Un replay différé (SyncManager) écrirait pour la mauvaise date.
        // Fail loud sur réseau ; le sheet gère le retry manuel.
        let url = try buildURL(path: "/api/nutrition/estimate_yesterday")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
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

    func updateNutritionSettings(calories: Double, proteines: Double, glucides: Double,
                                  lipides: Double,
                                  dayTypeTargets: [String: [String: Int]]? = nil,
                                  nutritionEndTime: String? = nil) async throws {
        var payload: [String: Any] = [
            "limite_calories":    Int(calories),
            "objectif_proteines": Int(proteines),
            "glucides":           glucides,
            "lipides":            lipides,
        ]
        if let dtt = dayTypeTargets { payload["day_type_targets"] = dtt }
        if let t   = nutritionEndTime { payload["nutrition_end_time"] = t }
        _ = try await offlinePost(endpoint: "/api/nutrition/settings", payload: payload)
        // Targets changent → toutes les données dérivées (nutrition_data, dashboard,
        // readiness, morning_brief) doivent être recalculées.
        CacheInvalidation.nutritionLogged.invalidate()
    }

    // MARK: - Food Catalog
    func fetchFoodCatalog() async -> [FoodItem] {
        guard let url = URL(string: "\(baseURL)/api/food_catalog"),
              let data = try? await fetchWithCache(url: url, key: "food_catalog") else { return [] }
        return FoodCatalogStore.decodeFromAPI(data)
    }

    func saveFoodCatalog(_ items: [FoodItem]) async throws {
        let itemDicts: [[String: Any]] = items
            .filter { !$0.isBuiltIn }
            .map { ["id":        $0.id.uuidString,
                    "name":      $0.name,
                    "ref_qty":   $0.refQty,
                    "ref_unit":  $0.refUnit,
                    "calories":  $0.calories,
                    "proteines": $0.proteines,
                    "glucides":  $0.glucides,
                    "lipides":   $0.lipides,
                    "category":  $0.category] }
        _ = try await offlinePost(endpoint: "/api/food_catalog", payload: ["items": itemDicts])
        CacheInvalidation.foodCatalogUpdated.invalidate()
    }

    // MARK: - Meal Templates
    func fetchMealTemplates() async -> [MealTemplate] {
        guard let url = URL(string: "\(baseURL)/api/meal_templates"),
              let (data, _) = try? await URLSession.authed.data(from: url) else { return [] }
        struct Resp: Decodable { let templates: [MealTemplate] }
        do {
            return try APIService.decoder.decode(Resp.self, from: data).templates
        } catch {
            nutritionLogger.error("❌ fetchMealTemplates decode failed: \(error, privacy: .public)")
            return []
        }
    }

    func createMealTemplate(name: String, items: [MealTemplateItem]) async throws -> MealTemplate {
        struct Resp: Decodable { let template: MealTemplate }
        let itemDicts: [[String: Any]] = items.map {
            ["name": $0.name, "calories": $0.calories,
             "proteines": $0.proteines, "glucides": $0.glucides, "lipides": $0.lipides]
        }
        guard let data = try await offlinePost(endpoint: "/api/meal_templates",
                                               payload: ["name": name, "items": itemDicts]) else {
            throw APIError.queuedOffline
        }
        return try APIService.decoder.decode(Resp.self, from: data).template
    }

    // Templates non cachées (fetchMealTemplates n'utilise pas fetchWithCache) —
    // rien à invalider sur update/delete.
    func updateMealTemplate(id: String, name: String, items: [MealTemplateItem]) async throws {
        let itemDicts: [[String: Any]] = items.map {
            ["name": $0.name, "calories": $0.calories,
             "proteines": $0.proteines, "glucides": $0.glucides, "lipides": $0.lipides]
        }
        _ = try await offlinePost(endpoint: "/api/meal_templates/\(id)/update",
                                  payload: ["name": name, "items": itemDicts])
    }

    func deleteMealTemplate(_ id: String) async throws {
        _ = try await offlinePost(endpoint: "/api/meal_templates/\(id)/delete", payload: [:])
    }

    func logMealTemplate(_ id: String, mealType: String) async throws {
        _ = try await offlinePost(endpoint: "/api/meal_templates/\(id)/log",
                                  payload: ["meal_type": mealType])
        UserDefaults.standard.set(DateFormatter.isoDate.string(from: Date()), forKey: "nutrition.last.log.date")
        NotificationService.cancelNutritionReminder()
        CacheInvalidation.nutritionLogged.invalidate()
    }
}

