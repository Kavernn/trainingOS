import Foundation
import Combine
import UserNotifications

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
    var errorDescription: String? {
        switch self {
        case .serverError(_, let msg): return msg
        case .queuedOffline: return "Enregistré hors-ligne — sera synchronisé à la reconnexion."
        }
    }
}

// MARK: - Offline-safe POST helper
// Every mutation goes through this. If the network call fails (offline),
// the payload is saved as a PendingMutation and replayed by SyncManager
// when connectivity returns. Returns true if sent live, false if queued.
// Returns nil when the mutation was queued offline (not an error).
// Returns non-nil Data on a successful server response.
// Throws APIError.serverError on 4xx/5xx, or URLError on bad config.
private func offlinePost(endpoint: String, payload: [String: Any]) async throws -> Data? {
    guard let url = URL(string: APIConfig.base + endpoint) else { throw URLError(.badURL) }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: payload)
    req.timeoutInterval = 15
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
        await MainActor.run { SyncManager.shared.enqueue(endpoint: endpoint, payload: payload) }
        return nil  // nil = queued offline, distinct from any server response
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// APIService domain map (all methods live in this file; split blocked by pbxproj)
//
//  WORKOUT      Dashboard · Séance · HIIT · Smart Progression · Deload · Weights
//  PROFILE      Body Weight · Profil · Wearable Sync · Stats
//  GOALS        Objectifs · Smart Goals · Insights · ACWR · Correlations
//  NUTRITION    Nutrition · Food Catalog
//  CARDIO       Cardio
//  WELLNESS     PSS · Life Stress · Coach · Peak Prediction · Morning Brief
//  MENTAL       Mood · Journal · Breathwork · Self-Care · Mental Health Dashboard
//  SLEEP        Sommeil
// ─────────────────────────────────────────────────────────────────────────────
class APIService: ObservableObject {
    static let shared = APIService()

    let baseURL = APIConfig.base

    @Published var dashboard: DashboardData?
    @Published var isLoading = false
    @Published var error: String?
    /// Optimistic flag — set immediately when logSession is called (online OR offline queued).
    /// Prevents "Commencer la séance" from reappearing while the fresh dashboard is loading.
    @Published var sessionLoggedToday = false

    private init() {}

    // MARK: - Cache helper
    // Timeout réseau : 15 s (couvre les cold starts Vercel sans bloquer 60 s)
    private func fetchWithCache(url: URL, key: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.authed.data(for: req)
            CacheService.shared.save(data, for: key)
            return data
        } catch {
            if let cached = CacheService.shared.load(for: key) {
                return cached
            }
            throw error
        }
    }

    // MARK: - Dashboard
    func fetchDashboard() async {
        // 1. Affiche le cache immédiatement → plus de spinner si données dispos
        if let cached = CacheService.shared.load(for: "dashboard"),
           let decoded = try? JSONDecoder().decode(DashboardData.self, from: cached),
           dashboard == nil {
            await MainActor.run { self.dashboard = decoded }
        }

        await MainActor.run { isLoading = true; error = nil }
        var req = URLRequest(url: URL(string: "\(baseURL)/api/dashboard")!)
        req.timeoutInterval = 15
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
            let decoded = try JSONDecoder().decode(DashboardData.self, from: data)
            await MainActor.run {
                self.dashboard = decoded
                self.isLoading = false
                // Sync optimistic flag with server truth
                if decoded.alreadyLoggedToday { self.sessionLoggedToday = true }
                else { self.sessionLoggedToday = false }
            }
            scheduleMorningNotification(for: decoded)
        } catch let decodingError as DecodingError {
            let msg: String
            switch decodingError {
            case .keyNotFound(let key, let ctx):
                msg = "Clé manquante: \(key.stringValue) — \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            case .typeMismatch(let type, let ctx):
                msg = "Type mismatch: attendu \(type) à \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            case .valueNotFound(let type, let ctx):
                msg = "Valeur manquante: \(type) à \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            default:
                msg = decodingError.localizedDescription
            }
            print("❌ Decoding error: \(msg)")
            await MainActor.run {
                if self.dashboard == nil { self.error = msg }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                if self.dashboard == nil { self.error = error.localizedDescription }
                self.isLoading = false
            }
        }
    }

    // MARK: - Morning Notification
    private func scheduleMorningNotification(for data: DashboardData) {
        // CODE-7: schedule at most once per calendar day — repeating trigger doesn't need re-registration
        let today = DateFormatter.isoDate.string(from: Date())
        let lastKey = "notif_morning_scheduled_date"
        guard UserDefaults.standard.string(forKey: lastKey) != today else { return }
        UserDefaults.standard.set(today, forKey: lastKey)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["morning-coaching"])

        let content = UNMutableNotificationContent()
        let sessionType = data.today
        content.title = "Bonne séance 💪"
        content.body  = "Au programme aujourd'hui : \(sessionType)"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour   = 7
        dateComponents.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "morning-coaching", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Seance Data
    func fetchSeanceData() async throws -> SeanceData {
        let url = URL(string: "\(baseURL)/api/seance_data")!
        let data = try await fetchWithCache(url: url, key: "seance_data")
        return try JSONDecoder().decode(SeanceData.self, from: data)
    }

    func logExercise(exercise: String, weight: Double, reps: String,
                     rpe: Double? = nil, sets: [[String: Any]] = [],
                     force: Bool = false, isSecond: Bool = false, isBonus: Bool = false,
                     equipmentType: String = "", painZone: String = "") async throws -> LogExerciseResponse {
        var body: [String: Any] = ["exercise": exercise, "weight": weight, "reps": reps]
        if let rpe { body["rpe"] = rpe }
        if !sets.isEmpty { body["sets"] = sets }
        if force    { body["force"] = true }
        if isSecond { body["is_second"] = true }
        if isBonus  { body["is_bonus"] = true }
        if !equipmentType.isEmpty { body["equipment_type"] = equipmentType }
        if !painZone.isEmpty { body["pain_zone"] = painZone }
        guard let data = try await offlinePost(endpoint: "/api/log", payload: body) else {
            return LogExerciseResponse(success: nil, newWeight: nil, oneRM: nil, isPR: nil)
        }
        if !isBonus { CacheService.shared.clear(for: isSecond ? "seance_soir_data" : "seance_data") }
        CacheService.shared.clear(for: "dashboard")
        CacheService.shared.clear(for: "stats_data")
        return (try? JSONDecoder().decode(LogExerciseResponse.self, from: data))
            ?? LogExerciseResponse(success: nil, newWeight: nil, oneRM: nil, isPR: nil)
    }

    func logSession(exos: [String], rpe: Double, comment: String,
                    durationMin: Double? = nil, energyPre: Int? = nil,
                    secondSession: Bool = false, bonusSession: Bool = false,
                    sessionName: String? = nil,
                    exerciseLogs: [[String: Any]] = []) async throws {
        var body: [String: Any] = ["exos": exos, "rpe": rpe, "comment": comment]
        if let d = durationMin  { body["duration_min"] = d }
        if let e = energyPre    { body["energy_pre"] = e }
        if secondSession        { body["second_session"] = true }
        if bonusSession         { body["bonus_session"] = true }
        if let n = sessionName, !n.isEmpty { body["session_name"] = n }
        if !exerciseLogs.isEmpty { body["exercise_logs"] = exerciseLogs }
        // Set optimistic flag immediately — works whether online or queued offline.
        if !secondSession && !bonusSession {
            await MainActor.run { sessionLoggedToday = true }
        }
        if try await offlinePost(endpoint: "/api/log_session", payload: body) != nil {
            CacheService.shared.clear(for: "dashboard")
            CacheService.shared.clear(for: "historique_data")
            if !bonusSession {
                CacheService.shared.clear(for: secondSession ? "seance_soir_data" : "seance_data")
            }
            CacheService.shared.clear(for: "stats_data")
        }
    }

    func fetchSeanceSoirData() async throws -> SeanceSoirData {
        let url = URL(string: "\(baseURL)/api/seance_soir_data")!
        let data = try await fetchWithCache(url: url, key: "seance_soir_data")
        return try JSONDecoder().decode(SeanceSoirData.self, from: data)
    }

    func deleteSession(date: String, sessionType: String = "morning") async throws {
        if try await offlinePost(endpoint: "/api/session/delete",
                                 payload: ["date": date, "session_type": sessionType]) != nil {
            CacheService.shared.clear(for: "historique_data")
            CacheService.shared.clear(for: "dashboard")
        }
    }

    func updateSession(date: String, rpe: Double?, comment: String, sessionType: String = "morning") async throws {
        var body: [String: Any] = ["date": date, "comment": comment, "session_type": sessionType]
        if let rpe { body["rpe"] = rpe }
        if try await offlinePost(endpoint: "/api/update_session", payload: body) != nil {
            CacheService.shared.clear(for: "historique_data")
            CacheService.shared.clear(for: "dashboard")
        }
    }

    func editSession(date: String, rpe: Double?, comment: String, sessionType: String = "morning",
                     exercises: [[String: Any]]? = nil) async throws {
        var body: [String: Any] = ["date": date, "comment": comment, "session_type": sessionType]
        if let rpe { body["rpe"] = rpe }
        if let exercises { body["exercises"] = exercises }
        if try await offlinePost(endpoint: "/api/session/edit", payload: body) != nil {
            CacheService.shared.clear(for: "historique_data")
            CacheService.shared.clear(for: "dashboard")
        }
    }

    // MARK: - HIIT
    func fetchHIITData() async throws -> [HIITEntry] {
        let url = URL(string: "\(baseURL)/api/hiit_data")!
        let data = try await fetchWithCache(url: url, key: "hiit_data")
        struct HIITResponse: Codable { let hiitLog: [HIITEntry]; enum CodingKeys: String, CodingKey { case hiitLog = "hiit_log" } }
        return try JSONDecoder().decode(HIITResponse.self, from: data).hiitLog
    }

    func logHIIT(sessionType: String, rounds: Int, workTime: Int, restTime: Int, rpe: Double, notes: String, secondSession: Bool = false) async throws {
        let body: [String: Any] = [
            "session_type": sessionType, "rounds": rounds,
            "work_time": workTime, "rest_time": restTime,
            "rpe": rpe, "notes": notes, "second_session": secondSession
        ]
        _ = try await offlinePost(endpoint: "/api/log_hiit", payload: body)
        CacheService.shared.clear(for: "dashboard")
        CacheService.shared.clear(for: "hiit_data")
    }

    func deleteHIIT(date: String, sessionType: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_hiit", payload: ["date": date, "session_type": sessionType])
    }

    func hiitEdit(body: [String: Any]) async throws -> Data {
        guard let data = try await offlinePost(endpoint: "/api/hiit/edit", payload: body) else {
            throw APIError.queuedOffline
        }
        return data
    }

    // MARK: - Body Weight / Profil
    func fetchProfilData() async throws -> (profile: UserProfile, bodyWeight: [BodyWeightEntry], tendance: String) {
        let url = URL(string: "\(baseURL)/api/profil_data")!
        let data = try await fetchWithCache(url: url, key: "profil_data")
        struct ProfilResponse: Codable {
            let profile: UserProfile
            let bodyWeight: [BodyWeightEntry]
            let tendance: String
            enum CodingKeys: String, CodingKey { case profile; case bodyWeight = "body_weight"; case tendance }
        }
        let r = try JSONDecoder().decode(ProfilResponse.self, from: data)
        return (r.profile, r.bodyWeight, r.tendance)
    }

    func addBodyWeight(date: String, weight: Double, bodyFat: Double?, waistCm: Double?,
                       armsCm: Double? = nil, chestCm: Double? = nil,
                       thighsCm: Double? = nil, hipsCm: Double? = nil) async throws {
        var body: [String: Any] = ["poids": weight]
        if let v = bodyFat  { body["body_fat"]  = v }
        if let v = waistCm  { body["waist_cm"]  = v }
        if let v = armsCm   { body["arms_cm"]   = v }
        if let v = chestCm  { body["chest_cm"]  = v }
        if let v = thighsCm { body["thighs_cm"] = v }
        if let v = hipsCm   { body["hips_cm"]   = v }
        _ = try await offlinePost(endpoint: "/api/body_weight", payload: body)
        CacheService.shared.clear(for: "profil_data")
    }

    func updateBodyWeight(date: String, oldWeight: Double, newWeight: Double, bodyFat: Double?, waistCm: Double?,
                          armsCm: Double? = nil, chestCm: Double? = nil,
                          thighsCm: Double? = nil, hipsCm: Double? = nil) async throws {
        var body: [String: Any] = ["date": date, "old_poids": oldWeight, "poids": newWeight]
        if let v = bodyFat  { body["body_fat"]  = v }
        if let v = waistCm  { body["waist_cm"]  = v }
        if let v = armsCm   { body["arms_cm"]   = v }
        if let v = chestCm  { body["chest_cm"]  = v }
        if let v = thighsCm { body["thighs_cm"] = v }
        if let v = hipsCm   { body["hips_cm"]   = v }
        _ = try await offlinePost(endpoint: "/api/body_weight/update", payload: body)
        CacheService.shared.clear(for: "profil_data")
    }

    func deleteBodyWeight(date: String, weight: Double) async throws {
        _ = try await offlinePost(endpoint: "/api/body_weight/delete", payload: ["date": date, "poids": weight])
        CacheService.shared.clear(for: "profil_data")
    }

    func updateProfile(name: String?, weight: Double?, height: Double?, age: Int?, goal: String?, level: String?, sex: String?) async throws {
        var body: [String: Any] = [:]
        if let v = name   { body["name"]   = v }
        if let v = weight { body["weight"] = v }
        if let v = height { body["height"] = v }
        if let v = age    { body["age"]    = v }
        if let v = goal   { body["goal"]   = v }
        if let v = level  { body["level"]  = v }
        if let v = sex    { body["sex"]    = v }
        _ = try await offlinePost(endpoint: "/api/update_profile", payload: body)
    }

    // MARK: - Objectifs
    func fetchObjectifsData() async throws -> [ObjectifEntry] {
        let url = URL(string: "\(baseURL)/api/objectifs_data")!
        let data = try await fetchWithCache(url: url, key: "objectifs_data")
        struct ObjResponse: Codable { let goals: [String: ObjData] }
        struct ObjData: Codable {
            let current: Double; let goal: Double; let achieved: Bool
            let deadline: String?; let note: String?; let archived: Bool?
        }
        let r = try JSONDecoder().decode(ObjResponse.self, from: data)
        return r.goals.map { ex, d in
            ObjectifEntry(exercise: ex, current: d.current, goal: d.goal,
                          achieved: d.achieved, deadline: d.deadline ?? "", note: d.note ?? "",
                          archived: d.archived ?? false)
        }.sorted { $0.exercise < $1.exercise }
    }

    func archiveObjectif(exercise: String) async throws {
        _ = try await offlinePost(endpoint: "/api/archive_objectif", payload: ["exercise": exercise])
    }

    func setGoal(exercise: String, goalWeight: Double, deadline: String) async throws {
        _ = try await offlinePost(endpoint: "/api/set_goal", payload: [
            "exercise": exercise, "goal_weight": goalWeight, "deadline": deadline
        ])
    }

    // MARK: - Smart Goals
    func fetchSmartGoals() async throws -> [SmartGoalEntry] {
        let url = URL(string: "\(baseURL)/api/smart_goals")!
        let data = try await fetchWithCache(url: url, key: "smart_goals")
        struct R: Codable { let smart_goals: [SmartGoalEntry] }
        return try JSONDecoder().decode(R.self, from: data).smart_goals
    }

    func saveSmartGoal(type: String, targetValue: Double, targetDate: String, id: String? = nil) async throws {
        var payload: [String: Any] = ["type": type, "target_value": targetValue, "target_date": targetDate]
        if let id { payload["id"] = id }
        _ = try await offlinePost(endpoint: "/api/smart_goals/save", payload: payload)
    }

    func deleteSmartGoal(id: String) async throws {
        _ = try await offlinePost(endpoint: "/api/smart_goals/delete", payload: ["id": id])
    }

    // MARK: - Health Dashboard
    func fetchDailyHealthSummary(date: String? = nil) async throws -> DailyHealthSummary {
        var urlStr = "\(baseURL)/api/health/daily_summary"
        if let date { urlStr += "?date=\(date)" }
        let url = URL(string: urlStr)!
        let key = "health_daily_\(date ?? "today")"
        let data = try await fetchWithCache(url: url, key: key)
        return try JSONDecoder().decode(DailyHealthSummary.self, from: data)
    }

    func fetchWeeklyHealthSummary(days: Int = 7) async throws -> [DailyHealthSummary] {
        let url = URL(string: "\(baseURL)/api/health/weekly_summary?days=\(days)")!
        let data = try await fetchWithCache(url: url, key: "health_weekly_\(days)")
        return try JSONDecoder().decode([DailyHealthSummary].self, from: data)
    }

    // MARK: - PSS
    func fetchPSSQuestions(isShort: Bool = false) async throws -> [PSSQuestion] {
        let url = URL(string: "\(baseURL)/api/pss/questions?short=\(isShort)")!
        let data = try await fetchWithCache(url: url, key: "pss_questions_\(isShort)")
        return try JSONDecoder().decode([PSSQuestion].self, from: data)
    }

    func submitPSS(
        responses: [Int],
        isShort: Bool = false,
        notes: String? = nil,
        triggers: [String] = [],
        triggerRatings: [String: Int] = [:]
    ) async throws -> PSSRecord {
        var body: [String: Any] = ["responses": responses, "is_short": isShort]
        if let notes { body["notes"] = notes }
        if !triggers.isEmpty { body["triggers"] = triggers }
        if !triggerRatings.isEmpty { body["trigger_ratings"] = triggerRatings }
        guard let data = try await offlinePost(endpoint: "/api/pss/submit", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheService.shared.clear(for: "pss_history")
        CacheService.shared.clear(for: "pss_check_due_full")
        return try JSONDecoder().decode(PSSRecord.self, from: data)
    }

    func fetchPSSHistory(type: String? = nil) async throws -> [PSSRecord] {
        var urlStr = "\(baseURL)/api/pss/history"
        if let type { urlStr += "?type=\(type)" }
        let url = URL(string: urlStr)!
        let data = try await fetchWithCache(url: url, key: "pss_history")
        return try JSONDecoder().decode([PSSRecord].self, from: data)
    }

    func checkPSSDue(type: String = "full") async throws -> PSSDueStatus {
        let url = URL(string: "\(baseURL)/api/pss/check_due?type=\(type)")!
        let data = try await fetchWithCache(url: url, key: "pss_check_due_\(type)")
        return try JSONDecoder().decode(PSSDueStatus.self, from: data)
    }

    // MARK: - Life Stress Engine
    func fetchLifeStressScore(date: String? = nil, forceRefresh: Bool = false) async throws -> LifeStressScore {
        var urlStr = "\(baseURL)/api/life_stress/score"
        var params: [String] = []
        if let date { params.append("date=\(date)") }
        if forceRefresh { params.append("refresh=true") }
        if !params.isEmpty { urlStr += "?" + params.joined(separator: "&") }
        let url = URL(string: urlStr)!
        let key = "life_stress_\(date ?? "today")"
        let data = try await fetchWithCache(url: url, key: key)
        return try JSONDecoder().decode(LifeStressScore.self, from: data)
    }

    func fetchLifeStressTrend(days: Int = 7) async throws -> [LifeStressScore] {
        let url = URL(string: "\(baseURL)/api/life_stress/trend?days=\(days)")!
        let data = try await fetchWithCache(url: url, key: "life_stress_trend_\(days)")
        return try JSONDecoder().decode([LifeStressScore].self, from: data)
    }

    // MARK: - Generated Program

    func generateProgram() async throws -> GeneratedProgram {
        let url = URL(string: "\(baseURL)/api/ai/generate_program")!
        var req = URLRequest(url: url)
        req.httpMethod  = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        let (data, response) = try await URLSession.authed.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "API", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "Erreur \(http.statusCode)"])
        }
        return try JSONDecoder().decode(GeneratedProgram.self, from: data)
    }

    func fetchLatestGeneratedProgram() async throws -> GeneratedProgram? {
        let url = URL(string: "\(baseURL)/api/ai/generated_program/latest")!
        let (data, response) = try await URLSession.authed.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(GeneratedProgram.self, from: data)
    }

    /// Approve a generated program: creates a real Programme + séances + exercices via existing API.
    /// Returns the new programme_id on success.
    func approveGeneratedProgram(_ gp: GeneratedProgram) async throws -> String {
        let content = gp.programJson
        let week1   = content.weeks.first

        // 1. Create programme
        let progUrl = URL(string: "\(baseURL)/api/programs")!
        var progReq = URLRequest(url: progUrl)
        progReq.httpMethod = "POST"
        progReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        progReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": "create",
            "name": "\(content.name) — \(dateStr)"
        ])
        let (progData, _) = try await URLSession.authed.data(for: progReq)
        guard let progJson = try JSONSerialization.jsonObject(with: progData) as? [String: Any],
              let programmeId = progJson["id"] as? String else {
            throw NSError(domain: "API", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Impossible de créer le programme"])
        }

        // 2. Create each unique séance (from week 1 day names)
        let days = week1?.days ?? []
        for day in days {
            var seanceReq = URLRequest(url: URL(string: "\(baseURL)/api/programme")!)
            seanceReq.httpMethod = "POST"
            seanceReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            seanceReq.httpBody = try JSONSerialization.data(withJSONObject: [
                "action":     "create_seance",
                "jour":       day.name,
                "program_id": programmeId
            ])
            _ = try? await URLSession.authed.data(for: seanceReq)
        }

        // 3. Add exercises (week 1 schemes)
        for day in days {
            for ex in day.exercises {
                let scheme = "\(ex.sets)x\(ex.reps)"
                var exReq = URLRequest(url: URL(string: "\(baseURL)/api/programme")!)
                exReq.httpMethod = "POST"
                exReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                exReq.httpBody = try JSONSerialization.data(withJSONObject: [
                    "action":     "add",
                    "jour":       day.name,
                    "exercise":   ex.name,
                    "scheme":     scheme,
                    "program_id": programmeId
                ])
                _ = try? await URLSession.authed.data(for: exReq)
            }
        }

        // 4. Apply 5-day schedule
        if !content.schedule.isEmpty {
            var schedReq = URLRequest(url: URL(string: "\(baseURL)/api/morning_schedule")!)
            schedReq.httpMethod = "POST"
            schedReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            schedReq.httpBody = try JSONSerialization.data(withJSONObject: ["schedule": content.schedule])
            _ = try? await URLSession.authed.data(for: schedReq)
        }

        // 5. Mark generated program as active
        var approveReq = URLRequest(url: URL(string: "\(baseURL)/api/ai/generated_program/approve")!)
        approveReq.httpMethod = "POST"
        approveReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        approveReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": gp.id,
            "programme_id": programmeId
        ])
        _ = try? await URLSession.authed.data(for: approveReq)

        CacheService.shared.clear(for: "programme_data")
        CacheService.shared.clear(for: "stats_data")
        return programmeId
    }

    func fetchPostWorkoutBrief(sessionType: String, rpe: Double?, exos: [String], comment: String?, date: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/ai/post_workout")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        var body: [String: Any] = ["session_type": sessionType, "exos": exos, "date": date]
        if let rpe { body["rpe"] = rpe }
        if let comment, !comment.isEmpty { body["comment"] = comment }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.authed.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let brief = json["brief"] as? String else {
            throw URLError(.badServerResponse)
        }
        return brief
    }

    func fetchWeeklyNarrative(context: String, weekKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/ai/narrative")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["context": context, "week": weekKey])
        let (data, _) = try await URLSession.authed.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let narrative = json["narrative"] as? String else {
            throw URLError(.badServerResponse)
        }
        return narrative
    }

    func fetchPeakPrediction() async throws -> PeakPredictionResponse {
        let url = URL(string: "\(baseURL)/api/peak_prediction")!
        let data = try await fetchWithCache(url: url, key: "peak_prediction")
        return try JSONDecoder().decode(PeakPredictionResponse.self, from: data)
    }

    // MARK: - Coach du jour
    func fetchDailyCoachTip() async throws -> CoachTip {
        let today = DateFormatter.isoDate.string(from: Date())
        let cacheKey = "coach_tip_\(today)"
        let url = URL(string: "\(baseURL)/api/coach/daily_tip")!
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try JSONDecoder().decode(CoachTip.self, from: data)
    }

    // MARK: - ACWR
    func fetchACWR() async throws -> ACWRData {
        let url = URL(string: "\(baseURL)/api/acwr")!
        let data = try await fetchWithCache(url: url, key: "acwr")
        return try JSONDecoder().decode(ACWRData.self, from: data)
    }

    // MARK: - Deload
    func fetchInsights() async throws -> [InsightEntry] {
        let url = URL(string: "\(baseURL)/api/insights")!
        let data = try await fetchWithCache(url: url, key: "insights")
        struct R: Codable { let insights: [InsightEntry] }
        return try JSONDecoder().decode(R.self, from: data).insights
    }

    func fetchDeloadData() async throws -> DeloadReport {
        let url = URL(string: "\(baseURL)/api/deload")!
        let data = try await fetchWithCache(url: url, key: "deload")
        return try JSONDecoder().decode(DeloadReport.self, from: data)
    }

    // MARK: - Food Catalog

    func fetchFoodCatalog() async -> [FoodItem] {
        guard let url = URL(string: "\(baseURL)/api/food_catalog"),
              let data = try? await fetchWithCache(url: url, key: "food_catalog") else { return [] }
        return FoodCatalogStore.decodeFromAPI(data)
    }

    func saveFoodCatalog(_ items: [FoodItem]) async {
        guard let url = URL(string: "\(baseURL)/api/food_catalog"),
              let body = FoodCatalogStore.encodeForAPI(items) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 15
        _ = try? await URLSession.authed.data(for: req)
        CacheService.shared.clear(for: "food_catalog")
    }

    // MARK: - Nutrition
    func fetchNutritionData() async throws -> (settings: NutritionSettings?, entries: [NutritionEntry], totals: NutritionTotals?) {
        let url = URL(string: "\(baseURL)/api/nutrition_data")!
        let data = try await fetchWithCache(url: url, key: "nutrition_data")
        struct NutrResponse: Codable {
            let settings: NutritionSettings?
            let entries: [NutritionEntry]
            let totals: NutritionTotals?
        }
        let r = try JSONDecoder().decode(NutrResponse.self, from: data)
        return (r.settings, r.entries, r.totals)
    }

    func fetchNutritionHistory() async throws -> [NutritionDayHistory] {
        let url = URL(string: "\(baseURL)/api/nutrition_data")!
        let data = try await fetchWithCache(url: url, key: "nutrition_data")
        let r = try JSONDecoder().decode(NutritionDataResponse.self, from: data)
        return r.history
    }

    func addNutritionEntry(name: String, calories: Double, proteines: Double, glucides: Double,
                           lipides: Double, mealType: String? = nil, source: String = "manual") async throws {
        var payload: [String: Any] = [
            "nom": name, "calories": calories,
            "proteines": proteines, "glucides": glucides, "lipides": lipides,
            "source": source
        ]
        if let mt = mealType { payload["meal_type"] = mt }
        _ = try await offlinePost(endpoint: "/api/nutrition/add", payload: payload)
        BehaviorTracker.shared.record(.nutritionLog)
    }

    func scanNutritionLabel(imageBase64: String, quantity: Double, unit: String) async throws -> ScanResult {
        let url = URL(string: "\(baseURL)/api/nutrition/scan-label")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        let payload: [String: Any] = [
            "image_base64": imageBase64,
            "media_type":   "image/jpeg",
            "quantity":     quantity,
            "unit":         unit
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                      ?? "Erreur serveur (\(http.statusCode))"
            throw ScanLabelError(message: msg)
        }
        return try JSONDecoder().decode(ScanResult.self, from: data)
    }

    func updateNutritionSettings(calories: Double, proteines: Double, glucides: Double, lipides: Double) async throws {
        _ = try await offlinePost(endpoint: "/api/nutrition/settings", payload: [
            "limite_calories":    Int(calories),
            "objectif_proteines": Int(proteines),
            "glucides":           glucides,
            "lipides":            lipides,
        ])
    }

    // MARK: - Cardio
    func fetchCardioData() async throws -> [CardioEntry] {
        let url = URL(string: "\(baseURL)/api/cardio_data")!
        let data = try await fetchWithCache(url: url, key: "cardio_data")
        struct Resp: Codable { let cardioLog: [CardioEntry]; enum CodingKeys: String, CodingKey { case cardioLog = "cardio_log" } }
        return try JSONDecoder().decode(Resp.self, from: data).cardioLog
    }

    func logCardio(type: String, durationMin: Double?, distanceKm: Double?, avgPace: String?,
                   avgHr: Double?, cadence: Double?, calories: Double?, rpe: Double?, notes: String) async throws {
        var body: [String: Any] = ["type": type, "notes": notes]
        if let v = durationMin { body["duration_min"] = v }
        if let v = distanceKm  { body["distance_km"] = v }
        if let v = avgPace     { body["avg_pace"] = v }
        if let v = avgHr       { body["avg_hr"] = v }
        if let v = cadence     { body["cadence"] = v }
        if let v = calories    { body["calories"] = v }
        if let v = rpe         { body["rpe"] = v }
        _ = try await offlinePost(endpoint: "/api/log_cardio", payload: body)
    }

    func deleteCardio(date: String, type: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_cardio", payload: ["date": date, "type": type])
        CacheService.shared.clear(for: "cardio_history")
        CacheService.shared.clear(for: "stats_cardio")
    }

    // MARK: - Recovery
    func fetchRecoveryData() async throws -> [RecoveryEntry] {
        let url = URL(string: "\(baseURL)/api/recovery_data")!
        let data = try await fetchWithCache(url: url, key: "recovery_data")
        struct Resp: Codable { let recoveryLog: [RecoveryEntry]; enum CodingKeys: String, CodingKey { case recoveryLog = "recovery_log" } }
        return try JSONDecoder().decode(Resp.self, from: data).recoveryLog
    }

    func logRecovery(sleepHours: Double?, sleepQuality: Double?, restingHr: Double?,
                     hrv: Double?, steps: Int?, soreness: Double?, activeEnergy: Double? = nil,
                     hrMorning: Double? = nil, hrPostWorkout: Double? = nil, hrEvening: Double? = nil,
                     notes: String, date: String? = nil) async throws {
        var body: [String: Any] = ["notes": notes]
        if let v = sleepHours      { body["sleep_hours"]      = v }
        if let v = sleepQuality    { body["sleep_quality"]    = v }
        if let v = restingHr       { body["resting_hr"]       = v }
        if let v = hrv             { body["hrv"]              = v }
        if let v = steps           { body["steps"]            = v }
        if let v = soreness        { body["soreness"]         = v }
        if let v = activeEnergy    { body["active_energy"]    = v }
        if let v = hrMorning       { body["hr_morning"]       = Int(v) }
        if let v = hrPostWorkout   { body["hr_post_workout"]  = Int(v) }
        if let v = hrEvening       { body["hr_evening"]       = Int(v) }
        if let d = date            { body["date"]             = d }
        _ = try await offlinePost(endpoint: "/api/log_recovery", payload: body)
        CacheService.shared.clear(for: "recovery_data")
    }

    func deleteRecovery(date: String) async throws {
        _ = try await offlinePost(endpoint: "/api/delete_recovery", payload: ["date": date])
    }

    // MARK: - Wearable Sync (Apple Watch → Supabase)
    func syncWearableData(_ snapshot: WearableSnapshot) async throws {
        var body: [String: Any] = ["date": snapshot.date]
        if let v = snapshot.steps         { body["steps"]           = v }
        if let v = snapshot.sleepHours    { body["sleep_hours"]    = v }
        if let v = snapshot.restingHr     { body["resting_hr"]     = v }
        if let v = snapshot.hrv           { body["hrv"]            = v }
        if let v = snapshot.activeEnergy  { body["active_energy"]  = v }
        // body_weight_lbs intentionally excluded — weight is manual-entry only

        let workouts: [[String: Any]] = snapshot.workouts.map { w in
            var entry: [String: Any] = [
                "type":         w.type,
                "duration_min": w.durationMin
            ]
            if let v = w.distanceKm { entry["distance_km"] = v }
            if let v = w.calories   { entry["calories"]    = v }
            if let v = w.avgHr      { entry["avg_hr"]      = v }
            if let v = w.avgPace    { entry["avg_pace"]    = v }
            return entry
        }
        body["workouts"] = workouts

        _ = try await offlinePost(endpoint: "/api/wearable/sync", payload: body)
        CacheService.shared.clear(for: "recovery_data")
        CacheService.shared.clear(for: "cardio_data")
    }

    // MARK: - Weights (for stats)
    func fetchWeights() async throws -> [String: WeightData] {
        let url = URL(string: "\(baseURL)/api/weights")!
        let data = try await fetchWithCache(url: url, key: "weights")
        return try JSONDecoder().decode([String: WeightData].self, from: data)
    }

    // MARK: - Santé Mentale — Mood

    func fetchMoodEmotions() async throws -> [MoodEmotion] {
        let url = URL(string: "\(baseURL)/api/mood/emotions")!
        let data = try await fetchWithCache(url: url, key: "mood_emotions")
        return try JSONDecoder().decode([MoodEmotion].self, from: data)
    }

    func submitMood(score: Int, emotions: [String], notes: String?, triggers: [String]) async throws -> MoodEntry {
        var body: [String: Any] = ["score": score, "emotions": emotions, "triggers": triggers]
        if let notes { body["notes"] = notes }
        guard let data = try await offlinePost(endpoint: "/api/mood/log", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheService.shared.clear(for: "mood_history")
        CacheService.shared.clear(for: "mood_check_due")
        return try JSONDecoder().decode(MoodEntry.self, from: data)
    }

    func fetchMoodHistory(days: Int = 90, limit: Int = 20, offset: Int = 0) async throws -> PagedResponse<MoodEntry> {
        let cacheKey = offset == 0 ? "mood_history" : "mood_history_\(offset)"
        let url = URL(string: "\(baseURL)/api/mood/history?days=\(days)&limit=\(limit)&offset=\(offset)")!
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try JSONDecoder().decode(PagedResponse<MoodEntry>.self, from: data)
    }

    func checkMoodDue() async throws -> MoodDueStatus {
        let url = URL(string: "\(baseURL)/api/mood/check_due")!
        let data = try await fetchWithCache(url: url, key: "mood_check_due")
        return try JSONDecoder().decode(MoodDueStatus.self, from: data)
    }

    // MARK: - Santé Mentale — Journal

    func fetchJournalPrompt() async throws -> String {
        let url = URL(string: "\(baseURL)/api/journal/today_prompt")!
        let data = try await fetchWithCache(url: url, key: "journal_prompt")
        let obj = try JSONDecoder().decode([String: String].self, from: data)
        return obj["prompt"] ?? ""
    }

    func submitJournalEntry(prompt: String, content: String, moodScore: Int? = nil) async throws -> JournalEntry {
        var body: [String: Any] = ["prompt": prompt, "content": content]
        if let m = moodScore { body["mood_score"] = m }
        guard let data = try await offlinePost(endpoint: "/api/journal/save", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheService.shared.clear(for: "journal_entries")
        return try JSONDecoder().decode(JournalEntry.self, from: data)
    }

    func fetchJournalEntries(limit: Int = 20, offset: Int = 0) async throws -> PagedResponse<JournalEntry> {
        let cacheKey = offset == 0 ? "journal_entries" : "journal_entries_\(offset)"
        let url = URL(string: "\(baseURL)/api/journal/entries?limit=\(limit)&offset=\(offset)")!
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try JSONDecoder().decode(PagedResponse<JournalEntry>.self, from: data)
    }

    // MARK: - Santé Mentale — Breathwork

    func fetchBreathworkTechniques() async throws -> [BreathworkTechnique] {
        let url = URL(string: "\(baseURL)/api/breathwork/techniques")!
        let data = try await fetchWithCache(url: url, key: "breathwork_techniques")
        return try JSONDecoder().decode([BreathworkTechnique].self, from: data)
    }

    func submitBreathworkSession(techniqueId: String, durationSec: Int, cycles: Int) async throws -> BreathworkSession {
        guard let data = try await offlinePost(endpoint: "/api/breathwork/log", payload: [
            "technique_id": techniqueId,
            "duration_sec": durationSec,
            "cycles": cycles,
        ]) else { throw APIError.queuedOffline }
        CacheService.shared.clear(for: "breathwork_stats")
        return try JSONDecoder().decode(BreathworkSession.self, from: data)
    }

    func fetchBreathworkStats(days: Int = 7) async throws -> BreathworkStats {
        let url = URL(string: "\(baseURL)/api/breathwork/stats?days=\(days)")!
        let data = try await fetchWithCache(url: url, key: "breathwork_stats")
        return try JSONDecoder().decode(BreathworkStats.self, from: data)
    }

    // MARK: - Santé Mentale — Self-Care

    func fetchSelfCareHabits() async throws -> [SelfCareHabit] {
        let url = URL(string: "\(baseURL)/api/self_care/habits")!
        let data = try await fetchWithCache(url: url, key: "self_care_habits")
        return try JSONDecoder().decode([SelfCareHabit].self, from: data)
    }

    func fetchSelfCareToday() async throws -> SelfCareToday {
        let url = URL(string: "\(baseURL)/api/self_care/today")!
        let data = try await fetchWithCache(url: url, key: "self_care_today")
        return try JSONDecoder().decode(SelfCareToday.self, from: data)
    }

    func submitSelfCareLog(habitIds: [String]) async throws -> SelfCareToday {
        guard let data = try await offlinePost(endpoint: "/api/self_care/log", payload: ["habit_ids": habitIds])
        else { throw APIError.queuedOffline }
        CacheService.shared.clear(for: "self_care_today")
        CacheService.shared.clear(for: "self_care_streaks")
        return try JSONDecoder().decode(SelfCareToday.self, from: data)
    }

    func fetchSelfCareStreaks() async throws -> [SelfCareStreak] {
        let url = URL(string: "\(baseURL)/api/self_care/streaks")!
        let data = try await fetchWithCache(url: url, key: "self_care_streaks")
        return try JSONDecoder().decode([SelfCareStreak].self, from: data)
    }

    func addSelfCareHabit(name: String, icon: String, category: String) async throws -> SelfCareHabit {
        guard let data = try await offlinePost(endpoint: "/api/self_care/habits", payload: ["name": name, "icon": icon, "category": category])
        else { throw APIError.queuedOffline }
        CacheService.shared.clear(for: "self_care_habits")
        CacheService.shared.clear(for: "self_care_today")
        return try JSONDecoder().decode(SelfCareHabit.self, from: data)
    }

    // MARK: - Santé Mentale — Dashboard

    func fetchMentalHealthSummary(days: Int = 7) async throws -> MentalHealthSummary {
        let url = URL(string: "\(baseURL)/api/mental_health/summary?days=\(days)")!
        let data = try await fetchWithCache(url: url, key: "mental_health_summary_\(days)")
        return try JSONDecoder().decode(MentalHealthSummary.self, from: data)
    }

    // MARK: - Sommeil

    func fetchSleepHistory(limit: Int = 20, offset: Int = 0) async throws -> PagedResponse<SleepEntry> {
        let cacheKey = offset == 0 ? "sleep_history" : "sleep_history_\(offset)"
        let url = URL(string: "\(baseURL)/api/sleep/history?limit=\(limit)&offset=\(offset)")!
        let data = try await fetchWithCache(url: url, key: cacheKey)
        return try JSONDecoder().decode(PagedResponse<SleepEntry>.self, from: data)
    }

    func fetchSleepToday() async throws -> SleepEntry? {
        let url = URL(string: "\(baseURL)/api/sleep/today")!
        let data = try await fetchWithCache(url: url, key: "sleep_today")
        return try? JSONDecoder().decode(SleepEntry.self, from: data)
    }

    func fetchSleepStats() async throws -> SleepStats {
        let url = URL(string: "\(baseURL)/api/sleep/stats")!
        let data = try await fetchWithCache(url: url, key: "sleep_stats")
        return try JSONDecoder().decode(SleepStats.self, from: data)
    }

    func logSleep(bedtime: String, wakeTime: String, quality: Int, notes: String?) async throws -> SleepEntry {
        var body: [String: Any] = ["bedtime": bedtime, "wake_time": wakeTime, "quality": quality]
        if let notes = notes, !notes.isEmpty { body["notes"] = notes }
        guard let data = try await offlinePost(endpoint: "/api/sleep/log", payload: body) else {
            throw APIError.queuedOffline
        }
        CacheService.shared.clear(for: "sleep_history")
        CacheService.shared.clear(for: "sleep_today")
        CacheService.shared.clear(for: "sleep_stats")
        return try JSONDecoder().decode(SleepEntry.self, from: data)
    }

    func deleteSleepEntry(id: String) async throws {
        _ = try await offlinePost(endpoint: "/api/sleep/delete", payload: ["id": id])
        CacheService.shared.clear(for: "sleep_history")
        CacheService.shared.clear(for: "sleep_today")
        CacheService.shared.clear(for: "sleep_stats")
    }

    // MARK: - Stats Data (background warm-up for ghost mode)
    func fetchStatsData() async throws {
        let url = URL(string: "\(baseURL)/api/stats_data")!
        var req = URLRequest(url: url); req.timeoutInterval = 15
        let (data, _) = try await URLSession.authed.data(for: req)
        CacheService.shared.save(data, for: "stats_data")
    }

    // MARK: - Morning Brief
    func fetchMorningBrief() async throws -> MorningBriefData {
        let url = URL(string: "\(baseURL)/api/coach/morning_brief")!
        let data = try await fetchWithCache(url: url, key: "morning_brief")
        return try JSONDecoder().decode(MorningBriefData.self, from: data)
    }

    // MARK: - Cross-Correlation Insights
    func fetchCorrelations(days: Int = 60) async throws -> CorrelationsData {
        let url = URL(string: "\(baseURL)/api/insights/correlations?days=\(days)")!
        let data = try await fetchWithCache(url: url, key: "correlations")
        return try JSONDecoder().decode(CorrelationsData.self, from: data)
    }

    // MARK: - Smart Progression
    func fetchProgressionSuggestions(date: String, sessionType: String, sessionName: String = "") async throws -> [ProgressionSuggestion] {
        var urlStr = "\(baseURL)/api/progression_suggestions?date=\(date)&session_type=\(sessionType)"
        if !sessionName.isEmpty, let encoded = sessionName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlStr += "&session_name=\(encoded)"
        }
        let url = URL(string: urlStr)!
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.authed.data(for: req)
        let decoded = try JSONDecoder().decode(ProgressionSuggestionsResponse.self, from: data)
        return decoded.suggestions
    }

    func applyProgression(exerciseName: String, suggestedWeight: Double, suggestedScheme: String?) async throws {
        var payload: [String: Any] = [
            "exercise_name": exerciseName,
            "suggested_weight": suggestedWeight
        ]
        if let scheme = suggestedScheme {
            payload["suggested_scheme"] = scheme
        }
        _ = try await offlinePost(endpoint: "/api/apply_progression", payload: payload)
    }

    // MARK: - Smart Day Recommendation
    func fetchSmartDay() async throws -> SmartDayRecommendation {
        let url = URL(string: "\(baseURL)/api/smart_day")!
        let data = try await fetchWithCache(url: url, key: "smart_day")
        return try JSONDecoder().decode(SmartDayRecommendation.self, from: data)
    }

    // MARK: - Weekly Report
    func fetchWeeklyReport() async throws -> WeeklyReport {
        let url = URL(string: "\(baseURL)/api/weekly_report")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.authed.data(for: req)
        return try JSONDecoder().decode(WeeklyReport.self, from: data)
    }

    // MARK: - Deload
    func applyDeload(poidsDeload: [String: Double]) async throws {
        let url = URL(string: "\(baseURL)/api/apply_deload")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["poids_deload": poidsDeload])
        req.timeoutInterval = 15
        let (_, resp) = try await URLSession.authed.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.serverError(http.statusCode, "Impossible d'appliquer le déload pour le moment.")
        }
        CacheService.shared.clear(for: "seance_data")
        CacheService.shared.clear(for: "dashboard")
    }
}

// MARK: - Scan Label models

struct ScanResult: Decodable {
    let nom:       String
    let calories:  Int
    let proteines: Double
    let glucides:  Double
    let lipides:   Double
    let fibres:    Double
    let sodiumMg:  Double
    enum CodingKeys: String, CodingKey {
        case nom, calories, proteines, glucides, lipides, fibres
        case sodiumMg = "sodium_mg"
    }
}

struct ScanLabelError: Error {
    let message: String
}
