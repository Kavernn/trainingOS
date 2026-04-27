import Foundation
import Combine

// MARK: - Coach Memory
// Persistent, structured facts the AI coach accumulates over time.
// Injected into every coach conversation via buildContext().

struct CoachMemoryEntry: Codable, Identifiable {
    let id: String
    var type: MemType
    var content: String
    let createdAt: String
    var updatedAt: String
    var confidence: Double  // 0.0 – 1.0

    enum MemType: String, Codable, CaseIterable {
        case pattern     = "PATTERN"
        case milestone   = "MILESTONE"
        case correlation = "CORRÉLATION"
        case risk        = "RISQUE"
        case preference  = "PRÉFÉRENCE"

        var icon: String {
            switch self {
            case .pattern:     return "repeat.circle.fill"
            case .milestone:   return "trophy.fill"
            case .correlation: return "chart.dots.scatter"
            case .risk:        return "exclamationmark.triangle.fill"
            case .preference:  return "star.fill"
            }
        }
    }
}

// MARK: - Store

final class CoachMemoryStore: ObservableObject {
    static let shared = CoachMemoryStore()

    private let storageKey    = "coach_memory_v1"
    private let analysisKey   = "coach_memory_last_analysis"
    private let maxEntries    = 30
    private let analysisCooldown: TimeInterval = 7 * 86400  // 7 days

    @Published private(set) var entries: [CoachMemoryEntry] = []

    private init() { load() }

    // MARK: - CRUD

    func upsert(_ entry: CoachMemoryEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
            // Evict lowest-confidence entries if over limit
            if entries.count > maxEntries {
                entries = Array(entries.sorted { $0.confidence > $1.confidence }.prefix(maxEntries))
            }
        }
        save()
    }

    func delete(id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    // MARK: - Context block injected into AI prompts

    var contextBlock: String {
        guard !entries.isEmpty else { return "" }
        let sorted = entries.sorted { $0.confidence > $1.confidence }.prefix(12)
        return sorted.map { "[\($0.type.rawValue)] \($0.content)" }.joined(separator: "\n")
    }

    // MARK: - Weekly auto-analysis

    func runAnalysisIfNeeded(
        sessions: [String: SessionEntry],
        recovery: [RecoveryEntry],
        weights: [String: WeightData],
        goals: [String: GoalProgress],
        correlations: [CorrelationInsight]
    ) {
        let now = Date().timeIntervalSince1970
        let lastRun = UserDefaults.standard.double(forKey: analysisKey)
        guard now - lastRun > analysisCooldown else { return }

        let generated = CoachMemoryAnalyzer.analyze(
            sessions: sessions, recovery: recovery,
            weights: weights, goals: goals,
            correlations: correlations
        )
        for entry in generated { upsert(entry) }
        UserDefaults.standard.set(now, forKey: analysisKey)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CoachMemoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Analyzer

enum CoachMemoryAnalyzer {

    static func analyze(
        sessions: [String: SessionEntry],
        recovery: [RecoveryEntry],
        weights: [String: WeightData],
        goals: [String: GoalProgress],
        correlations: [CorrelationInsight]
    ) -> [CoachMemoryEntry] {
        var results: [CoachMemoryEntry] = []
        let today = DateFormatter.isoDate.string(from: Date())

        // 1. PATTERN — preferred training days
        if let dayPattern = preferredTrainingDays(sessions: sessions) {
            results.append(CoachMemoryEntry(
                id: "pattern.training.days",
                type: .pattern,
                content: "S'entraîne préférentiellement \(dayPattern)",
                createdAt: today, updatedAt: today, confidence: 0.8
            ))
        }

        // 2. PATTERN — RPE tendency
        if let rpeFact = rpePattern(sessions: sessions) {
            results.append(CoachMemoryEntry(
                id: "pattern.rpe.tendency",
                type: .pattern,
                content: rpeFact,
                createdAt: today, updatedAt: today, confidence: 0.75
            ))
        }

        // 3. MILESTONE — session count
        if let milestone = sessionCountMilestone(sessions: sessions) {
            results.append(CoachMemoryEntry(
                id: "milestone.session.count",
                type: .milestone,
                content: milestone,
                createdAt: today, updatedAt: today, confidence: 1.0
            ))
        }

        // 4. RISQUE — chronic sleep deficit
        if let sleepRisk = sleepRisk(recovery: recovery) {
            results.append(CoachMemoryEntry(
                id: "risk.sleep.chronic",
                type: .risk,
                content: sleepRisk,
                createdAt: today, updatedAt: today, confidence: 0.85
            ))
        }

        // 5. MILESTONE — achieved goals
        for (name, goal) in goals where goal.achieved {
            results.append(CoachMemoryEntry(
                id: "milestone.goal.\(name.lowercased().replacingOccurrences(of: " ", with: "."))",
                type: .milestone,
                content: "Objectif '\(name)' atteint (\(String(format: "%.0f", goal.current)) / \(String(format: "%.0f", goal.goal)))",
                createdAt: today, updatedAt: today, confidence: 1.0
            ))
        }

        // 6. CORRÉLATION — strongest personal correlation
        if let top = correlations.filter({ abs($0.correlation) >= 0.5 }).max(by: { abs($0.correlation) < abs($1.correlation) }) {
            let dir = top.correlation > 0 ? "↑" : "↓"
            results.append(CoachMemoryEntry(
                id: "correlation.top.\(top.xVar).\(top.yVar)",
                type: .correlation,
                content: "\(top.label) (r=\(String(format: "%.2f", top.correlation))) — \(top.xVar)\(dir) influence \(top.yVar)",
                createdAt: today, updatedAt: today, confidence: min(1.0, abs(top.correlation))
            ))
        }

        // 7. PATTERN — short vs long sessions
        if let sessionLengthFact = sessionLengthPattern(sessions: sessions) {
            results.append(CoachMemoryEntry(
                id: "preference.session.length",
                type: .preference,
                content: sessionLengthFact,
                createdAt: today, updatedAt: today, confidence: 0.7
            ))
        }

        // 8. MILESTONE — strongest current lift
        if let strongestLift = strongestLift(weights: weights) {
            results.append(CoachMemoryEntry(
                id: "milestone.strongest.lift",
                type: .milestone,
                content: strongestLift,
                createdAt: today, updatedAt: today, confidence: 1.0
            ))
        }

        return results
    }

    // MARK: - Analysis helpers

    private static func preferredTrainingDays(sessions: [String: SessionEntry]) -> String? {
        guard sessions.count >= 8 else { return nil }
        var dayCounts: [Int: Int] = [:]
        let cal = Calendar.current
        for dateStr in sessions.keys {
            guard let date = DateFormatter.isoDate.date(from: dateStr) else { continue }
            let weekday = cal.component(.weekday, from: date)
            dayCounts[weekday, default: 0] += 1
        }
        let total = Double(sessions.count)
        let preferred = dayCounts.filter { Double($0.value) / total > 0.3 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { dayName($0.key) }
        guard !preferred.isEmpty else { return nil }
        return preferred.joined(separator: "/")
    }

    private static func rpePattern(sessions: [String: SessionEntry]) -> String? {
        let recent = sessions.sorted { $0.key > $1.key }.prefix(8).compactMap { $0.value.rpe }
        guard recent.count >= 5 else { return nil }
        let avg = recent.reduce(0, +) / Double(recent.count)
        if avg >= 8.5 {
            return "RPE moyen élevé sur les 8 dernières séances (\(String(format: "%.1f", avg))/10) — tendance à pousser fort"
        } else if avg <= 6.5 {
            return "RPE moyen bas sur les 8 dernières séances (\(String(format: "%.1f", avg))/10) — séances conservatrices"
        }
        return nil
    }

    private static func sessionCountMilestone(sessions: [String: SessionEntry]) -> String? {
        let count = sessions.count
        let milestones = [25, 50, 100, 150, 200, 300, 500]
        guard let m = milestones.filter({ count >= $0 }).max() else { return nil }
        return "\(count) séances enregistrées au total (cap. \(m)+)"
    }

    private static func sleepRisk(recovery: [RecoveryEntry]) -> String? {
        let withSleep = recovery.compactMap { $0.sleepHours }
        guard withSleep.count >= 5 else { return nil }
        let shortSleepRatio = Double(withSleep.filter { $0 < 7 }.count) / Double(withSleep.count)
        guard shortSleepRatio >= 0.45 else { return nil }
        let avg = withSleep.reduce(0, +) / Double(withSleep.count)
        return "Dort régulièrement moins de 7h (\(Int(shortSleepRatio * 100))% des nuits, moy. \(String(format: "%.1f", avg))h) — facteur de risque récupération"
    }

    private static func sessionLengthPattern(sessions: [String: SessionEntry]) -> String? {
        let durations = sessions.compactMap { $0.value.durationMin }.filter { $0 > 0 }
        guard durations.count >= 6 else { return nil }
        let avg = durations.reduce(0, +) / Double(durations.count)
        if avg < 55 {
            return "Séances courtes et intenses (durée moy. \(Int(avg))min)"
        } else if avg > 90 {
            return "Séances longues (durée moy. \(Int(avg))min) — volume élevé par session"
        }
        return nil
    }

    private static func strongestLift(weights: [String: WeightData]) -> String? {
        guard let (name, data) = weights
            .compactMap({ (k, v) -> (String, WeightData)? in v.currentWeight != nil ? (k, v) : nil })
            .max(by: { ($0.1.currentWeight ?? 0) < ($1.1.currentWeight ?? 0) })
        else { return nil }
        let w = data.currentWeight ?? 0
        return "Charge maximale actuelle : \(name) à \(String(format: "%.0f", w)) lbs"
    }

    private static func dayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "dim"
        case 2: return "lun"
        case 3: return "mar"
        case 4: return "mer"
        case 5: return "jeu"
        case 6: return "ven"
        case 7: return "sam"
        default: return "?"
        }
    }
}
