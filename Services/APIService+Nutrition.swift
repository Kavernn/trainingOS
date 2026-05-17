import Foundation

extension APIService {
    // MARK: - Nutrition
    func fetchNutritionData() async throws -> (settings: NutritionSettings?,
                                               entries: [NutritionEntry],
                                               totals: NutritionTotals?) {
        let url = URL(string: "\(baseURL)/api/nutrition_data")!
        let data = try await fetchWithCache(url: url, key: "nutrition_data")
        struct NutrResponse: Codable {
            let settings: NutritionSettings?
            let entries: [NutritionEntry]
            let totals: NutritionTotals?
        }
        let r = try JSONDecoder().decode(NutrResponse.self, from: data)
        return (r.settings, r.entries, r.totals)
    }

    func fetchNutritionHistory() async throws -> [NutritionDayHistory] {
        let url = URL(string: "\(baseURL)/api/nutrition_data")!
        let data = try await fetchWithCache(url: url, key: "nutrition_data")
        return try JSONDecoder().decode(NutritionDataResponse.self, from: data).history
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
        BehaviorTracker.shared.record(.nutritionLog)
    }

    func scanNutritionLabel(imageBase64: String, quantity: Double, unit: String) async throws -> ScanResult {
        let url = URL(string: "\(baseURL)/api/nutrition/scan-label")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        let payload: [String: Any] = [
            "image_base64": imageBase64,
            "media_type":   "image/jpeg",
            "quantity":     quantity,
            "unit":         unit
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                      ?? "Erreur serveur (\(http.statusCode))"
            throw ScanLabelError(message: msg)
        }
        return try JSONDecoder().decode(ScanResult.self, from: data)
    }

    func scanBarcode(_ code: String) async throws -> BarcodeResult {
        guard let url = URL(string: "\(baseURL)/api/food/barcode/\(code)") else {
            throw URLError(.badURL)
        }
        let (data, resp) = try await URLSession.authed.data(from: url)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 || http.statusCode == 503 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                      ?? "Produit introuvable"
            throw ScanLabelError(message: msg)
        }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(BarcodeResult.self, from: data)
    }

    func updateNutritionSettings(calories: Double, proteines: Double, glucides: Double,
                                  lipides: Double,
                                  dayTypeTargets: [String: [String: Int]]? = nil) async throws {
        var payload: [String: Any] = [
            "limite_calories":    Int(calories),
            "objectif_proteines": Int(proteines),
            "glucides":           glucides,
            "lipides":            lipides,
        ]
        if let dtt = dayTypeTargets { payload["day_type_targets"] = dtt }
        _ = try await offlinePost(endpoint: "/api/nutrition/settings", payload: payload)
    }

    // MARK: - Food Catalog
    func fetchFoodCatalog() async -> [FoodItem] {
        guard let url = URL(string: "\(baseURL)/api/food_catalog"),
              let data = try? await fetchWithCache(url: url, key: "food_catalog") else { return [] }
        return FoodCatalogStore.decodeFromAPI(data)
    }

    func saveFoodCatalog(_ items: [FoodItem]) async {
        guard let url = URL(string: "\(baseURL)/api/food_catalog"),
              let body = FoodCatalogStore.encodeForAPI(items) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 15
        _ = try? await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "food_catalog")
    }

    // MARK: - Meal Templates
    func fetchMealTemplates() async -> [MealTemplate] {
        guard let url = URL(string: "\(baseURL)/api/meal_templates"),
              let (data, _) = try? await URLSession.authed.data(from: url) else { return [] }
        struct Resp: Decodable { let templates: [MealTemplate] }
        return (try? JSONDecoder().decode(Resp.self, from: data))?.templates ?? []
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
        return try JSONDecoder().decode(Resp.self, from: data).template
    }

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
    }
}

// MARK: - Scan & Barcode models

struct ScanResult: Decodable {
    let nom:       String
    let calories:  Int
    let proteines: Double
    let glucides:  Double
    let lipides:   Double
    let fibres:    Double
    let sodiumMg:  Double
    enum CodingKeys: String, CodingKey {
        case nom, calories, proteines, glucides, lipides, fibres
        case sodiumMg = "sodium_mg"
    }
}

struct ScanLabelError: Error {
    let message: String
}

struct BarcodeResult: Decodable {
    let nom: String
    let servingSize: String?
    let per100g: MacroSet
    let perServing: MacroSet?

    struct MacroSet: Decodable {
        let calories: Int
        let proteines: Double
        let glucides: Double
        let lipides: Double
    }

    enum CodingKeys: String, CodingKey {
        case nom
        case servingSize = "serving_size"
        case per100g     = "per_100g"
        case perServing  = "per_serving"
    }
}
