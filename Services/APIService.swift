import Foundation
import Combine
import OSLog

// MARK: - Authenticated URLSession
extension URLSession {
    /// Injects Authorization header on every request. Use instead of URLSession.shared.
    static let authed: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Authorization": "Bearer \(APIConfig.apiKey)"]
        config.timeoutIntervalForRequest = 15
        // Défaut Apple iOS = 4 connexions/host — trop bas pour le dashboard Santé
        // qui charge 12 endpoints en parallèle. Bumped à 12 pour libérer le
        // parallélisme réel côté client (gain mesuré : 2.17s → 1.69s).
        config.httpMaximumConnectionsPerHost = 12
        return URLSession(configuration: config)
    }()
}

// MARK: - API Errors
enum APIError: LocalizedError {
    case serverError(Int, String)
    case queuedOffline  // mutation enqueued — not a failure, just deferred
    case invalidURL(path: String)
    case decodingFailed(endpoint: String, error: Error)
    var errorDescription: String? {
        switch self {
        case .serverError(_, let msg): return msg
        case .queuedOffline: return "Enregistré hors-ligne — sera synchronisé à la reconnexion."
        case .invalidURL(let path): return "URL invalide — \(path)"
        case .decodingFailed(let endpoint, _): return "Données incompatibles sur \(endpoint) — mise à jour requise"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  WORKOUT      APIService+Workout.swift
//  PROFILE      APIService+Profile.swift
//  NUTRITION    APIService+Nutrition.swift
//  CARDIO       APIService+Cardio.swift
//  WELLNESS     APIService+Wellness.swift
//  MENTAL       APIService+Mental.swift
//  SLEEP        APIService+Sleep.swift
// ─────────────────────────────────────────────────────────────────────────────

/// Display-only weekly plan. Never resolves dated execution overrides.
struct DashboardPlan: Codable {
    struct Programme: Codable {
        let active_program_id: String
        let current_program_id: String
        let schedule: [String: String]
        let full_program: [String: [String: SafeString]]

        var isActive: Bool {
            !active_program_id.isEmpty && active_program_id == current_program_id
        }

        func matches(_ other: Programme) -> Bool {
            active_program_id == other.active_program_id && other.isActive &&
            schedule == other.schedule &&
            full_program.mapValues { $0.mapValues(\.value) } ==
                other.full_program.mapValues { $0.mapValues(\.value) }
        }
    }

    let programme: Programme
    let eveningSchedule: [String: String]

    func morning(on date: Date) -> String {
        validSession(programme.schedule[TrainingDoctrine.dayName(on: date)]) ?? "Repos"
    }

    func evening(on date: Date) -> String? {
        validSession(eveningSchedule[TrainingDoctrine.dayName(on: date)])
    }

    private func validSession(_ name: String?) -> String? {
        guard let name, !name.isEmpty, name != "Repos", programme.full_program[name] != nil else { return nil }
        return name
    }
}

enum DashboardLoadMode {
    case initial
    case refresh
}

/// Loading state separated from data so views that only read dashboard
/// don't re-render when isLoading/isSlow/error toggle during fetchDashboard.
@MainActor
final class APILoadingState: ObservableObject {
    static let shared = APILoadingState()
    private init() {}
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isSlow = false
    @Published var error: String?
}

class APIService: ObservableObject {
    static let shared = APIService()

    let baseURL = APIConfig.base

    @Published var dashboard: DashboardData?
    @Published private(set) var dashboardPlan: DashboardPlan?
    @MainActor private var dashboardGeneration = 0
    @MainActor var dashboardContextVersion: Int { dashboardGeneration }
    @MainActor private var dashboardRequestRunning = false
    @MainActor private var dashboardScope: (program: String, date: String)?
    private let dashboardDefaults: UserDefaults
    private static let dashboardPlanKey = "dashboard_active_weekly_plan_v1"
    /// Optimistic flag — set immediately when logSession is called (online OR offline queued).
    /// Prevents "Commencer la séance" from reappearing while the fresh dashboard is loading.
    @Published var sessionLoggedToday = false

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let logger = Logger(subsystem: "TrainingOS", category: "api")
    private var consecutiveDashboardFailures = 0
    init(dashboardDefaults: UserDefaults = .standard) {
        self.dashboardDefaults = dashboardDefaults
        if let data = dashboardDefaults.data(forKey: Self.dashboardPlanKey),
           let plan = try? JSONDecoder().decode(DashboardPlan.self, from: data), plan.programme.isActive {
            dashboardPlan = plan
        }
    }

    private let baseHost: String = URL(string: APIConfig.base)?.host ?? ""
    private let baseScheme: String = URL(string: APIConfig.base)?.scheme ?? "https"

    // MARK: - Cache helper
    // Stratégie : cache-first (TTL respecté) + stale-while-revalidate sur expiration.
    // Le refresh background ne se déclenche QUE si le cache est périmé — pas à chaque hit.
    // Fraîcheur garantie par : TTL par clé (CacheService.ttls) + invalidation explicite post-mutation.
    func fetchWithCache(url: URL, key: String) async throws -> Data {
        if let cached = CacheService.shared.load(for: key) {
            return cached
        }
        // Expired: serve stale data immediately + background refresh — never block
        let (stale, _, _) = CacheService.shared.loadIncludingStale(for: key)
        if let stale {
            Task.detached(priority: .utility) {
                var req = URLRequest(url: url)
                req.timeoutInterval = 15
                req.cachePolicy = .reloadIgnoringLocalCacheData
                if let (fresh, resp) = try? await URLSession.authed.data(for: req),
                   (200...299).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) {
                    CacheService.shared.save(fresh, for: key)
                }
            }
            return stale
        }
        // No cache at all: foreground fetch (first launch or after explicit clear)
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.authed.data(for: req)
        guard (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw URLError(.badServerResponse)
        }
        CacheService.shared.save(data, for: key)
        return data
    }

    // Variante décodée avec self-healing sur cache empoisonné :
    // un 200 avec body indécodable (ex : ancien fantôme backend {"error": ...})
    // est mis en cache par fetchWithCache. Ici on tente le decode ; s'il throw,
    // on clear (mémoire + disque) et on refetch le réseau une fois. Adoption
    // opt-in — les callers qui veulent le filet migrent, les autres restent.
    func fetchWithCacheDecoded<T: Decodable>(url: URL, key: String, as type: T.Type) async throws -> T {
        let data = try await fetchWithCache(url: url, key: key)
        do {
            return try APIService.decoder.decode(T.self, from: data)
        } catch {
            CacheService.shared.clear(for: key)
            let fresh = try await fetchWithCache(url: url, key: key)
            return try APIService.decoder.decode(T.self, from: fresh)
        }
    }

    // MARK: - URL Builder
    func buildURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = baseScheme
        components.host = baseHost
        components.path = path
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw APIError.invalidURL(path: path) }
        return url
    }

    // MARK: - Offline-safe POST helper
    // Every mutation goes through this. If the network call fails (offline),
    // the payload is saved as a PendingMutation and replayed by SyncManager
    // when connectivity returns.
    // Returns non-nil Data on a successful server response.
    // Returns nil when the mutation was queued offline (not an error).
    // Throws APIError.serverError on 4xx/5xx, or URLError on bad config.
    func offlinePost(endpoint: String, method: String = "POST", payload: [String: Any],
                     transport: ((URLRequest) async throws -> (Data, URLResponse))? = nil,
                     enqueue: ((String, String, [String: Any]) -> Void)? = nil) async throws -> Data? {
        guard let url = URL(string: APIConfig.base + endpoint) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod      = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(APIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        if method != "DELETE" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        do {
            let (data, response): (Data, URLResponse)
            if let transport { (data, response) = try await transport(req) }
            else { (data, response) = try await URLSession.authed.data(for: req) }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let parsed = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                let msg = parsed["message"] as? String ?? parsed["error"] as? String
                throw APIError.serverError(http.statusCode, msg ?? "HTTP \(http.statusCode)")
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            await MainActor.run {
                if let enqueue { enqueue(endpoint, method, payload) }
                else { SyncManager.shared.enqueue(endpoint: endpoint, method: method, payload: payload) }
            }
            return nil  // nil = queued offline, distinct from any server response
        }
    }

    /// Additive correlated path. Construct JSON once; queue/replay keep these bytes.
    /// delivered transport is NOT a business response ACK or recovery ACK.
    func offlinePostCorrelated(endpoint: String, method: String = "POST", payload: [String: Any],
                               operationKey: OfflineOperationKey,
                               manager: SyncManager? = nil,
                               transport: ((URLRequest) async throws -> (Data, URLResponse))? = nil) async throws -> CorrelatedOfflinePostOutcome {
        let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let sync = await MainActor.run { manager ?? SyncManager.shared }
        return try await sync.postCorrelated(endpoint: endpoint, method: method, payloadData: bytes,
                                             operationKey: operationKey, transport: transport)
    }

    // MARK: - Dashboard
    @MainActor func publishActivePlanningChange() {
        // Drop in-flight Dashboard responses, but retain the visible plan until
        // its replacement is validated. This event concerns active planning only.
        dashboardGeneration += 1
        dashboardRequestRunning = false
        NotificationCenter.default.post(name: .activeProgrammePlanningDidChange, object: nil)
        Task { await self.fetchDashboard(mode: .refresh) }
    }

    /// Root Séance tab only. Other execution owners keep their existing loaders.
    @MainActor func fetchCurrentPlannedSeance(
        date: Date, preserveRecovery: Bool,
        transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.authed.data(for: $0) }
    ) async throws -> (program: String, data: SeanceData) {
        let day = DateFormatter.isoDate.string(from: date)
        func read<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
            var request = URLRequest(url: try buildURL(path: path, queryItems: query), cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 15
            let (bytes, response) = try await transport(request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            return try JSONDecoder().decode(T.self, from: bytes)
        }
        let before: DashboardPlan.Programme = try await read("/api/programme_data")
        guard before.isActive else { throw URLError(.cancelled) }
        let query = [URLQueryItem(name: "date", value: day), URLQueryItem(name: "program_id", value: before.active_program_id)]
        let execution: SeanceData = try await read("/api/seance_data", query: query)
        let hasServerProgress = execution.weights.values.contains { weight in
            weight.history?.contains { $0.date == day && ($0.sessionType ?? "morning") == "morning" } == true
        }
        let planned = DashboardPlan(programme: before, eveningSchedule: [:]).morning(on: date)
        let result: SeanceData
        if preserveRecovery || hasServerProgress || execution.alreadyLogged || execution.today == planned {
            result = execution
        } else {
            // Explicit read-only selector bypasses the dated override. Do not
            // mutate it. Completed/partial execution above retains its identity.
            result = try await read("/api/seance_data", query: query + [URLQueryItem(name: "session_name", value: planned)])
            guard result.today == planned else { throw URLError(.badServerResponse) }
        }
        let after: DashboardPlan.Programme = try await read("/api/programme_data")
        guard before.matches(after), result.todayDate == day else { throw URLError(.cancelled) }
        return (before.active_program_id, result)
    }

    /// Activation/deletion invalidates context, not a routine refresh. Old requests
    /// cannot republish their results after this boundary.
    @MainActor func invalidateDashboardContext() {
        dashboardGeneration += 1
        dashboardRequestRunning = false
        dashboardScope = nil
        dashboard = nil
        dashboardPlan = nil
        sessionLoggedToday = false
        dashboardDefaults.removeObject(forKey: Self.dashboardPlanKey)
        APILoadingState.shared.isLoading = false
        APILoadingState.shared.isRefreshing = false
        APILoadingState.shared.isSlow = false
        APILoadingState.shared.error = nil
    }

    @discardableResult
    @MainActor func fetchDashboard(
        mode: DashboardLoadMode = .initial,
        now: () -> Date = { Date() },
        transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.authed.data(for: $0) }
    ) async -> Bool {
        guard !dashboardRequestRunning else { return false }
        dashboardRequestRunning = true
        dashboardGeneration += 1
        let generation = dashboardGeneration
        let date = DateFormatter.isoDate.string(from: now())
        // Retain only certified metrics for this day. Refresh never tears down a
        // coherent ScrollView; initial load alone uses the empty/loading branch.
        if dashboardScope?.date != date { dashboard = nil; dashboardScope = nil }
        // A refresh has its own activity state. Only an initial load (or a
        // refresh without any usable content) can request the loading surface.
        APILoadingState.shared.isRefreshing = mode == .refresh
        APILoadingState.shared.isLoading = mode == .initial || (dashboard == nil && dashboardPlan == nil)
        APILoadingState.shared.isSlow = false
        APILoadingState.shared.error = nil
        defer {
            if generation == dashboardGeneration {
                dashboardRequestRunning = false
                APILoadingState.shared.isLoading = false
                APILoadingState.shared.isRefreshing = false
                APILoadingState.shared.isSlow = false
            }
        }
        func current() -> Bool {
            generation == dashboardGeneration && date == DateFormatter.isoDate.string(from: now()) && !Task.isCancelled
        }
        func read<T: Decodable>(_ path: String, dated: Bool = false) async throws -> T {
            let url = try buildURL(path: path, queryItems: dated ? [URLQueryItem(name: "date", value: date)] : [])
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 15
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
        do {
            let before: DashboardPlan.Programme = try await read("/api/programme_data")
            guard current(), before.isActive else { return false }
            if dashboardScope?.program != before.active_program_id {
                dashboard = nil; dashboardScope = nil
            }
            if dashboardPlan?.programme.active_program_id != before.active_program_id {
                dashboardPlan = nil
                dashboardDefaults.removeObject(forKey: Self.dashboardPlanKey)
            }
            let evening: [String: String] = try await read("/api/evening_schedule")
            let after: DashboardPlan.Programme = try await read("/api/programme_data")
            guard current() else { return false }
            guard before.matches(after) else { invalidateDashboardContext(); return false }
            let plan = DashboardPlan(programme: before, eveningSchedule: evening)
            // Persist the weekly plan independently: even a failed metrics request
            // can leave a correct, date-resolved offline presentation.
            dashboardPlan = plan
            dashboardDefaults.set(try JSONEncoder().encode(plan), forKey: Self.dashboardPlanKey)
            let decoded: DashboardData = try await read("/api/dashboard", dated: true)
            let finalContext: DashboardPlan.Programme = try await read("/api/programme_data")
            guard current() else { return false }
            guard before.matches(finalContext) else { invalidateDashboardContext(); return false }
            guard decoded.todayDate == date else { throw URLError(.badServerResponse) }
            dashboardScope = (before.active_program_id, date)
            dashboard = decoded
            sessionLoggedToday = decoded.alreadyLoggedToday
            consecutiveDashboardFailures = 0
            NotificationScheduler.shared.scheduleMorningNotification(for: decoded)
            return true
        } catch {
            guard current(), !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled else { return false }
            // Full-page failure is only appropriate without prior coherent data.
            if dashboard == nil {
                APILoadingState.shared.error = error is DecodingError
                    ? "Données incompatibles — mise à jour requise" : error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Coach Memory (server-side sync)

    func fetchCoachMemory() async throws -> [[String: Any]] {
        let url = try buildURL(path: "/api/coach/memory")
        let (data, resp) = try await URLSession.authed.data(for: URLRequest(url: url))
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.serverError(http.statusCode, "fetchCoachMemory HTTP \(http.statusCode)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["entries"] as? [[String: Any]] ?? []
    }

    func saveCoachMemory(_ entries: [[String: Any]]) async throws {
        let url = try buildURL(path: "/api/coach/memory")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["entries": entries])
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError.serverError(http.statusCode, msg ?? "saveCoachMemory HTTP \(http.statusCode)")
        }
    }
}
