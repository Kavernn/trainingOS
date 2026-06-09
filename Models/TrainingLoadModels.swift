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

struct ACWRSubData: Codable {
    let ratio: Double?
    let acuteLoad: Double?
    let chronicLoad: Double?
    let zoneCode: String?
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case ratio
        case acuteLoad   = "acute_load"
        case chronicLoad = "chronic_load"
        case zoneCode    = "zone_code"
        case confidence
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
    let strengthAcwr: ACWRSubData?
    let cardioAcwr: ACWRSubData?

    enum CodingKeys: String, CodingKey {
        case hasData = "has_data"
        case acute, chronic, ratio, zone, message
        case trend4w      = "trend_4w"
        case strengthAcwr = "strength_acwr"
        case cardioAcwr   = "cardio_acwr"
    }

    var formattedRatio: String {
        guard let r = ratio else { return "—" }
        return String(format: "%.2f", r) + "×"
    }
}
