import Foundation
import Combine

class APIService: ObservableObject {
    static let shared = APIService()

    private let baseURL = "https://training-os-rho.vercel.app"

    @Published var dashboard: DashboardData?
    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    // MARK: - Cache helper
    // Timeout réseau : 15 s (couvre les cold starts Vercel sans bloquer 60 s)
    private func fetchWithCache(url: URL, key: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
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
                let (d, _) = try await URLSession.shared.data(for: req)
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
            }
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

    // MARK: - Seance Data
    func fetchSeanceData() async throws -> SeanceData {
        let url = URL(string: "\(baseURL)/api/seance_data")!
        let data = try await fetchWithCache(url: url, key: "seance_data")
        return try JSONDecoder().decode(SeanceData.self, from: data)
    }

    func logExercise(exercise: String, weight: Double, reps: String,
                     sets: [[String: Any]] = []) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/api/log")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["exercise": exercise, "weight": weight, "reps": reps]
        if !sets.isEmpty { body["sets"] = sets }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func logSession(exos: [String], rpe: Double, comment: String,
                    durationMin: Double? = nil, energyPre: Int? = nil) async throws {
        let url = URL(string: "\(baseURL)/api/log_session")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["exos": exos, "rpe": rpe, "comment": comment]
        if let d = durationMin { body["duration_min"] = d }
        if let e = energyPre   { body["energy_pre"] = e }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await URLSession.shared.data(for: req)
        CacheService.shared.clear(for: "dashboard")
        CacheService.shared.clear(for: "seance_data")
        CacheService.shared.clear(for: "stats_data")
    }

    func deleteSession(date: String) async throws {
        let url = URL(string: "\(baseURL)/api/session/delete")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["date": date])
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    // MARK: - HIIT
    func fetchHIITData() async throws -> [HIITEntry] {
        let url = URL(string: "\(baseURL)/api/hiit_data")!
        let data = try await fetchWithCache(url: url, key: "hiit_data")
        struct HIITResponse: Codable { let hiitLog: [HIITEntry]; enum CodingKeys: String, CodingKey { case hiitLog = "hiit_log" } }
        return try JSONDecoder().decode(HIITResponse.self, from: data).hiitLog
    }

    func logHIIT(sessionType: String, rounds: Int, workTime: Int, restTime: Int, rpe: Double, notes: String, secondSession: Bool = false) async throws {
        let url = URL(string: "\(baseURL)/api/log_hiit")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "session_type": sessionType,
            "rounds": rounds,
            "work_time": workTime,
            "rest_time": restTime,
            "rpe": rpe,
            "notes": notes,
            "second_session": secondSession
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await URLSession.shared.data(for: req)
        CacheService.shared.clear(for: "dashboard")
        CacheService.shared.clear(for: "hiit_data")
    }

    func deleteHIIT(date: String, sessionType: String) async throws {
        let url = URL(string: "\(baseURL)/api/delete_hiit")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["date": date, "session_type": sessionType])
        let (_, _) = try await URLSession.shared.data(for: req)
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
        let url = URL(string: "\(baseURL)/api/body_weight")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["poids": weight]
        if let v = bodyFat  { body["body_fat"]  = v }
        if let v = waistCm  { body["waist_cm"]  = v }
        if let v = armsCm   { body["arms_cm"]   = v }
        if let v = chestCm  { body["chest_cm"]  = v }
        if let v = thighsCm { body["thighs_cm"] = v }
        if let v = hipsCm   { body["hips_cm"]   = v }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    func updateBodyWeight(date: String, oldWeight: Double, newWeight: Double, bodyFat: Double?, waistCm: Double?,
                          armsCm: Double? = nil, chestCm: Double? = nil,
                          thighsCm: Double? = nil, hipsCm: Double? = nil) async throws {
        let url = URL(string: "\(baseURL)/api/body_weight/update")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["date": date, "old_poids": oldWeight, "poids": newWeight]
        if let v = bodyFat  { body["body_fat"]  = v }
        if let v = waistCm  { body["waist_cm"]  = v }
        if let v = armsCm   { body["arms_cm"]   = v }
        if let v = chestCm  { body["chest_cm"]  = v }
        if let v = thighsCm { body["thighs_cm"] = v }
        if let v = hipsCm   { body["hips_cm"]   = v }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    func deleteBodyWeight(date: String, weight: Double) async throws {
        let url = URL(string: "\(baseURL)/api/body_weight/delete")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["date": date, "poids": weight])
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    func updateProfile(name: String?, weight: Double?, height: Double?, age: Int?, goal: String?, level: String?, sex: String?) async throws {
        let url = URL(string: "\(baseURL)/api/update_profile")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let v = name { body["name"] = v }
        if let v = weight { body["weight"] = v }
        if let v = height { body["height"] = v }
        if let v = age { body["age"] = v }
        if let v = goal { body["goal"] = v }
        if let v = level { body["level"] = v }
        if let v = sex { body["sex"] = v }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    // MARK: - Objectifs
    func fetchObjectifsData() async throws -> [ObjectifEntry] {
        let url = URL(string: "\(baseURL)/api/objectifs_data")!
        let data = try await fetchWithCache(url: url, key: "objectifs_data")
        struct ObjResponse: Codable { let goals: [String: ObjData] }
        struct ObjData: Codable {
            let current: Double; let goal: Double; let achieved: Bool
            let deadline: String?; let note: String?
        }
        let r = try JSONDecoder().decode(ObjResponse.self, from: data)
        return r.goals.map { ex, d in
            ObjectifEntry(exercise: ex, current: d.current, goal: d.goal,
                          achieved: d.achieved, deadline: d.deadline ?? "", note: d.note ?? "")
        }.sorted { $0.exercise < $1.exercise }
    }

    func setGoal(exercise: String, goalWeight: Double, deadline: String) async throws {
        let url = URL(string: "\(baseURL)/api/set_goal")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "exercise": exercise, "goal_weight": goalWeight, "deadline": deadline
        ])
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    // MARK: - Stats
    func fetchStatsData() async throws -> (
        weights: [String: WeightData],
        sessions: [String: SessionEntry],
        hiitLog: [HIITEntry],
        bodyWeight: [BodyWeightEntry],
        recoveryLog: [RecoveryEntry],
        nutritionTarget: NutritionSettings?,
        nutritionDays: [NutritionDay]
    ) {
        let url = URL(string: "\(baseURL)/api/stats_data")!
        let data = try await fetchWithCache(url: url, key: "stats_data")
        struct StatsResponse: Codable {
            let weights: [String: WeightData]
            let sessions: [String: SessionEntry]
            let hiitLog: [HIITEntry]
            let bodyWeight: [BodyWeightEntry]
            let recoveryLog: [RecoveryEntry]
            let nutritionTarget: NutritionSettings?
            let nutritionDays: [NutritionDay]
            enum CodingKeys: String, CodingKey {
                case weights, sessions
                case hiitLog         = "hiit_log"
                case bodyWeight      = "body_weight"
                case recoveryLog     = "recovery_log"
                case nutritionTarget = "nutrition_target"
                case nutritionDays   = "nutrition_days"
            }
        }
        let r = try JSONDecoder().decode(StatsResponse.self, from: data)
        return (r.weights, r.sessions, r.hiitLog, r.bodyWeight, r.recoveryLog, r.nutritionTarget, r.nutritionDays)
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
        let url = URL(string: "\(baseURL)/api/pss/submit")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "responses": responses,
            "is_short":  isShort,
        ]
        if let notes { body["notes"] = notes }
        if !triggers.isEmpty { body["triggers"] = triggers }
        if !triggerRatings.isEmpty { body["trigger_ratings"] = triggerRatings }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        CacheService.shared.clear(for: "pss_history")
        CacheService.shared.clear(for: "pss_check_due_full")
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                   ?? "Erreur serveur \(http.statusCode)"
            throw NSError(domain: "PSS", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
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

    // MARK: - Deload
    func fetchDeloadData() async throws -> DeloadReport {
        let url = URL(string: "\(baseURL)/api/deload")!
        let data = try await fetchWithCache(url: url, key: "deload")
        return try JSONDecoder().decode(DeloadReport.self, from: data)
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

    func addNutritionEntry(name: String, calories: Double, proteines: Double, glucides: Double, lipides: Double) async throws {
        let url = URL(string: "\(baseURL)/api/nutrition/add")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "nom": name, "calories": calories,
            "proteines": proteines, "glucides": glucides, "lipides": lipides
        ])
        let (_, _) = try await URLSession.shared.data(for: req)
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
        let url = URL(string: "\(baseURL)/api/log_cardio")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["type": type, "notes": notes]
        if let v = durationMin { body["duration_min"] = v }
        if let v = distanceKm  { body["distance_km"] = v }
        if let v = avgPace     { body["avg_pace"] = v }
        if let v = avgHr       { body["avg_hr"] = v }
        if let v = cadence     { body["cadence"] = v }
        if let v = calories    { body["calories"] = v }
        if let v = rpe         { body["rpe"] = v }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    func deleteCardio(date: String, type: String) async throws {
        let url = URL(string: "\(baseURL)/api/delete_cardio")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["date": date, "type": type])
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    // MARK: - Recovery
    func fetchRecoveryData() async throws -> [RecoveryEntry] {
        let url = URL(string: "\(baseURL)/api/recovery_data")!
        let data = try await fetchWithCache(url: url, key: "recovery_data")
        struct Resp: Codable { let recoveryLog: [RecoveryEntry]; enum CodingKeys: String, CodingKey { case recoveryLog = "recovery_log" } }
        return try JSONDecoder().decode(Resp.self, from: data).recoveryLog
    }

    func logRecovery(sleepHours: Double?, sleepQuality: Double?, restingHr: Double?,
                     hrv: Double?, steps: Int?, soreness: Double?, notes: String) async throws {
        let url = URL(string: "\(baseURL)/api/log_recovery")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["notes": notes]
        if let v = sleepHours   { body["sleep_hours"] = v }
        if let v = sleepQuality { body["sleep_quality"] = v }
        if let v = restingHr    { body["resting_hr"] = v }
        if let v = hrv          { body["hrv"] = v }
        if let v = steps        { body["steps"] = v }
        if let v = soreness     { body["soreness"] = v }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    func deleteRecovery(date: String) async throws {
        let url = URL(string: "\(baseURL)/api/delete_recovery")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["date": date])
        let (_, _) = try await URLSession.shared.data(for: req)
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
        let url = URL(string: "\(baseURL)/api/mood/log")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["score": score, "emotions": emotions, "triggers": triggers]
        if let notes { body["notes"] = notes }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        CacheService.shared.clear(for:"mood_history")
        CacheService.shared.clear(for:"mood_check_due")
        return try JSONDecoder().decode(MoodEntry.self, from: data)
    }

    func fetchMoodHistory(days: Int = 30) async throws -> [MoodEntry] {
        let url = URL(string: "\(baseURL)/api/mood/history?days=\(days)")!
        let data = try await fetchWithCache(url: url, key: "mood_history")
        return try JSONDecoder().decode([MoodEntry].self, from: data)
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

    func submitJournalEntry(prompt: String, content: String) async throws -> JournalEntry {
        let url = URL(string: "\(baseURL)/api/journal/save")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": prompt, "content": content])
        let (data, _) = try await URLSession.shared.data(for: req)
        CacheService.shared.clear(for:"journal_entries")
        return try JSONDecoder().decode(JournalEntry.self, from: data)
    }

    func fetchJournalEntries(limit: Int = 30) async throws -> [JournalEntry] {
        let url = URL(string: "\(baseURL)/api/journal/entries?limit=\(limit)")!
        let data = try await fetchWithCache(url: url, key: "journal_entries")
        return try JSONDecoder().decode([JournalEntry].self, from: data)
    }

    // MARK: - Santé Mentale — Breathwork

    func fetchBreathworkTechniques() async throws -> [BreathworkTechnique] {
        let url = URL(string: "\(baseURL)/api/breathwork/techniques")!
        let data = try await fetchWithCache(url: url, key: "breathwork_techniques")
        return try JSONDecoder().decode([BreathworkTechnique].self, from: data)
    }

    func submitBreathworkSession(techniqueId: String, durationSec: Int, cycles: Int) async throws -> BreathworkSession {
        let url = URL(string: "\(baseURL)/api/breathwork/log")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "technique_id": techniqueId,
            "duration_sec": durationSec,
            "cycles": cycles,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        CacheService.shared.clear(for:"breathwork_stats")
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
        let url = URL(string: "\(baseURL)/api/self_care/log")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["habit_ids": habitIds])
        let (data, _) = try await URLSession.shared.data(for: req)
        CacheService.shared.clear(for:"self_care_today")
        CacheService.shared.clear(for:"self_care_streaks")
        return try JSONDecoder().decode(SelfCareToday.self, from: data)
    }

    func fetchSelfCareStreaks() async throws -> [SelfCareStreak] {
        let url = URL(string: "\(baseURL)/api/self_care/streaks")!
        let data = try await fetchWithCache(url: url, key: "self_care_streaks")
        return try JSONDecoder().decode([SelfCareStreak].self, from: data)
    }

    func addSelfCareHabit(name: String, icon: String, category: String) async throws -> SelfCareHabit {
        let url = URL(string: "\(baseURL)/api/self_care/habits")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "icon": icon, "category": category])
        let (data, _) = try await URLSession.shared.data(for: req)
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

    func fetchSleepHistory(limit: Int = 30) async throws -> [SleepEntry] {
        let url = URL(string: "\(baseURL)/api/sleep/history?limit=\(limit)")!
        let data = try await fetchWithCache(url: url, key: "sleep_history")
        return try JSONDecoder().decode([SleepEntry].self, from: data)
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
        let url = URL(string: "\(baseURL)/api/sleep/log")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["bedtime": bedtime, "wake_time": wakeTime, "quality": quality]
        if let notes = notes, !notes.isEmpty { body["notes"] = notes }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        CacheService.shared.clear(for: "sleep_history")
        CacheService.shared.clear(for: "sleep_today")
        CacheService.shared.clear(for: "sleep_stats")
        return try JSONDecoder().decode(SleepEntry.self, from: data)
    }

    func deleteSleepEntry(id: String) async throws {
        let url = URL(string: "\(baseURL)/api/sleep/delete")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        _ = try await URLSession.shared.data(for: req)
        CacheService.shared.clear(for: "sleep_history")
        CacheService.shared.clear(for: "sleep_today")
        CacheService.shared.clear(for: "sleep_stats")
    }
}
