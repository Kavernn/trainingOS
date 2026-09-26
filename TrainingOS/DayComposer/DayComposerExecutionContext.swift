import Foundation

/// Passive provenance only: no drafts, owner, clock, ACK or persistence side effects.
struct DayComposerExecutionContext: Codable, Equatable {
    static let currentVersion = 1
    let version: Int
    let date: String
    let activeProgramID: String
    let sourceFingerprint: String
    let morningSession: String
    let eveningSession: String

    init(snapshot: DayComposerSnapshot) throws {
        version = Self.currentVersion
        date = snapshot.date
        activeProgramID = snapshot.activeProgramID
        sourceFingerprint = try snapshot.fingerprint
        morningSession = snapshot.morning.session
        eveningSession = snapshot.evening.session
    }

    enum Compatibility: Equatable {
        case compatible, unsupportedVersion, differentDate, differentProgram, differentSources
    }

    func compatibility(with current: Self) -> Compatibility {
        guard version == Self.currentVersion, current.version == Self.currentVersion else { return .unsupportedVersion }
        guard date == current.date else { return .differentDate }
        guard !activeProgramID.isEmpty, activeProgramID == current.activeProgramID else { return .differentProgram }
        guard !sourceFingerprint.isEmpty, sourceFingerprint == current.sourceFingerprint,
              morningSession == current.morningSession, eveningSession == current.eveningSession else {
            return .differentSources
        }
        return .compatible
    }
}

/// historique_data currently exposes exact names and session_type, not stable
/// session/exercise IDs or completion. Do not invent any of those missing fields.
struct DayComposerServerProjection {
    struct ObservedExercise: Hashable {
        let source: DayComposerSource
        let date: String
        let exactName: String
    }
    enum Presence: Equatable { case observed, unknown }
    let date: String
    let positivelyObserved: Set<ObservedExercise>

    private struct Page: Decodable {
        struct Session: Decodable {
            struct Exercise: Decodable { let exercise: String }
            let date: String
            let session_type: String
            let exos: [Exercise]
        }
        let session_list: [Session]
    }

    init(date: String, historyData: Data) throws {
        self.date = date
        let page = try JSONDecoder().decode(Page.self, from: historyData)
        positivelyObserved = Set(page.session_list.flatMap { session -> [ObservedExercise] in
            guard session.date == date, let source = DayComposerSource(rawValue: session.session_type) else { return [] }
            return session.exos.map { .init(source: source, date: date, exactName: $0.exercise) }
        })
    }

    func presence(of exactName: String, source: DayComposerSource) -> Presence {
        positivelyObserved.contains(.init(source: source, date: date, exactName: exactName)) ? .observed : .unknown
    }

    /// A bounded historical page gives positive evidence only. Pagination, ghost
    /// filtering and partial server history mean absence must ALWAYS stay unknown.
    @MainActor
    static func load(date: String) async throws -> Self {
        let url = try APIService.shared.buildURL(path: "/api/historique_data",
            queryItems: [URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "offset", value: "0")])
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await URLSession.authed.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DayComposerError.unavailable
        }
        return try Self(date: date, historyData: data)
    }
}
