import Foundation

// MARK: - Breathwork

enum BreathworkProtocol: String, Codable, CaseIterable {
    case calm_storm, ignite, stillness

    var displayName: String {
        switch self {
        case .calm_storm: return "Calm the Storm"
        case .ignite:     return "Ignite"
        case .stillness:  return "Stillness"
        }
    }

    var subtitle: String {
        switch self {
        case .calm_storm: return "4–7–8 · Craving · Stress aigu"
        case .ignite:     return "Breath of Fire · Matin · Pré-workout"
        case .stillness:  return "Box 4-4-4-4 · Soir · Rituel"
        }
    }

    var systemIcon: String {
        switch self {
        case .calm_storm: return "waveform.path"
        case .ignite:     return "flame"
        case .stillness:  return "square"
        }
    }
}

struct SpiritBreathSession: Codable, Identifiable {
    let id: String
    let protocol_: BreathworkProtocol
    let durationSec: Int
    let cycles: Int
    let startedAt: String
    let triggeredFrom: String

    enum CodingKeys: String, CodingKey {
        case id, cycles
        case protocol_      = "protocol"
        case durationSec    = "duration_sec"
        case startedAt      = "started_at"
        case triggeredFrom  = "triggered_from"
    }
}

// MARK: - Meditation

struct MeditationSession: Codable, Identifiable {
    let id: String
    let plannedSec: Int
    let actualSec: Int
    let bellInterval: Int
    let startedAt: String
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case id, completed
        case plannedSec  = "planned_sec"
        case actualSec   = "actual_sec"
        case bellInterval = "bell_interval"
        case startedAt   = "started_at"
    }
}

// MARK: - Spirit Journal

struct SpiritJournalEntry: Codable, Identifiable {
    let id: String
    let date: String
    var gratefulFor: String?
    var conquered: String?
    var haunting: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, date, conquered, haunting
        case gratefulFor = "grateful_for"
        case createdAt   = "created_at"
    }
}

struct SpiritJournalStub: Codable, Identifiable {
    let id: String
    let date: String
}

// MARK: - Spirit Config

struct SpiritConfig: Codable {
    var integrationPhoenix: Bool

    enum CodingKeys: String, CodingKey {
        case integrationPhoenix = "integration_phoenix"
    }
}

// MARK: - Patterns

struct SpiritInsight: Codable, Identifiable {
    let type: String
    let title: String
    let body: String
    let detail: String?
    var id: String { type }
}

struct SpiritPatterns: Codable {
    let insights: [SpiritInsight]
    let totalSessions: Int
    let enoughData: Bool

    enum CodingKeys: String, CodingKey {
        case insights
        case totalSessions = "total_sessions"
        case enoughData    = "enough_data"
    }
}

// MARK: - Breath protocol definition (local, not from API)

struct BreathPhaseStep {
    let label: String        // "INSPIRE", "RETIENS", "EXPIRE", "ATTENDS"
    let duration: Int        // seconds
    let endScale: CGFloat    // 0.6 (lungs empty) or 1.0 (lungs full)
    let countsCycle: Bool    // increment cyclesCompleted after this step
}

struct BreathProtocolDef {
    let id: BreathworkProtocol
    let steps: [BreathPhaseStep]
    let targetCycles: Int

    static let calm_storm = BreathProtocolDef(
        id: .calm_storm,
        steps: [
            BreathPhaseStep(label: "INSPIRE", duration: 4, endScale: 1.0, countsCycle: false),
            BreathPhaseStep(label: "RETIENS",  duration: 7, endScale: 1.0, countsCycle: false),
            BreathPhaseStep(label: "EXPIRE",   duration: 8, endScale: 0.55, countsCycle: true),
        ],
        targetCycles: 6
    )

    static let ignite = BreathProtocolDef(
        id: .ignite,
        steps: [
            BreathPhaseStep(label: "INSPIRE", duration: 1, endScale: 1.0, countsCycle: false),
            BreathPhaseStep(label: "EXPIRE",  duration: 1, endScale: 0.55, countsCycle: true),
        ],
        targetCycles: 90  // 30 breaths × 3 rounds
    )

    static let stillness = BreathProtocolDef(
        id: .stillness,
        steps: [
            BreathPhaseStep(label: "INSPIRE", duration: 4, endScale: 1.0,  countsCycle: false),
            BreathPhaseStep(label: "RETIENS",  duration: 4, endScale: 1.0,  countsCycle: false),
            BreathPhaseStep(label: "EXPIRE",   duration: 4, endScale: 0.55, countsCycle: false),
            BreathPhaseStep(label: "ATTENDS",  duration: 4, endScale: 0.55, countsCycle: true),
        ],
        targetCycles: 8
    )

    static func forProtocol(_ p: BreathworkProtocol) -> BreathProtocolDef {
        switch p {
        case .calm_storm: return .calm_storm
        case .ignite:     return .ignite
        case .stillness:  return .stillness
        }
    }
}
