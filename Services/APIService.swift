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
//  GOALS        APIService+Goals.swift
//  NUTRITION    APIService+Nutrition.swift
//  CARDIO       APIService+Cardio.swift
//  WELLNESS     APIService+Wellness.swift
//  MENTAL       APIService+Mental.swift
//  SLEEP        APIService+Sleep.swift
// ─────────────────────────────────────────────────────────────────────────────
class APIService: ObservableObject {
    static let shared = APIService()

    let baseURL = APIConfig.base

    @Published var dashboard: DashboardData?
    @Published var isLoading = false
    @Published var isSlow = false
    @Published var error: String?
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

    // MARK: - Local date helpers (P1.4 — date toujours envoyée par l'iOS, jamais calculée côté serveur)
    static var todayLocalString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: Date())
    }

    static var yesterdayLocalString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        return fmt.string(from: yesterday)
    }

    private let logger = Logger(subsystem: "TrainingOS", category: "api")
    private var consecutiveDashboardFailures = 0
    private init() {}

    private let baseHost: String = URL(string: APIConfig.base)?.host ?? ""
    private let baseScheme: String = URL(string: APIConfig.base)?.scheme ?? "https"

    // MARK: - Cache helper
    // Stratégie : cache-first + stale-while-revalidate + background refresh.
    func fetchWithCache(url: URL, key: String) async throws -> Data {
        if let cached = CacheService.shared.load(for: key) {
            Task.detached(priority: .utility) {
                var req = URLRequest(url: url)
                req.timeoutInterval = 15
                req.cachePolicy = .reloadIgnoringLocalCacheData
                if let (fresh, resp) = try? await URLSession.authed.data(for: req),
                   (200...299).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) {
                    CacheService.shared.save(fresh, for: key)
                }
            }
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
    func offlinePost(endpoint: String, method: String = "POST", payload: [String: Any]) async throws -> Data? {
        guard let url = URL(string: APIConfig.base + endpoint) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod      = method
        req.timeoutInterval = 15
        if method != "DELETE" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        do {
            let (data, response) = try await URLSession.authed.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw APIError.serverError(http.statusCode, msg ?? "HTTP \(http.statusCode)")
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            await MainActor.run { SyncManager.shared.enqueue(endpoint: endpoint, method: method, payload: payload) }
            return nil  // nil = queued offline, distinct from any server response
        }
    }

    // MARK: - Dashboard
    func fetchDashboard() async {
        if let cached = CacheService.shared.load(for: "dashboard"),
           dashboard == nil {
            if let decoded = try? APIService.decoder.decode(DashboardData.self, from: cached) {
                await MainActor.run { self.dashboard = decoded }
            } else {
                logger.warning("⚠️ Dashboard cache decode failed — stale cache cleared")
                CacheService.shared.clear(for: "dashboard")
            }
        }

        await MainActor.run { isLoading = true; isSlow = false; error = nil }
        guard let url = try? buildURL(path: "/api/dashboard",
                                      queryItems: [URLQueryItem(name: "date", value: DateFormatter.isoDate.string(from: Date()))]) else {
            await MainActor.run { isLoading = false; error = "URL invalide — /api/dashboard" }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let slowTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { self.isSlow = true }
            }
        }
        do {
            let data: Data
            do {
                let (d, _) = try await URLSession.authed.data(for: req)
                CacheService.shared.save(d, for: "dashboard")
                data = d
            } catch {
                guard let cached = CacheService.shared.load(for: "dashboard") else { throw error }
                data = cached
            }
            slowTask.cancel()
            await MainActor.run { self.isSlow = false }
            let decoded = try APIService.decoder.decode(DashboardData.self, from: data)
            await MainActor.run {
                self.dashboard = decoded
                self.isLoading = false
                if decoded.alreadyLoggedToday { self.sessionLoggedToday = true }
                else { self.sessionLoggedToday = false }
                self.consecutiveDashboardFailures = 0
            }
            NotificationScheduler.shared.scheduleMorningNotification(for: decoded)
        } catch let decodingError as DecodingError {
            slowTask.cancel()
            let _ = decodingError  // keep for logging
            logger.error("❌ Dashboard decoding error: \(decodingError, privacy: .public)")
            await MainActor.run {
                if self.dashboard == nil { self.error = "Données incompatibles — mise à jour requise" }
                self.isLoading = false
                self.isSlow = false
                self.consecutiveDashboardFailures += 1
                if self.consecutiveDashboardFailures >= 3 { self.revertOptimisticFlagFromStaleCache() }
            }
        } catch {
            slowTask.cancel()
            await MainActor.run {
                if self.dashboard == nil { self.error = error.localizedDescription }
                self.isLoading = false
                self.isSlow = false
                self.consecutiveDashboardFailures += 1
                if self.consecutiveDashboardFailures >= 3 { self.revertOptimisticFlagFromStaleCache() }
            }
        }
    }

    // Called on MainActor — reads stale cache to verify sessionLoggedToday after 3 consecutive failures.
    // Prevents an optimistic flag from persisting indefinitely when the network is down.
    private func revertOptimisticFlagFromStaleCache() {
        guard sessionLoggedToday else { return }
        let (stale, _, _) = CacheService.shared.loadIncludingStale(for: "dashboard")
        if let stale, let decoded = try? APIService.decoder.decode(DashboardData.self, from: stale) {
            sessionLoggedToday = decoded.alreadyLoggedToday
        } else {
            sessionLoggedToday = false
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
