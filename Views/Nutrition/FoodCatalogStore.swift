import Foundation

// MARK: - FoodItem

struct FoodItem: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var refQty: Double
    var refUnit: String
    var calories: Double
    var proteines: Double
    var glucides: Double
    var lipides: Double
    var category: String = "Autre"
    var isBuiltIn: Bool = false  // transient — excluded from Codable

    enum CodingKeys: String, CodingKey {
        case id, name, refQty, refUnit, calories, proteines, glucides, lipides, category
    }

    init(id: UUID = UUID(), name: String, refQty: Double, refUnit: String,
         calories: Double, proteines: Double, glucides: Double, lipides: Double,
         category: String = "Autre", isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.refQty = refQty; self.refUnit = refUnit
        self.calories = calories; self.proteines = proteines
        self.glucides = glucides; self.lipides = lipides
        self.category = category; self.isBuiltIn = isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        name      = try c.decode(String.self, forKey: .name)
        refQty    = try c.decode(Double.self, forKey: .refQty)
        refUnit   = try c.decode(String.self, forKey: .refUnit)
        calories  = try c.decode(Double.self, forKey: .calories)
        proteines = try c.decode(Double.self, forKey: .proteines)
        glucides  = try c.decode(Double.self, forKey: .glucides)
        lipides   = try c.decode(Double.self, forKey: .lipides)
        category  = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? "Autre"
        isBuiltIn = false
    }

    func macros(for qty: Double) -> (cal: Double, prot: Double, gluc: Double, lip: Double) {
        let f = qty / refQty
        return (calories * f, proteines * f, glucides * f, lipides * f)
    }
}

// MARK: - Store

enum FoodCatalogStore {
    static let customKey = "food_catalog_custom_v1"
    static let legacyKey = "food_catalog_v1"

    // MARK: Built-in reference table — 58 aliments, tous /100g (USDA/CIQUAL)
    static func builtInItems() -> [FoodItem] {
        let vi = "Viande", fr = "Fruit", le = "Légume"
        return [
            // VIANDES
            FoodItem(name: "Poulet — poitrine (cuit)",     refQty: 100, refUnit: "g", calories: 165, proteines: 31,  glucides: 0,   lipides: 3.6,  category: vi, isBuiltIn: true),
            FoodItem(name: "Poulet — cuisse (cuit)",       refQty: 100, refUnit: "g", calories: 209, proteines: 26,  glucides: 0,   lipides: 10.9, category: vi, isBuiltIn: true),
            FoodItem(name: "Poulet — entier rôti",         refQty: 100, refUnit: "g", calories: 190, proteines: 27,  glucides: 0,   lipides: 9,    category: vi, isBuiltIn: true),
            FoodItem(name: "Dinde — poitrine (cuite)",     refQty: 100, refUnit: "g", calories: 165, proteines: 30,  glucides: 0,   lipides: 3.7,  category: vi, isBuiltIn: true),
            FoodItem(name: "Dinde — hachée (cuite)",       refQty: 100, refUnit: "g", calories: 189, proteines: 27,  glucides: 0,   lipides: 8.5,  category: vi, isBuiltIn: true),
            FoodItem(name: "Bœuf haché — 10% MG (cuit)",  refQty: 100, refUnit: "g", calories: 215, proteines: 26,  glucides: 0,   lipides: 12,   category: vi, isBuiltIn: true),
            FoodItem(name: "Bœuf haché — 20% MG (cuit)",  refQty: 100, refUnit: "g", calories: 265, proteines: 24,  glucides: 0,   lipides: 18,   category: vi, isBuiltIn: true),
            FoodItem(name: "Bifteck — surlonge (cuit)",   refQty: 100, refUnit: "g", calories: 205, proteines: 29,  glucides: 0,   lipides: 9,    category: vi, isBuiltIn: true),
            FoodItem(name: "Bifteck — filet (cuit)",      refQty: 100, refUnit: "g", calories: 185, proteines: 30,  glucides: 0,   lipides: 6.5,  category: vi, isBuiltIn: true),
            FoodItem(name: "Porc — filet (cuit)",         refQty: 100, refUnit: "g", calories: 180, proteines: 28,  glucides: 0,   lipides: 7,    category: vi, isBuiltIn: true),
            FoodItem(name: "Porc — côtelette (cuite)",    refQty: 100, refUnit: "g", calories: 195, proteines: 27,  glucides: 0,   lipides: 9,    category: vi, isBuiltIn: true),
            FoodItem(name: "Jambon (cuit, tranché)",      refQty: 100, refUnit: "g", calories: 145, proteines: 21,  glucides: 2,   lipides: 5.5,  category: vi, isBuiltIn: true),
            FoodItem(name: "Bacon (cuit)",                refQty: 100, refUnit: "g", calories: 541, proteines: 37,  glucides: 0.5, lipides: 42,   category: vi, isBuiltIn: true),
            FoodItem(name: "Saucisse de porc (cuite)",    refQty: 100, refUnit: "g", calories: 296, proteines: 16,  glucides: 1,   lipides: 25,   category: vi, isBuiltIn: true),
            FoodItem(name: "Veau — escalope (cuite)",     refQty: 100, refUnit: "g", calories: 176, proteines: 30,  glucides: 0,   lipides: 5.5,  category: vi, isBuiltIn: true),
            FoodItem(name: "Agneau — côtelette (cuite)",  refQty: 100, refUnit: "g", calories: 294, proteines: 25,  glucides: 0,   lipides: 21,   category: vi, isBuiltIn: true),
            // FRUITS
            FoodItem(name: "Banane",       refQty: 100, refUnit: "g", calories: 89, proteines: 1.1, glucides: 23,  lipides: 0.3, category: fr, isBuiltIn: true),
            FoodItem(name: "Pomme",        refQty: 100, refUnit: "g", calories: 52, proteines: 0.3, glucides: 14,  lipides: 0.2, category: fr, isBuiltIn: true),
            FoodItem(name: "Orange",       refQty: 100, refUnit: "g", calories: 47, proteines: 0.9, glucides: 12,  lipides: 0.1, category: fr, isBuiltIn: true),
            FoodItem(name: "Fraise",       refQty: 100, refUnit: "g", calories: 32, proteines: 0.7, glucides: 7.7, lipides: 0.3, category: fr, isBuiltIn: true),
            FoodItem(name: "Myrtille",     refQty: 100, refUnit: "g", calories: 57, proteines: 0.7, glucides: 14,  lipides: 0.3, category: fr, isBuiltIn: true),
            FoodItem(name: "Framboise",    refQty: 100, refUnit: "g", calories: 52, proteines: 1.2, glucides: 12,  lipides: 0.7, category: fr, isBuiltIn: true),
            FoodItem(name: "Mangue",       refQty: 100, refUnit: "g", calories: 60, proteines: 0.8, glucides: 15,  lipides: 0.4, category: fr, isBuiltIn: true),
            FoodItem(name: "Ananas",       refQty: 100, refUnit: "g", calories: 50, proteines: 0.5, glucides: 13,  lipides: 0.1, category: fr, isBuiltIn: true),
            FoodItem(name: "Raisin",       refQty: 100, refUnit: "g", calories: 69, proteines: 0.7, glucides: 18,  lipides: 0.2, category: fr, isBuiltIn: true),
            FoodItem(name: "Pastèque",     refQty: 100, refUnit: "g", calories: 30, proteines: 0.6, glucides: 7.6, lipides: 0.2, category: fr, isBuiltIn: true),
            FoodItem(name: "Pêche",        refQty: 100, refUnit: "g", calories: 39, proteines: 0.9, glucides: 10,  lipides: 0.3, category: fr, isBuiltIn: true),
            FoodItem(name: "Poire",        refQty: 100, refUnit: "g", calories: 57, proteines: 0.4, glucides: 15,  lipides: 0.1, category: fr, isBuiltIn: true),
            FoodItem(name: "Kiwi",         refQty: 100, refUnit: "g", calories: 61, proteines: 1.1, glucides: 15,  lipides: 0.5, category: fr, isBuiltIn: true),
            FoodItem(name: "Cerise",       refQty: 100, refUnit: "g", calories: 63, proteines: 1.1, glucides: 16,  lipides: 0.2, category: fr, isBuiltIn: true),
            FoodItem(name: "Melon",        refQty: 100, refUnit: "g", calories: 34, proteines: 0.8, glucides: 8.2, lipides: 0.2, category: fr, isBuiltIn: true),
            FoodItem(name: "Pamplemousse", refQty: 100, refUnit: "g", calories: 42, proteines: 0.8, glucides: 11,  lipides: 0.1, category: fr, isBuiltIn: true),
            FoodItem(name: "Abricot",      refQty: 100, refUnit: "g", calories: 48, proteines: 1.4, glucides: 11,  lipides: 0.4, category: fr, isBuiltIn: true),
            FoodItem(name: "Prune",        refQty: 100, refUnit: "g", calories: 46, proteines: 0.7, glucides: 11,  lipides: 0.3, category: fr, isBuiltIn: true),
            // LÉGUMES
            FoodItem(name: "Brocoli",               refQty: 100, refUnit: "g", calories: 34,  proteines: 2.8, glucides: 7,   lipides: 0.4, category: le, isBuiltIn: true),
            FoodItem(name: "Épinards",              refQty: 100, refUnit: "g", calories: 23,  proteines: 2.9, glucides: 3.6, lipides: 0.4, category: le, isBuiltIn: true),
            FoodItem(name: "Tomate",                refQty: 100, refUnit: "g", calories: 18,  proteines: 0.9, glucides: 3.9, lipides: 0.2, category: le, isBuiltIn: true),
            FoodItem(name: "Carotte",               refQty: 100, refUnit: "g", calories: 41,  proteines: 0.9, glucides: 10,  lipides: 0.2, category: le, isBuiltIn: true),
            FoodItem(name: "Patate douce (cuite)",  refQty: 100, refUnit: "g", calories: 86,  proteines: 1.6, glucides: 20,  lipides: 0.1, category: le, isBuiltIn: true),
            FoodItem(name: "Pomme de terre (cuite)",refQty: 100, refUnit: "g", calories: 87,  proteines: 1.9, glucides: 20,  lipides: 0.1, category: le, isBuiltIn: true),
            FoodItem(name: "Poivron rouge",         refQty: 100, refUnit: "g", calories: 31,  proteines: 1,   glucides: 7,   lipides: 0.3, category: le, isBuiltIn: true),
            FoodItem(name: "Poivron vert",          refQty: 100, refUnit: "g", calories: 20,  proteines: 0.9, glucides: 4.6, lipides: 0.2, category: le, isBuiltIn: true),
            FoodItem(name: "Concombre",             refQty: 100, refUnit: "g", calories: 15,  proteines: 0.7, glucides: 3.6, lipides: 0.1, category: le, isBuiltIn: true),
            FoodItem(name: "Courgette",             refQty: 100, refUnit: "g", calories: 17,  proteines: 1.2, glucides: 3.1, lipides: 0.3, category: le, isBuiltIn: true),
            FoodItem(name: "Haricots verts (cuits)",refQty: 100, refUnit: "g", calories: 35,  proteines: 1.9, glucides: 8,   lipides: 0.1, category: le, isBuiltIn: true),
            FoodItem(name: "Laitue romaine",        refQty: 100, refUnit: "g", calories: 17,  proteines: 1.2, glucides: 3.3, lipides: 0.3, category: le, isBuiltIn: true),
            FoodItem(name: "Avocat",                refQty: 100, refUnit: "g", calories: 160, proteines: 2,   glucides: 9,   lipides: 15,  category: le, isBuiltIn: true),
            FoodItem(name: "Maïs (cuit)",           refQty: 100, refUnit: "g", calories: 96,  proteines: 3.4, glucides: 21,  lipides: 1.5, category: le, isBuiltIn: true),
            FoodItem(name: "Oignon",                refQty: 100, refUnit: "g", calories: 40,  proteines: 1.1, glucides: 9.3, lipides: 0.1, category: le, isBuiltIn: true),
            FoodItem(name: "Champignon (café)",     refQty: 100, refUnit: "g", calories: 22,  proteines: 3.1, glucides: 3.3, lipides: 0.3, category: le, isBuiltIn: true),
            FoodItem(name: "Choufleur",             refQty: 100, refUnit: "g", calories: 25,  proteines: 1.9, glucides: 5,   lipides: 0.3, category: le, isBuiltIn: true),
            FoodItem(name: "Asperge",               refQty: 100, refUnit: "g", calories: 20,  proteines: 2.2, glucides: 3.7, lipides: 0.1, category: le, isBuiltIn: true),
            FoodItem(name: "Pois (cuits)",          refQty: 100, refUnit: "g", calories: 84,  proteines: 5.4, glucides: 15,  lipides: 0.4, category: le, isBuiltIn: true),
            FoodItem(name: "Betterave",             refQty: 100, refUnit: "g", calories: 43,  proteines: 1.6, glucides: 10,  lipides: 0.2, category: le, isBuiltIn: true),
            FoodItem(name: "Céleri",                refQty: 100, refUnit: "g", calories: 16,  proteines: 0.7, glucides: 3,   lipides: 0.2, category: le, isBuiltIn: true),
            FoodItem(name: "Chou vert",             refQty: 100, refUnit: "g", calories: 25,  proteines: 1.3, glucides: 6,   lipides: 0.1, category: le, isBuiltIn: true),
            FoodItem(name: "Kale (chou frisé)",     refQty: 100, refUnit: "g", calories: 49,  proteines: 4.3, glucides: 9,   lipides: 0.9, category: le, isBuiltIn: true),
            FoodItem(name: "Ail",                   refQty: 100, refUnit: "g", calories: 149, proteines: 6.4, glucides: 33,  lipides: 0.5, category: le, isBuiltIn: true),
        ]
    }

    // MARK: - Load / Save

    static func load() -> [FoodItem] {
        migrateLegacy()
        let builtIn = builtInItems()
        let custom = loadCustom()
        let builtInNames = Set(builtIn.map { $0.name })
        return builtIn + custom.filter { !builtInNames.contains($0.name) }
    }

    static func save(_ items: [FoodItem]) {
        let customOnly = items.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(customOnly) else { return }
        UserDefaults.standard.set(data, forKey: customKey)
    }

    private static func loadCustom() -> [FoodItem] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let items = try? JSONDecoder().decode([FoodItem].self, from: data)
        else { return [] }
        return items
    }

    // One-time migration from old flat key → custom-only key
    private static func migrateLegacy() {
        guard UserDefaults.standard.data(forKey: customKey) == nil,
              let legacyData = UserDefaults.standard.data(forKey: legacyKey),
              let legacyItems = try? JSONDecoder().decode([FoodItem].self, from: legacyData)
        else { return }
        let builtInNames = Set(builtInItems().map { $0.name })
        let customOnly = legacyItems.filter { !builtInNames.contains($0.name) }
        if let data = try? JSONEncoder().encode(customOnly) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    // MARK: - Sync state

    static let syncFailedKey = "food_catalog_sync_failed"
    static var syncFailed: Bool {
        get { UserDefaults.standard.bool(forKey: syncFailedKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncFailedKey) }
    }

    // MARK: - API codec (snake_case ↔ camelCase) — syncs custom items only

    private static var apiEncoder: JSONEncoder {
        let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; return e
    }
    private static var apiDecoder: JSONDecoder {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }

    static func encodeForAPI(_ items: [FoodItem]) -> Data? {
        struct Payload: Encodable { let items: [FoodItem] }
        return try? apiEncoder.encode(Payload(items: items.filter { !$0.isBuiltIn }))
    }

    static func decodeFromAPI(_ data: Data) -> [FoodItem] {
        struct Resp: Decodable { let items: [FoodItem] }
        return (try? apiDecoder.decode(Resp.self, from: data))?.items ?? []
    }
}

// MARK: - Recent Foods

private struct RecentFoodEntry: Codable {
    var name: String
    var quantity: Double
    var unit: String
    var timestamp: Date
    var count: Int?
}

enum RecentFoodsStore {
    struct Item: Identifiable {
        let id: UUID
        let food: FoodItem
        let quantity: Double
    }

    private static let key = "recent_foods_v1"

    static func record(name: String, quantity: Double, unit: String) {
        var entries = load()
        if let idx = entries.firstIndex(where: { $0.name == name }) {
            entries[idx].count = (entries[idx].count ?? 1) + 1
            entries[idx].quantity = quantity
            entries[idx].timestamp = Date()
        } else {
            entries.insert(RecentFoodEntry(name: name, quantity: quantity, unit: unit, timestamp: Date(), count: 1), at: 0)
            if entries.count > 50 { entries = Array(entries.prefix(50)) }
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func topRecent(catalog: [FoodItem], days: Int = 30, limit: Int = 10) -> [Item] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let recent = load().filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return [] }
        return recent
            .sorted {
                let ca = $0.count ?? 1, cb = $1.count ?? 1
                return ca != cb ? ca > cb : $0.timestamp > $1.timestamp
            }
            .prefix(limit)
            .compactMap { entry in
                guard let food = catalog.first(where: { $0.name == entry.name }) else { return nil }
                return Item(id: food.id, food: food, quantity: entry.quantity)
            }
    }

    static func lastQuantity(for name: String) -> Double? {
        load().first { $0.name == name }?.quantity
    }

    private static func load() -> [RecentFoodEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([RecentFoodEntry].self, from: data)
        else { return [] }
        return items
    }
}
