import Foundation

struct PortraitDimension: Codable {
    let name: String
    let recent: Double?
    let ref: Double?
    let delta: Double?
    let deltaPct: Double?
    let hasBaseline: Bool
    let improving: Bool?

    enum CodingKeys: String, CodingKey {
        case name, recent, ref, delta, improving
        case deltaPct    = "delta_pct"
        case hasBaseline = "has_baseline"
    }

    var icon: String {
        switch name {
        case "frequency":   return "figure.strengthtraining.traditional"
        case "volume":      return "dumbbell.fill"
        case "hrv":         return "waveform.path.ecg"
        case "sleep":       return "moon.zzz.fill"
        case "stress":      return "brain.head.profile"
        case "nutrition":   return "fork.knife.circle.fill"
        case "body_weight": return "scalemass.fill"
        default:            return "chart.bar.fill"
        }
    }

    var label: String {
        switch name {
        case "frequency":   return "Fréquence"
        case "volume":      return "Volume"
        case "hrv":         return "HRV"
        case "sleep":       return "Sommeil"
        case "stress":      return "Stress"
        case "nutrition":   return "Nutrition"
        case "body_weight": return "Poids"
        default:            return name.capitalized
        }
    }

    var formattedDelta: String {
        guard let p = deltaPct else { return "—" }
        let sign = p >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f", p))%"
    }
}

struct PortraitData: Codable {
    let dimensions: [PortraitDimension]
    let transformationScore: Int?
    let improvingCount: Int
    let totalWithBaseline: Int
    let referenceOffsetDays: Int
    let hasBaseline: Bool
    let inceptionDate: String?

    enum CodingKeys: String, CodingKey {
        case dimensions
        case transformationScore  = "transformation_score"
        case improvingCount       = "improving_count"
        case totalWithBaseline    = "total_with_baseline"
        case referenceOffsetDays  = "reference_offset_days"
        case hasBaseline          = "has_baseline"
        case inceptionDate        = "inception_date"
    }
}
