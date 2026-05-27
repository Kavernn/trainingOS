import SwiftUI
import Combine
import OSLog

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var insights: [InsightEntry] = []
    @Published var deload: DeloadReport?
    @Published var moodDue: MoodDueStatus?
    @Published var morningBrief: MorningBriefData?
    @Published var eveningSession: SeanceSoirData?
    @Published var todaySleepLogged = false
    @Published var todayRecovery: RecoveryEntry?
    @Published var lssTrend: [LifeStressScore] = []
    @Published var coachTip: CoachTip?
    @Published var smartDay: SmartDayRecommendation?
    @Published var weeklyReport: WeeklyReport?
    @Published var sleepStages: SleepStages?
    @Published var sleepWindow: SleepWindow?
    @Published var bodyBudget: BodyBudgetResponse?
    @Published var readinessData: ReadinessResponse?
    @Published var phoenixScore: PhoenixScore?
    @Published var phoenixDayDelta: Double? = nil
    @Published var activeSeason: Season?
    @Published var dailyPattern: PatternEntry?
    @Published var ritualToday: RitualToday?
    @Published var warRoomEnabled = false
    @Published var hrvAnalysis: HRVAnalysis? = nil
    @Published var yesterdayNutrition: NutritionDayHistory?
    // D-D1: banner when 2+ secondary calls fail
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
        partialLoadWarning = false
        morningBriefFailed = false

        // D-B1: timeout safety net — runs concurrently, fires only if performLoad hangs
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if APIService.shared.dashboard == nil {
                APIService.shared.isLoading = false
                APIService.shared.error = "Connexion trop lente — tire vers le bas pour réessayer"
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

        // Phase 2: all independent secondary calls in parallel.
        // withTaskGroup is safe on iOS 26 beta (async let parallel has LIFO crash).
        // @MainActor in each task: properties are MainActor-isolated.
        // Network awaits still suspend and yield the actor, so fetches run concurrently.
        // Tasks return 1 only for CRITICAL calls — banner shown when criticalFailures >= 1.
        var criticalFailures = 0
        await withTaskGroup(of: Int.self) { group in
            group.addTask { @MainActor in
                do { self.deload = try await APIService.shared.fetchDeloadData(); return 0 }
                catch { self.logger.error("fetchDeload: \(error, privacy: .public)"); return 0 }
            }
            group.addTask { @MainActor in
                do { self.moodDue = try await APIService.shared.checkMoodDue(); return 0 }
                catch { self.logger.error("checkMoodDue: \(error, privacy: .public)"); return 0 }
            }
            group.addTask { @MainActor in
                do { self.morningBrief = try await APIService.shared.fetchMorningBrief(); return 0 }
                catch {
                    self.logger.error("fetchMorningBrief: \(error, privacy: .public)")
                    self.morningBriefFailed = true
                    return 0
                }
            }
            group.addTask { @MainActor in
                do { self.eveningSession = try await APIService.shared.fetchSeanceSoirData(); return 0 }
                catch { self.logger.error("fetchSeanceSoir: \(error, privacy: .public)"); return 0 }
            }
            // CRITICAL: drives the readiness score displayed on the dashboard
            group.addTask { @MainActor in
                do {
                    let log = try await APIService.shared.fetchRecoveryData()
                    let entry = log.first(where: { $0.date == today })
                    self.todaySleepLogged = entry?.sleepHours != nil
                    self.todayRecovery    = entry
                    return 0
                } catch {
                    self.logger.error("fetchRecovery: \(error, privacy: .public)")
                    return 1
                }
            }
            group.addTask { @MainActor in
                do {
                    // sequential — async let LIFO crash on iOS 26 beta
                    let analysis = try await APIService.shared.fetchHRVAnalysis()
                    self.hrvAnalysis = analysis
                    return 0
                } catch {
                    self.logger.error("fetchHRVAnalysis: \(error, privacy: .public)")
                    return 0
                }
            }
            group.addTask { @MainActor [yesterdayStr] in
                if let history = try? await APIService.shared.fetchNutritionHistory() {
                    self.yesterdayNutrition = history.first(where: { $0.date == yesterdayStr })
                }
                return 0
            }
            group.addTask { @MainActor in
                self.sleepStages = await HealthKitService.shared.fetchLastNightSleepStages()
                return 0
            }
            group.addTask { @MainActor in
                self.sleepWindow = await HealthKitService.shared.fetchLastNightSleepWindow()
                return 0
            }
            group.addTask { @MainActor in
                await AlertService.shared.fetch()
                return 0
            }
            group.addTask { @MainActor in
                do {
                    let score = try await APIService.shared.fetchPhoenixScore()
                    self.phoenixScore = score
                    // Day-over-day delta: rotate stored score once per calendar day
                    let storedDate  = UserDefaults.standard.string(forKey: "phoenix.score.date") ?? ""
                    if storedDate != today {
                        let oldValue = UserDefaults.standard.double(forKey: "phoenix.score.value")
                        let oldDate  = UserDefaults.standard.string(forKey: "phoenix.score.date") ?? ""
                        if !oldDate.isEmpty {
                            UserDefaults.standard.set(oldValue, forKey: "phoenix.score.prev_value")
                            UserDefaults.standard.set(oldDate,  forKey: "phoenix.score.prev_date")
                        }
                        UserDefaults.standard.set(Double(score.score), forKey: "phoenix.score.value")
                        UserDefaults.standard.set(today, forKey: "phoenix.score.date")
                    }
                    let prevDate = UserDefaults.standard.string(forKey: "phoenix.score.prev_date") ?? ""
                    if !prevDate.isEmpty {
                        let prevValue = UserDefaults.standard.double(forKey: "phoenix.score.prev_value")
                        self.phoenixDayDelta = Double(score.score) - prevValue
                    }
                    NotificationService.notifyPhoenixStateChange(
                        newState: score.state,
                        newLabel: score.phoenixState.label
                    )
                    return 0
                } catch {
                    self.logger.error("fetchPhoenixScore: \(error, privacy: .public)")
                    return 0
                }
            }
            group.addTask { @MainActor in
                do {
                    let resp = try await APIService.shared.fetchPatterns()
                    self.dailyPattern = resp.daily
                    return 0
                } catch {
                    self.logger.error("fetchPatterns: \(error, privacy: .public)")
                    return 0
                }
            }
            group.addTask { @MainActor in
                do {
                    self.ritualToday = try await APIService.shared.fetchRitualToday()
                    AppState.shared.ritualTodayNotDone = !(self.ritualToday?.morningDone ?? true)
                    // B4: schedule demon haunting notification if chronic pattern detected
                    if let demons = self.ritualToday?.demons {
                        NotificationService.scheduleRitualDemonHaunting(demons: demons)
                    }
                    return 0
                } catch {
                    self.logger.error("fetchRitualToday: \(error, privacy: .public)")
                    return 0
                }
            }
            group.addTask { @MainActor in
                self.bodyBudget = try? await APIService.shared.fetchBodyBudget()
                return 0
            }
            for await failures in group { criticalFailures += failures }
        }

        if criticalFailures >= 1 { partialLoadWarning = true }

        // Propagate macro nutrition hint to session coaching view
        AppState.shared.macroSessionHint = computeMacroHint()

        // Analytics — once per calendar day
        if analyticsLoadedDate != today {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in self.insights     = (try? await APIService.shared.fetchInsights()) ?? [] }
                group.addTask { @MainActor in self.lssTrend     = (try? await APIService.shared.fetchLifeStressTrend(days: 7)) ?? [] }
                group.addTask { @MainActor in self.coachTip     = try? await APIService.shared.fetchDailyCoachTip() }
                group.addTask { @MainActor in self.smartDay     = try? await APIService.shared.fetchSmartDay() }
                group.addTask { @MainActor in
                    if let report = try? await APIService.shared.fetchWeeklyReport() {
                        self.weeklyReport = report
                        NotificationService.scheduleWeeklyRecapWithData(report: report, tracker: BehaviorTracker.shared)
                    }
                }
                group.addTask { @MainActor in self.readinessData = try? await APIService.shared.fetchReadiness() }
                group.addTask { @MainActor in
                    let season = try? await APIService.shared.getActiveSeason()
                    self.activeSeason = season
                    if let s = season {
                        NotificationService.scheduleSeasonMilestones(
                            seasonStartISO: s.startedAt,
                            seasonNumber: s.number
                        )
                    }
                }
                group.addTask { @MainActor in
                    if let config = try? await APIService.shared.getWarRoomConfig() {
                        let enabled = config.warStartDate != nil
                        self.warRoomEnabled = enabled
                        UserDefaults.standard.set(enabled, forKey: "warRoomEnabled")
                        NotificationService.scheduleWarRoomDailyCheckin(isEnabled: enabled)
                    }
                }
                group.addTask { @MainActor in
                    if let graveyard = try? await APIService.shared.fetchGraveyard(),
                       let latest = graveyard.tombstones.first {
                        NotificationService.notifyNewTombstone(
                            totalCount: graveyard.totalCount,
                            latestTombstone: latest
                        )
                    }
                }
                group.addTask { @MainActor in
                    if let dna = try? await APIService.shared.fetchWorkoutDNA() {
                        NotificationService.notifyDNAArchetypeChange(
                            newKey: dna.archetype.key,
                            newLabel: dna.archetype.label
                        )
                    }
                }
                group.addTask { @MainActor in
                    if let capsules = try? await APIService.shared.fetchTimeCapsules() {
                        NotificationService.scheduleTimeCapsuleSoon(capsules: capsules)
                    }
                }
            }
            analyticsLoadedDate = today
        }
    }

    func refreshMoodDue() async {
        moodDue = try? await APIService.shared.checkMoodDue()
    }

    func refreshRitual() async {
        CacheService.shared.clear(for: "ritual_today")
        if let updated = try? await APIService.shared.fetchRitualToday() {
            ritualToday = updated
            AppState.shared.ritualTodayNotDone = !updated.morningDone
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

    // D-B1: Whether readiness score comes from local computation (fallback)
    // Used by D-D14 to show "Calculé localement" indicator
    var readinessIsLocal: Bool {
        guard let s = smartDay?.recoveryScore, s > 0 else { return true }
        return false
    }

    // Readiness score 0–100. Uses server value when available, falls back to local computation.
    var readinessScore: Int? {
        if let s = smartDay?.recoveryScore, s > 0 {
            // Server returns 0–10 scale
            return min(100, Int((s / 10.0) * 100))
        }
        guard let rec = todayRecovery else { return nil }
        var weighted = 0.0
        var totalW   = 0.0
        if let hrv = rec.hrv {
            weighted += min(1, max(0, (hrv - 15) / 65)) * 0.30
            totalW   += 0.30
        }
        if let sleep = rec.sleepHours {
            let n: Double = sleep >= 7 && sleep <= 9 ? 1 : sleep < 7 ? max(0, sleep / 7) : max(0, 1 - (sleep - 9) / 3)
            weighted += n * 0.35
            totalW   += 0.35
        }
        if let rhr = rec.restingHr {
            weighted += min(1, max(0, (80 - rhr) / 35)) * 0.25
            totalW   += 0.25
        }
        if let soreness = rec.soreness {
            weighted += max(0, 1 - soreness / 5) * 0.10
            totalW   += 0.10
        }
        guard totalW >= 0.25 else { return nil }
        return Int((weighted / totalW) * 100)
    }

    private func computeMacroHint() -> MacroNutritionHint? {
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
