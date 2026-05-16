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
    // D-D1: banner when 2+ secondary calls fail
    @Published var partialLoadWarning = false

    private let logger = Logger(subsystem: "TrainingOS", category: "dashboard")
    // PERF-5: skip expensive analytics if already loaded today
    private var analyticsLoadedDate = ""
    private var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

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
        let today = todayStr
        partialLoadWarning = false

        // D-B1: timeout safety net — runs concurrently, fires only if performLoad hangs
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if APIService.shared.dashboard == nil {
                APIService.shared.isLoading = false
                APIService.shared.error = "Connexion trop lente — tire vers le bas pour réessayer"
            }
        }

        await performLoad(today: today)
        timeoutTask.cancel()
    }

    private func performLoad(today: String) async {
        // Phase 1: dashboard first — populates skeleton UI immediately
        do { _ = try await APIService.shared.fetchDashboard() }
        catch { logger.error("fetchDashboard: \(error, privacy: .public)") }

        // Phase 2: all independent secondary calls in parallel.
        // withTaskGroup is safe on iOS 26 beta (async let parallel has LIFO crash).
        // @MainActor in each task: properties are MainActor-isolated.
        // Network awaits still suspend and yield the actor, so fetches run concurrently.
        var secondaryFailures = 0
        await withTaskGroup(of: Int.self) { group in
            group.addTask { @MainActor in
                do { self.deload = try await APIService.shared.fetchDeloadData(); return 0 }
                catch { self.logger.error("fetchDeload: \(error, privacy: .public)"); return 1 }
            }
            group.addTask { @MainActor in
                do { self.moodDue = try await APIService.shared.checkMoodDue(); return 0 }
                catch { self.logger.error("checkMoodDue: \(error, privacy: .public)"); return 1 }
            }
            group.addTask { @MainActor in
                do { self.morningBrief = try await APIService.shared.fetchMorningBrief(); return 0 }
                catch { self.logger.error("fetchMorningBrief: \(error, privacy: .public)"); return 1 }
            }
            group.addTask { @MainActor in
                do { self.eveningSession = try await APIService.shared.fetchSeanceSoirData(); return 0 }
                catch { self.logger.error("fetchSeanceSoir: \(error, privacy: .public)"); return 1 }
            }
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
            for await failures in group { secondaryFailures += failures }
        }

        if secondaryFailures >= 2 { partialLoadWarning = true }

        // Analytics — once per calendar day
        if analyticsLoadedDate != today {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in self.insights  = (try? await APIService.shared.fetchInsights()) ?? [] }
                group.addTask { @MainActor in self.lssTrend  = (try? await APIService.shared.fetchLifeStressTrend(days: 7)) ?? [] }
                group.addTask { @MainActor in self.coachTip  = try? await APIService.shared.fetchDailyCoachTip() }
                group.addTask { @MainActor in self.smartDay  = try? await APIService.shared.fetchSmartDay() }
                group.addTask { @MainActor in self.weeklyReport = try? await APIService.shared.fetchWeeklyReport() }
            }
            analyticsLoadedDate = today
        }
    }

    func refreshMoodDue() async {
        moodDue = try? await APIService.shared.checkMoodDue()
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
}
