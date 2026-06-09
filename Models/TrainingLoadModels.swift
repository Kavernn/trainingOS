import Foundation

enum TrainingZone: String, Codable {
    case under, optimal, spike

    var label: String {
        switch self {
        case .under:   return "Sous-chargé"
        case .optimal: return "Zone optimale"
        case .spike:   return "Surcharge"
        }
    }

    var colorHex: String {
        switch self {
        case .under:   return "FF9500"
        case .optimal: return "34C759"
        case .spike:   return "FF3B30"
        }
    }

    var icon: String {
        switch self {
        case .under:   return "arrow.down.circle"
        case .optimal: return "checkmark.circle.fill"
        case .spike:   return "exclamationmark.triangle.fill"
        }
    }
}

struct TrainingLoadData: Codable {
    let hasData: Bool
    let acute: Double?
    let chronic: Double?
    let ratio: Double?
    let zone: TrainingZone
    let trend4w: [Double]
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData = "has_data"
        case acute, chronic, ratio, zone, message
        case trend4w = "trend_4w"
    }

    var formattedRatio: String {
        guard let r = ratio else { return "—" }
        return String(format: "%.2f", r) + "×"
    }
}
