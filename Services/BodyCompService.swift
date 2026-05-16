import SwiftUI
import Combine

// ── Staleness ────────────────────────────────────────────────────────────────

enum EntryFreshness {
    case never
    case fresh
    case stale(days: Int)
    case veryStale(days: Int)

    var label: String {
        switch self {
        case .never:             return "Aucune donnée"
        case .fresh:             return ""
        case .stale(let d):     return "Il y a \(d) jours"
        case .veryStale(let d): return "Il y a \(d) jours — données périmées"
        }
    }

    var isProblematic: Bool {
        switch self { case .never, .veryStale: return true; default: return false }
    }
}

// ── Navy result ───────────────────────────────────────────────────────────────

struct NavyBodyFatResult {
    let pct: Double
    let fatMassLbs: Double
    let leanMassLbs: Double
    let basedOnDate: String

    func category() -> (label: String, color: Color) {
        switch pct {
        case ..<6:  return ("Athlète",    .cyan)
        case ..<13: return ("Très fit",   .green)
        case ..<17: return ("Fitness",    .blue)
        case ..<24: return ("Acceptable", .orange)
        default:    return ("Obèse",      .red)
        }
    }
}

// ── Service ───────────────────────────────────────────────────────────────────

@MainActor
final class BodyCompService: ObservableObject {
    static let shared = BodyCompService()

    @Published private(set) var latest: BodyWeightEntry?
    @Published private(set) var history: [BodyWeightEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var legacyWeightPending = false

    private init() {}

    // ── Read ─────────────────────────────────────────────────────────────────

    func getCurrentWeight() -> Double? { latest?.weight }

    func getLatestMeasurements() -> BodyWeightEntry? { latest }

    func getNavyBodyFat(heightCm: Double) -> NavyBodyFatResult? {
        guard let e = latest,
              let waist = e.waistCm,
              let neck  = e.neckCm,
              waist > neck, heightCm > 0 else { return nil }
        let diff = waist - neck
        guard diff > 0 else { return nil }
        let raw  = 495.0 / (1.0324 - 0.19077 * log10(diff) + 0.15456 * log10(heightCm)) - 450.0
        let pct  = min(max(raw, 2.0), 60.0)
        return NavyBodyFatResult(
            pct:         pct,
            fatMassLbs:  e.weight * pct / 100.0,
            leanMassLbs: e.weight * (1.0 - pct / 100.0),
            basedOnDate: e.date
        )
    }

    func staleness() -> EntryFreshness {
        guard let e = latest else { return .never }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let entryDate = fmt.date(from: e.date) else { return .fresh }
        let days = Calendar.current.dateComponents([.day], from: entryDate, to: .now).day ?? 0
        if days <= 14  { return .fresh }
        if days <= 90  { return .stale(days: days) }
        return .veryStale(days: days)
    }

    // Missing fields for Navy formula
    var navyMissingFields: [String] {
        guard let e = latest else { return ["poids", "tour de taille", "tour de cou"] }
        var missing: [String] = []
        if e.waistCm == nil { missing.append("tour de taille") }
        if e.neckCm  == nil { missing.append("tour de cou") }
        return missing
    }

    // ── Refresh ──────────────────────────────────────────────────────────────

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        guard let (_, bw, _) = try? await APIService.shared.fetchProfilData() else { return }
        let sorted = bw.sorted { $0.date < $1.date }
        history = sorted
        latest  = sorted.last
    }

    func refreshWithLegacyCheck() async {
        isLoading = true
        defer { isLoading = false }
        // fetchProfilData returns legacy_weight_pending — decode raw to capture it
        guard let url = URL(string: "\(APIConfig.base)/api/profil_data") else { return }
        guard let data = try? await APIService.shared.fetchWithCache(url: url, key: "profil_data") else { return }

        struct ProfilRaw: Decodable {
            let bodyWeight: [BodyWeightEntry]
            let legacyWeightPending: Bool?
            enum CodingKeys: String, CodingKey {
                case bodyWeight         = "body_weight"
                case legacyWeightPending = "legacy_weight_pending"
            }
        }
        guard let r = try? JSONDecoder().decode(ProfilRaw.self, from: data) else { return }
        let sorted = r.bodyWeight.sorted { $0.date < $1.date }
        history              = sorted
        latest               = sorted.last
        legacyWeightPending  = r.legacyWeightPending ?? false
    }

    func importLegacyWeight(_ weightLbs: Double) async {
        let today = DateFormatter.isoDate.string(from: Date())
        try? await APIService.shared.addBodyWeight(
            date: today, weight: weightLbs,
            bodyFat: nil, waistCm: nil
        )
        legacyWeightPending = false
    }
}
