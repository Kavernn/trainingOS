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
    let trainingCalories: Double?
    let restCalories: Double?

    var hasDynamicGoals: Bool { trainingCalories != nil && restCalories != nil }

    init(calories: Double?, proteines: Double?, glucides: Double?, lipides: Double?,
         trainingCalories: Double? = nil, restCalories: Double? = nil) {
        self.calories = calories; self.proteines = proteines
        self.glucides = glucides; self.lipides = lipides
        self.trainingCalories = trainingCalories; self.restCalories = restCalories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        calories  = (try? c.decode(Double.self, forKey: .init("limite_calories")))
                 ?? (try? c.decode(Double.self, forKey: .init("calories")))
        proteines = (try? c.decode(Double.self, forKey: .init("objectif_proteines")))
                 ?? (try? c.decode(Double.self, forKey: .init("proteines")))
        glucides         = try? c.decode(Double.self, forKey: .init("glucides"))
        lipides          = try? c.decode(Double.self, forKey: .init("lipides"))
        trainingCalories = try? c.decode(Double.self, forKey: .init("training_calories"))
        restCalories     = try? c.decode(Double.self, forKey: .init("rest_calories"))
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
    var todayType: String?
    var effectiveCalories: Double?

    enum CodingKeys: String, CodingKey {
        case settings, totals, entries, history
        case todayType = "today_type"
        case effectiveCalories = "effective_calories"
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

// MARK: - Meal Template
struct MealTemplate: Identifiable, Codable {
    let id: String
    var name: String
    var items: [MealTemplateItem]

    var totalCalories:  Double { items.reduce(0) { $0 + $1.calories } }
    var totalProteines: Double { items.reduce(0) { $0 + $1.proteines } }
    var totalGlucides:  Double { items.reduce(0) { $0 + $1.glucides } }
    var totalLipides:   Double { items.reduce(0) { $0 + $1.lipides } }

    enum CodingKeys: String, CodingKey { case id, name, items }
}

struct MealTemplateItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var calories: Double
    var proteines: Double
    var glucides: Double
    var lipides: Double

    enum CodingKeys: String, CodingKey {
        case name, calories, proteines, glucides, lipides
    }
}

// MARK: - Nutrition Correlations
struct NutritionCorrelations: Decodable {
    let protRpe:    ProtRpeInsight?
    let calRec:     CalRecInsight?
    let volCal:     VolCalInsight?
    let sampleDays: Int

    struct ProtRpeInsight: Decodable {
        let highProtAvgRpe: Double
        let lowProtAvgRpe:  Double
        let diff:           Double
        let sampleHigh:     Int
        let sampleLow:      Int
        enum CodingKeys: String, CodingKey {
            case highProtAvgRpe = "high_prot_avg_rpe"
            case lowProtAvgRpe  = "low_prot_avg_rpe"
            case diff
            case sampleHigh = "sample_high"
            case sampleLow  = "sample_low"
        }
    }

    struct CalRecInsight: Decodable {
        let onTargetAvg:  Double
        let offTargetAvg: Double
        let diff:         Double
        let sampleOn:     Int
        let sampleOff:    Int
        enum CodingKeys: String, CodingKey {
            case onTargetAvg  = "on_target_avg"
            case offTargetAvg = "off_target_avg"
            case diff
            case sampleOn  = "sample_on"
            case sampleOff = "sample_off"
        }
    }

    struct VolCalInsight: Decodable {
        let highVolAvgCal: Int
        let lowVolAvgCal:  Int
        let diff:          Int
    }

    enum CodingKeys: String, CodingKey {
        case protRpe   = "prot_rpe"
        case calRec    = "cal_rec"
        case volCal    = "vol_cal"
        case sampleDays = "sample_days"
    }
}

// MARK: - Shared key decoder
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
