import Foundation

// MARK: - FoodItem

struct FoodItem: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var refQty: Double       // quantité de référence (ex: 100)
    var refUnit: String      // "g", "ml", "unité(s)", "portion(s)"
    var calories: Double     // pour refQty
    var proteines: Double
    var glucides: Double
    var lipides: Double

    func macros(for qty: Double) -> (cal: Double, prot: Double, gluc: Double, lip: Double) {
        let f = qty / refQty
        return (calories * f, proteines * f, glucides * f, lipides * f)
    }
}

// MARK: - Store

enum FoodCatalogStore {
    static let key = "food_catalog_v1"

    static let defaults: [FoodItem] = [
        FoodItem(name: "Poulet",            refQty: 100, refUnit: "g",          calories: 165, proteines: 31,   glucides: 0,   lipides: 3.5),
        FoodItem(name: "Œuf",               refQty: 1,   refUnit: "unité(s)",   calories: 70,  proteines: 6,    glucides: 0.5, lipides: 5),
        FoodItem(name: "Thon",              refQty: 100, refUnit: "g",          calories: 132, proteines: 30,   glucides: 0,   lipides: 1),
        FoodItem(name: "Jambon",            refQty: 100, refUnit: "g",          calories: 145, proteines: 21,   glucides: 2,   lipides: 5.5),
        FoodItem(name: "Yaourt grec",       refQty: 100, refUnit: "g",          calories: 100, proteines: 10,   glucides: 3.7, lipides: 5),
        FoodItem(name: "Yogourt islandais", refQty: 100, refUnit: "g",          calories: 65,  proteines: 10.5, glucides: 4,   lipides: 0.3),
        FoodItem(name: "Cottage",           refQty: 100, refUnit: "g",          calories: 98,  proteines: 11,   glucides: 3.4, lipides: 4.3),
        FoodItem(name: "Shake protéiné",    refQty: 1,   refUnit: "portion(s)", calories: 120, proteines: 25,   glucides: 5,   lipides: 1.5),
        FoodItem(name: "Riz (cuit)",        refQty: 100, refUnit: "g",          calories: 130, proteines: 2.7,  glucides: 28,  lipides: 0.3),
        FoodItem(name: "Avoine",            refQty: 100, refUnit: "g",          calories: 389, proteines: 17,   glucides: 66,  lipides: 7),
        FoodItem(name: "Pain de blé",       refQty: 30,  refUnit: "g",          calories: 80,  proteines: 3,    glucides: 15,  lipides: 1),
        FoodItem(name: "Beurre de noix",    refQty: 32,  refUnit: "g",          calories: 190, proteines: 7,    glucides: 7,   lipides: 16),
        FoodItem(name: "Banane",            refQty: 1,   refUnit: "unité(s)",   calories: 105, proteines: 1.3,  glucides: 27,  lipides: 0.4),
        FoodItem(name: "Lait 2%",           refQty: 250, refUnit: "ml",         calories: 130, proteines: 8.5,  glucides: 12,  lipides: 5),
    ]

    static func load() -> [FoodItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([FoodItem].self, from: data),
              !items.isEmpty else {
            return defaults
        }
        return items
    }

    static func save(_ items: [FoodItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
