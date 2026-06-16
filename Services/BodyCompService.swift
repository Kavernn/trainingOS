import SwiftUI
import Combine
import OSLog

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

    func category(isMale: Bool) -> (label: String, color: Color) {
        if isMale {
            switch pct {
            case ..<6:  return ("Essential", Color.statusYellow)
            case ..<14: return ("Athlète",   Color.statusCyan)
            case ..<18: return ("Fitness",   Color.appSuccess)
            case ..<25: return ("Moyen",     Color.statusBlue)
            default:    return ("Obèse",     Color.appDanger)
            }
        } else {
            switch pct {
            case ..<14: return ("Essential", Color.statusYellow)
            case ..<21: return ("Athlète",   Color.statusCyan)
            case ..<25: return ("Fitness",   Color.appSuccess)
            case ..<32: return ("Moyen",     Color.statusBlue)
            default:    return ("Obèse",     Color.appDanger)
            }
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
    private init() {}

    // ── Read ─────────────────────────────────────────────────────────────────

    func getNavyBodyFat(heightCm: Double, isMale: Bool) -> NavyBodyFatResult? {
        guard let e = latest, heightCm > 0 else { return nil }

        if isMale {
            guard let waist = e.waistCm, let neck = e.neckCm,
                  waist > neck else { return nil }
            let diff = waist - neck
            guard diff > 0 else { return nil }
            // Hodgdon & Beckett (1984) — constante 1.0471 pour inputs en cm
            let raw = 495.0 / (1.0471 - 0.19077 * log10(diff) + 0.15456 * log10(heightCm)) - 450.0
            let pct = min(max(raw, 3.0), 60.0)
            return NavyBodyFatResult(
                pct:         pct,
                fatMassLbs:  e.weight * pct / 100.0,
                leanMassLbs: e.weight * (1.0 - pct / 100.0),
                basedOnDate: e.date
            )
        } else {
            guard let waist = e.waistCm, let hips = e.hipsCm, let neck = e.neckCm,
                  (waist + hips) > neck else { return nil }
            let sum = waist + hips - neck
            guard sum > 0 else { return nil }
            // Hodgdon & Beckett (1984) — formule femme, inputs en cm
            let raw = 495.0 / (1.29579 - 0.35004 * log10(sum) + 0.22100 * log10(heightCm)) - 450.0
            let pct = min(max(raw, 10.0), 60.0)
            return NavyBodyFatResult(
                pct:         pct,
                fatMassLbs:  e.weight * pct / 100.0,
                leanMassLbs: e.weight * (1.0 - pct / 100.0),
                basedOnDate: e.date
            )
        }
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

    func navyMissingFields(isMale: Bool) -> [String] {
        guard let e = latest else {
            return isMale ? ["tour de taille", "tour de cou"]
                          : ["tour de taille", "tour de cou", "tour de hanches"]
        }
        var missing: [String] = []
        if e.waistCm == nil { missing.append("tour de taille") }
        if e.neckCm  == nil { missing.append("tour de cou") }
        if !isMale && e.hipsCm == nil { missing.append("tour de hanches") }
        return missing
    }

    // ── Refresh ──────────────────────────────────────────────────────────────

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let (_, bw, _) = try await APIService.shared.fetchProfilData()
            let sorted = bw.sorted { $0.date < $1.date }
            history = sorted
            latest  = sorted.last
        } catch {
            Logger(subsystem: "TrainingOS", category: "bodycomp").error("❌ BodyCompService.refresh failed: \(error, privacy: .public)")
        }
    }

}
