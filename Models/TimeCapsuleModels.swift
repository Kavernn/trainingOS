import Foundation
import SwiftUI

struct TimeCapsuleListResponse: Codable {
    let capsules: [TimeCapsule]
}

struct TimeCapsule: Codable, Identifiable {
    let id: String
    let createdAt: String
    let unlockAt: String
    let unlockedAt: String?
    let durationMonths: Int
    let message: String?
    let isOpened: Bool
    let snapshot: CapsuleSnapshot
    var current: CapsuleSnapshot?

    enum CodingKeys: String, CodingKey {
        case id, message, snapshot, current
        case createdAt      = "created_at"
        case unlockAt       = "unlock_at"
        case unlockedAt     = "unlocked_at"
        case durationMonths = "duration_months"
        case isOpened       = "is_opened"
    }

    var isUnlocked: Bool {
        guard let d = _parseISO(unlockAt) else { return false }
        return d <= Date()
    }

    var daysUntilUnlock: Int {
        guard let d = _parseISO(unlockAt) else { return 0 }
        let diff = d.timeIntervalSince(Date())
        return max(0, Int(diff / 86400))
    }

    var formattedUnlockDate: String  { _fmt(unlockAt) }
    var formattedCreatedDate: String { _fmt(createdAt) }

    private func _parseISO(_ iso: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: iso) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: iso)
    }

    private func _fmt(_ iso: String) -> String {
        guard let d = _parseISO(iso) else { return iso }
        let f = DateFormatter()
        f.locale    = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        return f.string(from: d)
    }
}

struct CapsuleSnapshot: Codable {
    let capturedAt: String
    let activeProgramme: String?
    let totalSessionsToDate: Int
    let prs: [String: PREntry]
    let weeklyVolumeAvgKg: Double
    let sessionsPerMonthAvg: Double
    let bodyWeightKg: Double?
    let macrosAvg: MacrosAvgCapsule
    // pssAvg: present in JSON but intentionally excluded from UI/share

    enum CodingKeys: String, CodingKey {
        case prs
        case capturedAt           = "captured_at"
        case activeProgramme      = "active_programme"
        case totalSessionsToDate  = "total_sessions_to_date"
        case weeklyVolumeAvgKg    = "weekly_volume_avg_kg"
        case sessionsPerMonthAvg  = "sessions_per_month_avg"
        case bodyWeightKg         = "body_weight_kg"
        case macrosAvg            = "macros_avg"
    }
}

struct PREntry: Codable {
    let weight: Double
    let reps: Int
    let date: String
    let name: String?
}

struct MacrosAvgCapsule: Codable {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG   = "carbs_g"
        case fatG     = "fat_g"
    }
}

// ── Client-side comparison ────────────────────────────────────────────────────

struct CapsuleMetric: Identifiable {
    let id = UUID()
    let label: String
    let before: String
    let after: String
    let delta: String
    let deltaPositive: Bool
    let isNeutral: Bool
}

extension TimeCapsule {
    func comparisonMetrics() -> [CapsuleMetric] {
        guard let cur = current else { return [] }
        let snap = snapshot
        var metrics: [CapsuleMetric] = []

        // PRs — backend values are in kg; convert to lbs for UnitSettings
        let u = UnitSettings.shared
        for (key, prB) in snap.prs.sorted(by: { $0.key < $1.key }) {
            let label = key.replacingOccurrences(of: "_", with: " ").capitalized
            if let prA = cur.prs[key] {
                let bLbs = prB.weight / 0.453592
                let aLbs = prA.weight / 0.453592
                let dLbs = aLbs - bLbs
                metrics.append(CapsuleMetric(
                    label: label,
                    before: u.format(bLbs, decimals: 0),
                    after:  u.format(aLbs, decimals: 0),
                    delta:  dLbs >= 0 ? "+\(u.format(dLbs, decimals: 0))" : u.format(dLbs, decimals: 0),
                    deltaPositive: dLbs >= 0,
                    isNeutral: false
                ))
            }
        }

        // Weekly volume — backend in kg; convert to lbs then display via UnitSettings
        let volD   = cur.weeklyVolumeAvgKg - snap.weeklyVolumeAvgKg
        let volPct = snap.weeklyVolumeAvgKg > 0 ? (volD / snap.weeklyVolumeAvgKg) * 100 : 0
        let snapVolLbs = snap.weeklyVolumeAvgKg / 0.453592
        let curVolLbs  = cur.weeklyVolumeAvgKg  / 0.453592
        metrics.append(CapsuleMetric(
            label:  "Volume hebdo",
            before: _formatK(u.display(snapVolLbs)) + " \(u.label)",
            after:  _formatK(u.display(curVolLbs))  + " \(u.label)",
            delta:  volPct >= 0 ? "+\(Int(volPct))%" : "\(Int(volPct))%",
            deltaPositive: volD >= 0,
            isNeutral: false
        ))

        // Sessions / month
        let sessD = cur.sessionsPerMonthAvg - snap.sessionsPerMonthAvg
        metrics.append(CapsuleMetric(
            label:  "Séances/mois",
            before: "\(Int(snap.sessionsPerMonthAvg))",
            after:  "\(Int(cur.sessionsPerMonthAvg))",
            delta:  sessD >= 0 ? "+\(Int(sessD))" : "\(Int(sessD))",
            deltaPositive: sessD >= 0,
            isNeutral: false
        ))

        // Body weight (neutral — no judgment) — backend in kg; convert to lbs for UnitSettings
        if let bwB = snap.bodyWeightKg, let bwA = cur.bodyWeightKg {
            let bLbs = bwB / 0.453592
            let aLbs = bwA / 0.453592
            let dLbs = aLbs - bLbs
            metrics.append(CapsuleMetric(
                label:  "Poids",
                before: u.format(bLbs),
                after:  u.format(aLbs),
                delta:  dLbs >= 0 ? "+\(u.format(dLbs))" : u.format(dLbs),
                deltaPositive: false,
                isNeutral: true
            ))
        }

        // Protein
        let protD = cur.macrosAvg.proteinG - snap.macrosAvg.proteinG
        if snap.macrosAvg.proteinG > 0 {
            metrics.append(CapsuleMetric(
                label:  "Protéines moy.",
                before: "\(Int(snap.macrosAvg.proteinG)) g/j",
                after:  "\(Int(cur.macrosAvg.proteinG)) g/j",
                delta:  protD >= 0 ? "+\(Int(protD)) g" : "\(Int(protD)) g",
                deltaPositive: protD >= 0,
                isNeutral: false
            ))
        }

        return metrics
    }

    var motivationalVerdict: String {
        guard current != nil else { return "La constance > la perfection." }
        let ms      = comparisonMetrics()
        let judged  = ms.filter { !$0.isNeutral }
        let positive = judged.filter { $0.deltaPositive }.count
        guard !judged.isEmpty else { return "La constance > la perfection." }
        let ratio = Double(positive) / Double(judged.count)
        if ratio >= 0.70 { return "Tu as tenu ta promesse." }
        if ratio >= 0.40 { return "La constance > la perfection. T'es toujours là." }
        return "Chaque comeback est plus fort que le setback."
    }
}
