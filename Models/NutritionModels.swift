import Foundation

// MARK: - Nutrition Totals
struct NutritionTotals: Codable {
    let calories: Double?
    let proteines: Double?
    let glucides: Double?
    let lipides: Double?
}

// MARK: - Nutrition Entry
struct NutritionEntry: Codable, Identifiable {
    var id: String { entryId ?? (name ?? "") + "\(calories ?? 0)" }
    let entryId: String?
    let name: String?
    let calories: Double?
    let proteines: Double?
    let glucides: Double?
    let lipides: Double?
    let quantity: Double?
    let unit: String?
    let time: String?
    let mealType: String?

    init(entryId: String?, name: String?, calories: Double?, proteines: Double?,
         glucides: Double?, lipides: Double?, quantity: Double?, unit: String?,
         time: String?, mealType: String?) {
        self.entryId = entryId; self.name = name; self.calories = calories
        self.proteines = proteines; self.glucides = glucides; self.lipides = lipides
        self.quantity = quantity; self.unit = unit; self.time = time; self.mealType = mealType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        entryId   = try? c.decode(String.self, forKey: .init("id"))
        name      = (try? c.decode(String.self, forKey: .init("nom")))
                 ?? (try? c.decode(String.self, forKey: .init("name")))
        calories  = try? c.decode(Double.self, forKey: .init("calories"))
        proteines = try? c.decode(Double.self, forKey: .init("proteines"))
        glucides  = try? c.decode(Double.self, forKey: .init("glucides"))
        lipides   = try? c.decode(Double.self, forKey: .init("lipides"))
        quantity  = try? c.decode(Double.self, forKey: .init("quantity"))
        unit      = try? c.decode(String.self, forKey: .init("unit"))
        time      = (try? c.decode(String.self, forKey: .init("heure")))
                 ?? (try? c.decode(String.self, forKey: .init("time")))
        mealType  = try? c.decode(String.self, forKey: .init("meal_type"))
    }
}

// MARK: - Nutrition Settings
struct NutritionSettings: Codable {
    let calories: Double?
    let proteines: Double?
    let glucides: Double?
    let lipides: Double?

    init(calories: Double?, proteines: Double?, glucides: Double?, lipides: Double?) {
        self.calories = calories; self.proteines = proteines
        self.glucides = glucides; self.lipides = lipides
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        calories  = (try? c.decode(Double.self, forKey: .init("limite_calories")))
                 ?? (try? c.decode(Double.self, forKey: .init("calories")))
        proteines = (try? c.decode(Double.self, forKey: .init("objectif_proteines")))
                 ?? (try? c.decode(Double.self, forKey: .init("proteines")))
        glucides  = try? c.decode(Double.self, forKey: .init("glucides"))
        lipides   = try? c.decode(Double.self, forKey: .init("lipides"))
    }
}

// MARK: - Nutrition Day History
struct NutritionDayHistory: Identifiable, Decodable {
    var id: String { date }
    let date: String
    let calories: Double
    let proteines: Double
}

// MARK: - Nutrition Data Response
struct NutritionDataResponse: Decodable {
    var settings: NutritionSettings?
    var totals: NutritionTotals?
    var entries: [NutritionEntry]
    var history: [NutritionDayHistory]

    enum CodingKeys: String, CodingKey {
        case settings, totals, entries, history
    }
}

// MARK: - Nutrition Day (for stats compliance chart)
struct NutritionDay: Codable, Identifiable {
    var id: String { date ?? "" }
    let date: String?
    let calories: Double?
    let proteines: Double?
    let glucides: Double?
    let lipides: Double?
}

// MARK: - Shared key decoder
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
