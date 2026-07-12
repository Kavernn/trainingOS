import SwiftUI
import Combine
import OSLog

// MARK: - Phase accumulators (no @Published → no re-renders during task group)

private final class P2State: @unchecked Sendable {
    var deload: DeloadReport? = nil
    var moodDue: MoodDueStatus? = nil
    var morningBrief: MorningBriefData? = nil
    var morningBriefFailed = false
    var todayRecovery: RecoveryEntry? = nil
    var hrvAnalysis: HRVAnalysis? = nil
    var yesterdayNutrition: NutritionDayHistory? = nil
    var dailyPattern: PatternEntry? = nil
    var ritualToday: RitualToday? = nil
    var cardioToday: CardioEntry? = nil
    var budgetStatus: BudgetStatus? = nil
    var criticalFailures = 0
}

private final class P3State: @unchecked Sendable {
    var readinessData: ReadinessResponse? = nil
    var streakData: StreakResponse? = nil
    var warRoomEnabled = false
    var warRoomHasResult = false
    var warRoomHasTemptation = false
    var weeklyTonnage: Int? = nil
}

// MARK: - DashboardSignalEngine

struct DashboardSignalEngine {
    func criticalSignal(
        dash: DashboardData,
        deload: DeloadReport?,
        readinessScore: Int?,
        hrvAnalysis: HRVAnalysis?,
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
        if let score = readinessScore, score < 40 {
            return CriticalSignal(
                message: "Récupération à \(score)/100 — réduis le volume de ta séance aujourd'hui.",
                actionLabel: "Voir récupération",
                destination: .recovery,
                icon: "heart.fill"
            )
        }
        if let analysis = hrvAnalysis,
           let rmssd = analysis.todayRmssd,
           let baseline = analysis.hrv30dAvg,
           baseline > 0, rmssd < baseline * 0.80 {
            let pct = Int(((baseline - rmssd) / baseline) * 100)
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
    @Published var cardioToday: CardioEntry? = nil
    @Published var budgetStatus: BudgetStatus? = nil
    @Published var streakData: StreakResponse? = nil
    @Published var weeklyTonnage: Int? = nil
    @Published var partialLoadWarning = false
    @Published var morningBriefFailed = false

    private let logger = Logger(subsystem: "TrainingOS", category: "dashboard")
    // PERF-5: skip expensive analytics if already loaded today
    private var analyticsLoadedDate = ""

    // D-D2: localize raw API error strings
    func localizeAPIError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("timeout") || lower.contains("timed out") { return "Connexion lente, réessaie" }
        if lower.contains("401") || lower.contains("unauthorized") { return "Session expirée, reconnecte-toi" }
        if lower.contains("network") || lower.contains("internet") { return "Pas de connexion internet" }
        return "Une erreur est survenue — réessaie"
    }

    private var sessionObserver: (any NSObjectProtocol)?

    init() {
        sessionObserver = NotificationCenter.default.addObserver(
            forName: .sessionCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.loadAll() }
        }
    }

    deinit {
        if let sessionObserver { NotificationCenter.default.removeObserver(sessionObserver) }
    }

    func loadAll() async {
        guard !APILoadingState.shared.isLoading else { return }
        partialLoadWarning = false
        morningBriefFailed = false

        // D-B1: timeout safety net — runs concurrently, fires only if performLoad hangs
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if APIService.shared.dashboard == nil {
                APILoadingState.shared.isLoading = false
                APILoadingState.shared.error = "Connexion trop lente — tire vers le bas pour réessayer"
            }
        }

        await performLoad()
        timeoutTask.cancel()
    }

    private func performLoad() async {
        // Phase 1: dashboard first — populates skeleton UI immediately
        do { _ = try await APIService.shared.fetchDashboard() }
        catch { logger.error("fetchDashboard: \(error, privacy: .public)") }

        // Single source of truth: dashboard.todayDate echoes the device date sent via ?date=.
        // Falls back to device date if dashboard failed to load (network + cache both failed).
        let today = APIService.shared.dashboard?.todayDate ?? DateFormatter.isoDate.string(from: Date())
        let yesterdayStr: String = {
            let base = DateFormatter.isoDate.date(from: today) ?? Date()
            return DateFormatter.isoDate.string(from: Calendar.current.date(byAdding: .day, value: -1, to: base) ?? base)
        }()

        // Phase 2: accumulate into P2State (no @Published → no re-renders while tasks run).
        // withTaskGroup is safe on iOS 26 beta (async let parallel has LIFO crash).
        // After the group all assignments happen synchronously → SwiftUI coalesces into 1 render.
        let p2 = P2State()
        await withTaskGroup(of: Int.self) { group in
            group.addTask { @MainActor in
                do { p2.deload = try await APIService.shared.fetchDeloadData(); return 0 }
                catch { self.logger.error("fetchDeload: \(error, privacy: .public)"); return 0 }
            }
            group.addTask { @MainActor in
                do { p2.moodDue = try await APIService.shared.checkMoodDue(); return 0 }
                catch { self.logger.error("checkMoodDue: \(error, privacy: .public)"); return 0 }
            }
            group.addTask { @MainActor in
                do { p2.morningBrief = try await APIService.shared.fetchMorningBrief(); return 0 }
                catch {
                    self.logger.error("fetchMorningBrief: \(error, privacy: .public)")
                    p2.morningBriefFailed = true
                    return 0
                }
            }
            // CRITICAL: drives the readiness score displayed on the dashboard
            group.addTask { @MainActor in
                do {
                    let log = try await APIService.shared.fetchRecoveryData()
                    let entry = log.first(where: { $0.date == today })
                    p2.todayRecovery = entry
                    return 0
                } catch {
                    self.logger.error("fetchRecovery: \(error, privacy: .public)")
                    return 1
                }
            }
            group.addTask { @MainActor in
                do {
                    // sequential — async let LIFO crash on iOS 26 beta
                    p2.hrvAnalysis = try await APIService.shared.fetchHRVAnalysis()
                    return 0
                } catch let e as URLError where e.code == .cancelled {
                    return 0  // task cancelled (navigation) — not an error
                } catch {
                    self.logger.error("fetchHRVAnalysis: \(error, privacy: .public)")
                    return 0
                }
            }
            group.addTask { @MainActor [yesterdayStr] in
                if let history = try? await APIService.shared.fetchNutritionHistory() {
                    p2.yesterdayNutrition = history.first(where: { $0.date == yesterdayStr })
                }
                return 0
            }
            group.addTask { @MainActor in
                await AlertService.shared.fetch()
                return 0
            }
            group.addTask { @MainActor in
                do {
                    let resp = try await APIService.shared.fetchPatterns()
                    p2.dailyPattern = resp.daily
                    return 0
                } catch {
                    self.logger.error("fetchPatterns: \(error, privacy: .public)")
                    return 0
                }
            }
            group.addTask { @MainActor in
                do {
                    let ritual = try await APIService.shared.fetchRitualToday()
                    p2.ritualToday = ritual
                    return 0
                } catch {
                    self.logger.error("fetchRitualToday: \(error, privacy: .public)")
                    return 0
                }
            }
            group.addTask { @MainActor in
                let all = (try? await APIService.shared.fetchCardioData()) ?? []
                p2.cardioToday = all.first(where: { $0.date == today })
                return 0
            }
            group.addTask { @MainActor in
                p2.budgetStatus = try? await APIService.shared.fetchBudgetStatus()
                return 0
            }
            for await failures in group { p2.criticalFailures += failures }
        }

        // Phase 2 batch-publish — all synchronous, coalesced by SwiftUI into 1 re-render
        deload             = p2.deload
        moodDue            = p2.moodDue
        morningBrief       = p2.morningBrief
        morningBriefFailed = p2.morningBriefFailed
        todayRecovery      = p2.todayRecovery
        hrvAnalysis        = p2.hrvAnalysis
        yesterdayNutrition = p2.yesterdayNutrition
        dailyPattern       = p2.dailyPattern
        ritualToday        = p2.ritualToday
        cardioToday        = p2.cardioToday
        budgetStatus       = p2.budgetStatus
        if p2.criticalFailures >= 1 { partialLoadWarning = true }

        // Propagate macro nutrition hint to session coaching view
        AppState.shared.macroSessionHint = computeMacroHint()

        // Analytics — once per calendar day
        if analyticsLoadedDate != today {
            let p3 = P3State()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in p3.readinessData = try? await APIService.shared.fetchReadiness() }
                group.addTask { @MainActor in p3.streakData      = try? await APIService.shared.fetchStreaks(date: today) }
                group.addTask { @MainActor in p3.weeklyTonnage   = try? await APIService.shared.fetchWeeklyTonnage().volume }
                group.addTask { @MainActor in
                    if let config = try? await APIService.shared.getWarRoomConfig() {
                        let enabled = config.warStartDate != nil
                        p3.warRoomEnabled = enabled
                        UserDefaults.standard.set(enabled, forKey: "warRoomEnabled")
                        NotificationService.scheduleWarRoomDailyCheckin(isEnabled: enabled)
                    }
                }
                group.addTask { @MainActor in
                    if let ts = try? await APIService.shared.getWarRoomTodayStatus() {
                        p3.warRoomHasResult     = ts.hasResult
                        p3.warRoomHasTemptation = ts.hasTemptation
                    }
                }
                // Notification-only side effects (no @Published needed)
                group.addTask { @MainActor in
                    if let report = try? await APIService.shared.fetchWeeklyReport() {
                        NotificationService.scheduleWeeklyRecapWithData(report: report, tracker: BehaviorTracker.shared)
                    }
                }
                group.addTask { @MainActor in
                    if let s = try? await APIService.shared.getActiveSeason() {
                        NotificationService.scheduleSeasonMilestones(seasonStartISO: s.startedAt, seasonNumber: s.number)
                    }
                }
                group.addTask { @MainActor in
                    if let dna = try? await APIService.shared.fetchWorkoutDNA() {
                        NotificationService.notifyDNAArchetypeChange(newKey: dna.archetype.key, newLabel: dna.archetype.label)
                    }
                }
                group.addTask { @MainActor in
                    if let capsules = try? await APIService.shared.fetchTimeCapsules() {
                        NotificationService.scheduleTimeCapsuleSoon(capsules: capsules)
                    }
                }
            }
            // Phase 3 batch-publish — coalesced by SwiftUI into 1 re-render
            readinessData        = p3.readinessData
            streakData           = p3.streakData
            weeklyTonnage        = p3.weeklyTonnage
            warRoomEnabled       = p3.warRoomEnabled
            warRoomHasResult     = p3.warRoomHasResult
            warRoomHasTemptation = p3.warRoomHasTemptation
            analyticsLoadedDate  = today
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

    var readinessScore: Int? { readinessData?.score }

    // MARK: - Critical Alert System

    func criticalSignal(dash: DashboardData) -> CriticalSignal? {
        DashboardSignalEngine().criticalSignal(
            dash: dash, deload: deload, readinessScore: readinessScore,
            hrvAnalysis: hrvAnalysis, streakData: streakData
        )
    }

    private func computeMacroHint() -> MacroNutritionHint? {
        DashboardSignalEngine().computeMacroHint(dailyPattern: dailyPattern, yesterdayNutrition: yesterdayNutrition)
    }
}
