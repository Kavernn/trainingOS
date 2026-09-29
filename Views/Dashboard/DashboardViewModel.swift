import SwiftUI
import Combine
import OSLog

// MARK: - Main-actor phase results, published as each structured child completes

final class P2State: @unchecked Sendable {
    var deload: DeloadReport? = nil
    var moodDue: MoodDueStatus? = nil
    var morningBrief: MorningBriefData? = nil
    var morningBriefFailed = false
    var todayRecovery: RecoveryEntry? = nil
    var hrvAnalysis: HRVAnalysis? = nil
    var yesterdayNutrition: NutritionDayHistory? = nil
    var todayNutritionType: String? = nil
    var dailyPattern: PatternEntry? = nil
    var ritualToday: RitualToday? = nil
    var cardioToday: CardioEntry? = nil
    var budgetStatus: BudgetStatus? = nil
    var criticalFailures = 0
    var receivedRecovery = false
    var receivedCardio = false
    var receivedPattern = false
    var receivedNutrition = false
}

final class P3State: @unchecked Sendable {
    var readinessData: ReadinessResponse? = nil
    var streakData: StreakResponse? = nil
    var warRoomEnabled: Bool?
    var warRoomHasResult: Bool?
    var warRoomHasTemptation: Bool?
    var weeklyTonnage: Int? = nil
}

enum DashboardDayField: Sendable {
    case deload, moodDue, morningBrief, recovery, hrv, nutrition, alerts, pattern, ritual, cardio, budget
}

enum DashboardAnalyticsField: Sendable {
    case readiness, streak, tonnage, warRoomConfig, warRoomStatus, effects
}

// MARK: - DashboardSignalEngine

struct DashboardSignalEngine {
    func criticalSignal(
        dash: DashboardData,
        deload: DeloadReport?,
        readiness: ReadinessResponse?,
        streakData: StreakResponse?
    ) -> CriticalSignal? {
        if let report = deload, report.fatigueLevel == 2 {
            return CriticalSignal(
                message: "Fatigue accumulée détectée — un deload s'impose cette semaine.",
                actionLabel: "Voir le plan deload",
                destination: .deload,
                icon: "bolt.fill"
            )
        }
        if let score = readiness?.score, score < 40 {
            return CriticalSignal(
                message: "Récupération à \(score)/100 — réduis le volume de ta séance aujourd'hui.",
                actionLabel: "Voir récupération",
                destination: .recovery,
                icon: "heart.fill"
            )
        }
        // Baseline HRV unifiée (Commit 4) : zone rouge backend = signal critique.
        // Plus de recalcul iOS — seuils + sensitivity user_profile vivent côté
        // hrv_engine.py. Futurs consommateurs à migrer (backlog commit 5) :
        // RecoveryPerformanceBanner.swift:43, RecoveryView.swift:1185.
        if let hrv = readiness?.hrvStatus,
           hrv.zone == "red",
           let today = hrv.todayRmssd, let baseline = hrv.baseline7d, baseline > 0 {
            let pct = Int(((baseline - today) / baseline) * 100)
            return CriticalSignal(
                message: "HRV \(pct)% sous ta baseline — priorise la récupération aujourd'hui.",
                actionLabel: "Voir HRV",
                destination: .hrv,
                icon: "heart.fill"
            )
        }
        let low = dash.today.lowercased()
        let isRestDay = low.contains("repos") || low.contains("rest") || low.contains("recovery")
        if !isRestDay, !dash.today.isEmpty, !dash.alreadyLoggedToday {
            let streak = streakData?.currentStreak ?? 0
            if streak > 2 {
                return CriticalSignal(
                    message: "Séance prévue aujourd'hui — ton streak de \(streak) jours est en jeu.",
                    actionLabel: "Commencer la séance",
                    destination: .workout,
                    icon: "flame.fill"
                )
            }
        }
        return nil
    }

    func computeMacroHint(
        dailyPattern: PatternEntry?,
        yesterdayNutrition: NutritionDayHistory?
    ) -> MacroNutritionHint? {
        guard let pattern = dailyPattern,
              pattern.family == "C",
              let t = pattern.macroThreshold,
              let yesterday = yesterdayNutrition else { return nil }
        let v: Double
        let label: String
        switch t.macro {
        case "proteines":
            guard yesterday.proteines > 0 else { return nil }
            v = yesterday.proteines; label = "protéines"
        case "calories":
            guard yesterday.calories > 0 else { return nil }
            v = yesterday.calories; label = "calories"
        default:
            return nil
        }
        return MacroNutritionHint(isAbove: v >= t.value, macro: label, value: v, threshold: t.value, unit: t.unit)
    }
}

// MARK: - Critical Alert Types

enum DashboardAlertDestination {
    case recovery, hrv, workout, deload
}

struct CriticalSignal {
    let message: String
    let actionLabel: String
    let destination: DashboardAlertDestination
    let icon: String
}

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var deload: DeloadReport?
    @Published var moodDue: MoodDueStatus?
    @Published var morningBrief: MorningBriefData?
    @Published var todayRecovery: RecoveryEntry?
    @Published var readinessData: ReadinessResponse?
    @Published var dailyPattern: PatternEntry?
    @Published var ritualToday: RitualToday?
    @Published var warRoomEnabled = false
    @Published var warRoomHasResult = false
    @Published var warRoomHasTemptation = false
    @Published var hrvAnalysis: HRVAnalysis? = nil
    @Published var yesterdayNutrition: NutritionDayHistory?
    @Published var todayNutritionType: String?
    @Published var cardioToday: CardioEntry? = nil
    @Published var budgetStatus: BudgetStatus? = nil
    @Published var streakData: StreakResponse? = nil
    @Published var weeklyTonnage: Int? = nil
    @Published var partialLoadWarning = false
    @Published var morningBriefFailed = false

    private let logger = Logger(subsystem: "TrainingOS", category: "dashboard")
    // PERF-5: skip expensive analytics if already loaded today
    private var analyticsLoadedDate = ""
    private var publishedProgram: String?
    private var publishedDate = ""
    private var lastLoad: Date?
    private var lastVersion: Int?

    var hasCurrentDayContext: Bool {
        publishedDate == DateFormatter.isoDate.string(from: Date())
            && publishedProgram == APIService.shared.dashboardPlan?.programme.active_program_id
            && APIService.shared.dashboard?.todayDate == publishedDate
    }

    func loadIfNeeded() async {
        let api = APIService.shared
        guard !Self.canReuse(lastLoad: lastLoad, now: Date(),
                            loadedDate: api.dashboard?.todayDate,
                            sameContext: lastVersion == api.dashboardContextVersion) else { return }
        await loadAll(mode: .initial)
    }

    static func canReuse(lastLoad: Date?, now: Date, loadedDate: String?, sameContext: Bool) -> Bool {
        guard let lastLoad else { return false }
        return sameContext && loadedDate == DateFormatter.isoDate.string(from: now)
            && now.timeIntervalSince(lastLoad) >= 0 && now.timeIntervalSince(lastLoad) < 300
    }

    private let publicationPermission: ((Int, String) -> Bool)?
    private let publishMacroHint: @MainActor (MacroNutritionHint?) -> Void

    private func canPublish(_ version: Int, today: String) -> Bool {
        if let publicationPermission { return !Task.isCancelled && publicationPermission(version, today) }
        return !Task.isCancelled && APIService.shared.dashboardContextVersion == version
            && today == DateFormatter.isoDate.string(from: Date())
    }

    // D-D2: localize raw API error strings
    func localizeAPIError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("timeout") || lower.contains("timed out") { return "Connexion lente, réessaie" }
        if lower.contains("401") || lower.contains("unauthorized") { return "Session expirée, reconnecte-toi" }
        if lower.contains("network") || lower.contains("internet") { return "Pas de connexion internet" }
        return "Une erreur est survenue — réessaie"
    }

    private var sessionObserver: (any NSObjectProtocol)?

    init(publicationPermission: ((Int, String) -> Bool)? = nil,
         publishMacroHint: @escaping @MainActor (MacroNutritionHint?) -> Void = { AppState.shared.macroSessionHint = $0 }) {
        self.publicationPermission = publicationPermission
        self.publishMacroHint = publishMacroHint
        sessionObserver = NotificationCenter.default.addObserver(
            forName: .sessionCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.reloadAfterMutation() }
        }
    }

    deinit {
        if let sessionObserver { NotificationCenter.default.removeObserver(sessionObserver) }
    }

    private var refreshRunning = false
    private var refreshRequested = false

    func reloadAfterMutation() async {
        lastLoad = nil
        if refreshRunning {
            refreshRequested = true
            return
        }
        await loadAll()
    }

    func loadAll(mode: DashboardLoadMode = .refresh) async {
        guard !refreshRunning else {
            if APIService.shared.dashboard == nil { refreshRequested = true }
            return
        }
        refreshRunning = true
        defer {
            refreshRunning = false
            if refreshRequested { lastLoad = nil }
        }
        partialLoadWarning = false
        morningBriefFailed = false

        // Each Dashboard request owns its timeout and loading state. A second
        // timer must not reopen the gate or turn cancellation into an error.
        repeat {
            refreshRequested = false
            await performLoad(mode: mode)
        } while refreshRequested && !Task.isCancelled
    }

    private func performLoad(mode: DashboardLoadMode) async {
        // Phase 1: dashboard first — populates skeleton UI immediately
        guard await APIService.shared.fetchDashboard(mode: mode), !Task.isCancelled else { return }
        let contextVersion = APIService.shared.dashboardContextVersion

        // Single source of truth: dashboard.todayDate echoes the device date sent via ?date=.
        // Falls back to device date if dashboard failed to load (network + cache both failed).
        let today = APIService.shared.dashboard?.todayDate ?? DateFormatter.isoDate.string(from: Date())
        let yesterdayStr: String = {
            let base = DateFormatter.isoDate.date(from: today) ?? Date()
            return DateFormatter.isoDate.string(from: Calendar.mtl.date(byAdding: .day, value: -1, to: base) ?? base)
        }()

        let program = APIService.shared.dashboardPlan?.programme.active_program_id
        if publishedProgram != program || publishedDate != today {
            deload = nil; moodDue = nil; morningBrief = nil; todayRecovery = nil
            readinessData = nil; ritualToday = nil; hrvAnalysis = nil
            resetMacroInputs()
            todayNutritionType = nil; cardioToday = nil
            budgetStatus = nil; streakData = nil; weeklyTonnage = nil
            warRoomEnabled = false; warRoomHasResult = false; warRoomHasTemptation = false
            analyticsLoadedDate = ""
            publishedProgram = program; publishedDate = today
        }
        lastLoad = Date()
        lastVersion = contextVersion
        // Both groups belong to this load. Reports cannot hold back day summaries.
        await Self.enrich(day: {
            await self.loadDay(today: today, yesterdayStr: yesterdayStr, contextVersion: contextVersion)
        }, analytics: {
            await self.loadAnalytics(today: today, contextVersion: contextVersion)
        })
    }

    // Structured children are cancelled with their owner; either stream may publish first.
    static func enrich(day: @escaping @MainActor @Sendable () async -> Void,
                       analytics: @escaping @MainActor @Sendable () async -> Void) async {
        await withTaskGroup(of: Void.self) { phases in
            phases.addTask { await day() }
            phases.addTask { await analytics() }
        }
    }

    private func loadDay(today: String, yesterdayStr: String, contextVersion: Int) async {
        await receiveDay(today: today, contextVersion: contextVersion) { group, p2 in
            group.addTask { @MainActor in
                do { p2.deload = try await APIService.shared.fetchDeloadData(); return (.deload, 0) }
                catch { self.logger.error("fetchDeload: \(error, privacy: .public)"); return (.deload, 0) }
            }
            group.addTask { @MainActor in
                do { p2.moodDue = try await APIService.shared.checkMoodDue(); return (.moodDue, 0) }
                catch { self.logger.error("checkMoodDue: \(error, privacy: .public)"); return (.moodDue, 0) }
            }
            group.addTask { @MainActor in
                do { p2.morningBrief = try await APIService.shared.fetchMorningBrief(); return (.morningBrief, 0) }
                catch {
                    self.logger.error("fetchMorningBrief: \(error, privacy: .public)")
                    p2.morningBriefFailed = true
                    return (.morningBrief, 0)
                }
            }
            // CRITICAL: drives the readiness score displayed on the dashboard
            group.addTask { @MainActor in
                do {
                    let log = try await APIService.shared.fetchRecoveryData()
                    let entry = log.first(where: { $0.date == today })
                    p2.todayRecovery = entry
                    p2.receivedRecovery = true
                    return (.recovery, 0)
                } catch let e as URLError where e.code == .cancelled {
                    return (.recovery, 0)  // task cancelled (navigation) — not an error
                } catch {
                    self.logger.error("fetchRecovery: \(error, privacy: .public)")
                    return (.recovery, 1)
                }
            }
            group.addTask { @MainActor in
                do {
                    // sequential — async let LIFO crash on iOS 26 beta
                    p2.hrvAnalysis = try await APIService.shared.fetchHRVAnalysis()
                    return (.hrv, 0)
                } catch let e as URLError where e.code == .cancelled {
                    return (.hrv, 0)  // task cancelled (navigation) — not an error
                } catch {
                    self.logger.error("fetchHRVAnalysis: \(error, privacy: .public)")
                    return (.hrv, 0)
                }
            }
            group.addTask { @MainActor [yesterdayStr] in
                // Un seul fetch — même cache key que fetchNutritionHistory. Extrait :
                // - todayType (source unique serveur, pas de mapping client)
                // - yesterdayNutrition (existant)
                if let detail = try? await APIService.shared.fetchNutritionDetail() {
                    p2.receivedNutrition = true
                    p2.todayNutritionType = detail.todayType
                    p2.yesterdayNutrition = detail.history.first(where: { $0.date == yesterdayStr })
                }
                return (.nutrition, 0)
            }
            group.addTask { @MainActor in
                await AlertService.shared.fetch()
                return (.alerts, 0)
            }
            group.addTask { @MainActor in
                do {
                    let resp = try await APIService.shared.fetchPatterns()
                    p2.dailyPattern = resp.daily
                    p2.receivedPattern = true
                    return (.pattern, 0)
                } catch {
                    self.logger.error("fetchPatterns: \(error, privacy: .public)")
                    return (.pattern, 0)
                }
            }
            group.addTask { @MainActor in
                do {
                    let ritual = try await APIService.shared.fetchRitualToday()
                    p2.ritualToday = ritual
                    return (.ritual, 0)
                } catch {
                    self.logger.error("fetchRitualToday: \(error, privacy: .public)")
                    return (.ritual, 0)
                }
            }
            group.addTask { @MainActor in
                if let all = try? await APIService.shared.fetchCardioData() {
                    p2.cardioToday = all.first(where: { $0.date == today })
                    p2.receivedCardio = true
                }
                return (.cardio, 0)
            }
            group.addTask { @MainActor in
                p2.budgetStatus = try? await APIService.shared.fetchBudgetStatus()
                return (.budget, 0)
            }
        }
    }

    // Same production receiver, with isolated child operations available to focused tests.
    func receiveDay(today: String, contextVersion: Int,
                    addTasks: (inout TaskGroup<(DashboardDayField, Int)>, P2State) -> Void) async {
        let p2 = P2State()
        await withTaskGroup(of: (DashboardDayField, Int).self) { group in
            addTasks(&group, p2)
            for await (field, failures) in group {
                guard canPublish(contextVersion, today: today) else { group.cancelAll(); continue }
                p2.criticalFailures += failures
                // Only this child's destination may change. Pending/failed children retain
                // their previous value; a successful optional response can explicitly clear it.
                switch field {
                case .deload:
                    if let value = p2.deload { deload = value }
                case .moodDue:
                    if let value = p2.moodDue { moodDue = value }
                case .morningBrief:
                    if let value = p2.morningBrief { morningBrief = value }
                    let failed = p2.morningBriefFailed && morningBrief == nil
                    if morningBriefFailed != failed { morningBriefFailed = failed }
                case .recovery:
                    if p2.receivedRecovery { todayRecovery = p2.todayRecovery }
                case .hrv:
                    if let value = p2.hrvAnalysis { hrvAnalysis = value }
                case .nutrition:
                    if p2.receivedNutrition {
                        yesterdayNutrition = p2.yesterdayNutrition
                        todayNutritionType = p2.todayNutritionType
                        publishMacroHint(computeMacroHint())
                    }
                case .pattern:
                    if p2.receivedPattern {
                        dailyPattern = p2.dailyPattern
                        publishMacroHint(computeMacroHint())
                    }
                case .ritual:
                    if let value = p2.ritualToday { ritualToday = value }
                case .cardio:
                    if p2.receivedCardio { cardioToday = p2.cardioToday }
                case .budget:
                    if let value = p2.budgetStatus { budgetStatus = value }
                case .alerts:
                    break
                }
                let warning = p2.criticalFailures > 0
                if partialLoadWarning != warning { partialLoadWarning = warning }
            }
        }
    }

    private func loadAnalytics(today: String, contextVersion: Int) async {
        // Analytics — once per calendar day
        if analyticsLoadedDate != today {
            await receiveAnalytics(today: today, contextVersion: contextVersion) { group, p3 in
                group.addTask { @MainActor in
                    p3.readinessData = try? await APIService.shared.fetchReadiness()
                    return .readiness
                }
                group.addTask { @MainActor in
                    p3.streakData      = try? await APIService.shared.fetchStreaks(date: today)
                    return .streak
                }
                group.addTask { @MainActor in
                    p3.weeklyTonnage   = try? await APIService.shared.fetchWeeklyTonnage().volume
                    return .tonnage
                }
                group.addTask { @MainActor in
                    if let config = try? await APIService.shared.getWarRoomConfig() {
                        guard self.canPublish(contextVersion, today: today) else { return .warRoomConfig }
                        let enabled = config.warStartDate != nil
                        p3.warRoomEnabled = enabled
                        UserDefaults.standard.set(enabled, forKey: "warRoomEnabled")
                        let notificationEnabled = NotificationService.isEnabled("notif_on_war_room_checkin")
                        NotificationService.scheduleWarRoomDailyCheckin(
                            isEnabled: enabled && notificationEnabled
                        )
                    }
                    return .warRoomConfig
                }
                group.addTask { @MainActor in
                    if let ts = try? await APIService.shared.getWarRoomTodayStatus() {
                        p3.warRoomHasResult     = ts.hasResult
                        p3.warRoomHasTemptation = ts.hasTemptation
                    }
                    return .warRoomStatus
                }
                // Notification-only side effects (no @Published needed)
                group.addTask { @MainActor in
                    if let report = try? await APIService.shared.fetchWeeklyReport() {
                        guard self.canPublish(contextVersion, today: today) else { return .effects }
                        NotificationService.scheduleWeeklyRecapWithData(report: report, tracker: BehaviorTracker.shared)
                    }
                    return .effects
                }
                group.addTask { @MainActor in
                    if let s = try? await APIService.shared.getActiveSeason() {
                        guard self.canPublish(contextVersion, today: today) else { return .effects }
                        NotificationService.scheduleSeasonMilestones(seasonStartISO: s.startedAt, seasonNumber: s.number)
                    }
                    return .effects
                }
                group.addTask { @MainActor in
                    if let dna = try? await APIService.shared.fetchWorkoutDNA() {
                        guard self.canPublish(contextVersion, today: today) else { return .effects }
                        NotificationService.notifyDNAArchetypeChange(newKey: dna.archetype.key, newLabel: dna.archetype.label)
                    }
                    return .effects
                }
                group.addTask { @MainActor in
                    if let capsules = try? await APIService.shared.fetchTimeCapsules() {
                        guard self.canPublish(contextVersion, today: today) else { return .effects }
                        NotificationService.scheduleTimeCapsuleSoon(capsules: capsules)
                    }
                    return .effects
                }
            }
            guard canPublish(contextVersion, today: today) else { return }
            analyticsLoadedDate = today
        }
    }

    func receiveAnalytics(today: String, contextVersion: Int,
                          addTasks: (inout TaskGroup<DashboardAnalyticsField>, P3State) -> Void) async {
        let p3 = P3State()
        await withTaskGroup(of: DashboardAnalyticsField.self) { group in
            addTasks(&group, p3)
            for await field in group {
                guard canPublish(contextVersion, today: today) else { group.cancelAll(); continue }
                switch field {
                case .readiness:
                    if let value = p3.readinessData { readinessData = value }
                case .streak:
                    if let value = p3.streakData { streakData = value }
                case .tonnage:
                    if let value = p3.weeklyTonnage { weeklyTonnage = value }
                case .warRoomConfig:
                    if let value = p3.warRoomEnabled { warRoomEnabled = value }
                case .warRoomStatus:
                    if let value = p3.warRoomHasResult { warRoomHasResult = value }
                    if let value = p3.warRoomHasTemptation { warRoomHasTemptation = value }
                case .effects:
                    break
                }
            }
        }
    }

    func refreshMoodDue() async {
        moodDue = try? await APIService.shared.checkMoodDue()
    }

    func refreshWarRoomTodayStatus() async {
        CacheService.shared.clear(for: "war_room_today_status")
        if let ts = try? await APIService.shared.getWarRoomTodayStatus() {
            warRoomHasResult     = ts.hasResult
            warRoomHasTemptation = ts.hasTemptation
        }
    }

    func refreshRitual() async {
        CacheService.shared.clear(for: "ritual_today")
        if let updated = try? await APIService.shared.fetchRitualToday() {
            ritualToday = updated
        }
    }

    func refreshMorningBrief() async {
        morningBriefFailed = false
        do {
            morningBrief = try await APIService.shared.fetchMorningBrief()
        } catch {
            logger.error("refreshMorningBrief: \(error, privacy: .public)")
            morningBriefFailed = true
        }
    }

    // MARK: - Critical Alert System

    func criticalSignal(dash: DashboardData) -> CriticalSignal? {
        DashboardSignalEngine().criticalSignal(
            dash: dash, deload: deload, readiness: readinessData, streakData: streakData
        )
    }

    // A new day/program removes both inputs even if their next requests fail.
    func resetMacroInputs() {
        dailyPattern = nil
        yesterdayNutrition = nil
        publishMacroHint(computeMacroHint())
    }

    private func computeMacroHint() -> MacroNutritionHint? {
        DashboardSignalEngine().computeMacroHint(dailyPattern: dailyPattern, yesterdayNutrition: yesterdayNutrition)
    }
}

// MARK: - Verdict Arbiter (Commit 2)
//
// Plafonne l'affichage du verdict effort quand un CriticalSignal s'affiche.
// L'arbitre COMPARE deux flux déjà présents côté client (readiness backend
// + criticalSignal iOS), il ne recalcule rien. Le verdict backend reste
// intact dans les logs/API — seul l'affichage est plafonné.
// Règle absolue : jamais "Go hard" sous un CriticalSignal actif.

enum EffortCap: String {
    case none, moderate, rest
}

struct DashboardVerdictArbiter {
    /// Deload / readiness<40 = rest. HRV signal = moderate. Rappel séance
    /// (streak, destination .workout) ne plafonne pas — aucune contradiction
    /// physiologique, c'est un signal d'engagement, pas de risque.
    static func cap(signal: CriticalSignal?) -> EffortCap {
        guard let signal = signal else { return .none }
        switch signal.destination {
        case .deload, .recovery: return .rest
        case .hrv:               return .moderate
        case .workout:           return .none
        }
    }
}
