import Foundation
import CoreLocation

// MARK: - Core Model

struct Gym: Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    let phone: String?
    let website: String?
    let openingHours: String?
    let gymType: GymType
    var distanceMeters: Double?
    var crowdsource: GymCrowdsource?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var distanceFormatted: String {
        guard let d = distanceMeters else { return "" }
        return d < 1000 ? "\(Int(d)) m" : String(format: "%.1f km", d / 1000.0)
    }

    var isOpenNow: Bool? { openingHours.flatMap { OpeningHoursParser.isOpenNow($0) } }

    var openStatusText: String {
        switch isOpenNow {
        case true:  return "Ouvert"
        case false:
            if let h = openingHours, let next = OpeningHoursParser.nextOpenTime(h) {
                return "Fermé — ouvre à \(next)"
            }
            return "Fermé"
        case nil:   return openingHours != nil ? "Voir horaires" : "Horaires inconnus"
        }
    }
}

// MARK: - Gym Type

enum GymType: String, CaseIterable, Codable {
    case commercial, crossfit, independent, hotel, community, outdoor

    var label: String {
        switch self {
        case .commercial:  return "Commercial"
        case .crossfit:    return "CrossFit"
        case .independent: return "Indépendant"
        case .hotel:       return "Hôtel"
        case .community:   return "Communautaire"
        case .outdoor:     return "Extérieur"
        }
    }

    var icon: String {
        switch self {
        case .commercial:  return "building.2.fill"
        case .crossfit:    return "figure.strengthtraining.functional"
        case .independent: return "dumbbell.fill"
        case .hotel:       return "bed.double.fill"
        case .community:   return "person.3.fill"
        case .outdoor:     return "leaf.fill"
        }
    }
}

// MARK: - Crowdsource

struct GymCrowdsource: Codable {
    let dropInPrice: Double?
    let equipment: [String]
    let vibeHardcore: Int?
    let vibeCrowded: Int?
    let vibeMusic: Int?
    let contributionCount: Int
    let lastUpdated: String?
}

// MARK: - Filters

struct GymFilters {
    var selectedTypes: Set<GymType> = []
    var openNow: Bool = false
    var dropInOnly: Bool = false
    var radiusKm: Int = 5
    var requiredEquipment: Set<EquipmentKey> = []

    var isActive: Bool {
        !selectedTypes.isEmpty || openNow || dropInOnly || !requiredEquipment.isEmpty
    }
}

// MARK: - Equipment

enum EquipmentKey: String, CaseIterable, Codable {
    case squatRack   = "squat_rack"
    case barbell     = "barbell"
    case dumbbells   = "dumbbells"
    case cables      = "cables"
    case bench       = "bench"
    case pullUpBar   = "pull_up_bar"
    case cardio      = "cardio"
    case kettlebells = "kettlebells"

    var label: String {
        switch self {
        case .squatRack:   return "Squat rack"
        case .barbell:     return "Barbell"
        case .dumbbells:   return "Dumbbells"
        case .cables:      return "Câbles"
        case .bench:       return "Bench"
        case .pullUpBar:   return "Pull-up bar"
        case .cardio:      return "Cardio"
        case .kettlebells: return "Kettlebells"
        }
    }
}

// MARK: - Persistence

struct GymFavorite: Codable, Identifiable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let gymType: GymType
    let savedAt: Date
}

struct GymVisit: Codable, Identifiable {
    let id: String
    let gymId: String
    let gymName: String
    let gymAddress: String
    let visitedAt: Date
}

// MARK: - Contribution

struct GymContributionPayload: Codable {
    let gymId: String
    let gymName: String
    let latitude: Double
    let longitude: Double
    let dropInPrice: Double?
    let equipment: [String]
    let vibeHardcore: Int?
    let vibeCrowded: Int?
    let vibeMusic: Int?
}

// MARK: - Opening Hours Parser

enum OpeningHoursParser {
    private static let osmDayMap: [String: Int] = [
        "mo": 0, "tu": 1, "we": 2, "th": 3, "fr": 4, "sa": 5, "su": 6
    ]

    static func isOpenNow(_ raw: String) -> Bool? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s == "24/7" || s.hasPrefix("Mo-Su 00:00-24:00") { return true }

        let cal = Calendar.current
        let now = Date()
        let wd = cal.component(.weekday, from: now)          // 1=Sun
        let osmDay = [6, 0, 1, 2, 3, 4, 5][wd - 1]
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        for seg in s.split(separator: ";").map({ String($0).trimmingCharacters(in: .whitespaces) }) {
            if let result = parseSegment(seg, osmDay: osmDay, nowMin: nowMin) {
                return result
            }
        }
        return nil
    }

    static func nextOpenTime(_ raw: String) -> String? {
        let pattern = #"(\d{1,2}:\d{2})-\d{1,2}:\d{2}"#
        guard let r = raw.range(of: pattern, options: .regularExpression) else { return nil }
        return String(raw[r]).components(separatedBy: "-").first
    }

    private static func parseSegment(_ seg: String, osmDay: Int, nowMin: Int) -> Bool? {
        let timePattern = #"(\d{1,2}:\d{2})-(\d{1,2}:\d{2})"#
        guard let timeRange = seg.range(of: timePattern, options: .regularExpression) else { return nil }

        let times = String(seg[timeRange]).split(separator: "-").compactMap { t -> Int? in
            let p = String(t).split(separator: ":").map { Int(String($0)) ?? 0 }
            guard p.count == 2 else { return nil }
            return p[0] * 60 + p[1]
        }
        guard times.count == 2 else { return nil }
        let closeMin = times[1] == 0 ? 24 * 60 : times[1]

        let daySpec = String(seg[seg.startIndex..<timeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard daySpec.isEmpty || dayApplies(daySpec, to: osmDay) else { return nil }

        return nowMin >= times[0] && nowMin < closeMin
    }

    private static func dayApplies(_ spec: String, to osmDay: Int) -> Bool {
        let lower = spec.lowercased().replacingOccurrences(of: " ", with: "")
        for part in lower.split(separator: ",").map(String.init) {
            let rangeParts = part.split(separator: "-").map(String.init)
            if rangeParts.count == 2,
               let s = osmDayMap[String(rangeParts[0].prefix(2))],
               let e = osmDayMap[String(rangeParts[1].prefix(2))] {
                if s <= e {
                    if (s...e).contains(osmDay) { return true }
                } else {
                    if osmDay >= s || osmDay <= e { return true }
                }
            } else if rangeParts.count == 1,
                      let d = osmDayMap[String(rangeParts[0].prefix(2))],
                      d == osmDay {
                return true
            }
        }
        return false
    }
}
