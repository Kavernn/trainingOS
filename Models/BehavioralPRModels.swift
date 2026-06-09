import Foundation

struct BehavioralPR: Codable {
    let id: String
    let type: String
    let label: String
    let icon: String
    let value: Double?
    let bestEver: Double
    let setDate: String
    let isActive: Bool
    let unit: String
    let hasData: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, label, icon, value, unit
        case bestEver = "best_ever"
        case setDate  = "set_date"
        case isActive = "is_active"
        case hasData  = "has_data"
    }

    var formattedValue: String {
        guard let v = value else { return "—" }
        if unit == "nuits" || unit == "jours" { return "\(Int(v)) \(unit)" }
        return "\(String(format: "%.1f", v))\(unit)"
    }

    var formattedBest: String {
        if unit == "nuits" || unit == "jours" { return "\(Int(bestEver)) \(unit)" }
        return "\(String(format: "%.1f", bestEver))\(unit)"
    }
}

struct BehavioralPRsData: Codable {
    let prs: [BehavioralPR]
    let total: Int
    let activePRs: Int
    let hasData: Bool

    enum CodingKeys: String, CodingKey {
        case prs, total
        case activePRs = "active_prs"
        case hasData   = "has_data"
    }
}
