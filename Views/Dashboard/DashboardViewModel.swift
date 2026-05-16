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

    init() {
        NotificationCenter.default.addObserver(
            forName: .sessionCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.loadAll() }
        }
    }

    func loadAll() async {
        let today = todayStr
        partialLoadWarning = false

        // D-B1: wrap full load in a 15-second timeout
        // We race the actual work against a timeout sentinel
        let workFinished = ActorFlag()
        let loadTask = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(today: today)
            await workFinished.set()
        }

        try? await Task.sleep(nanoseconds: 15_000_000_000)
        let didFinish = await workFinished.value
        if !didFinish {
            loadTask.cancel()
            // Only surface timeout error if dashboard still hasn't loaded
            if APIService.shared.dashboard == nil {
                APIService.shared.isLoading = false
                APIService.shared.error = "Connexion trop lente — tire vers le bas pour réessayer"
            }
        }
    }

    private func performLoad(today: String) async {
        // sequential — async let LIFO crash on iOS 26 beta
        do { _ = try await APIService.shared.fetchDashboard() } catch { logger.error("fetchDashboard: \(error, privacy: .public)") }

        // D-D1: count secondary call failures
        var secondaryFailures = 0

        do { deload = try await APIService.shared.fetchDeloadData() } catch {
            logger.error("fetchDeload: \(error, privacy: .public)")
            secondaryFailures += 1
        }
        do { moodDue = try await APIService.shared.checkMoodDue() } catch {
            logger.error("checkMoodDue: \(error, privacy: .public)")
            secondaryFailures += 1
        }
        do { morningBrief = try await APIService.shared.fetchMorningBrief() } catch {
            logger.error("fetchMorningBrief: \(error, privacy: .public)")
            secondaryFailures += 1
        }
        do { eveningSession = try await APIService.shared.fetchSeanceSoirData() } catch {
            logger.error("fetchSeanceSoir: \(error, privacy: .public)")
            secondaryFailures += 1
        }
        do {
            let log = try await APIService.shared.fetchRecoveryData()
            let entry = log.first(where: { $0.date == today })
            todaySleepLogged = entry?.sleepHours != nil
            todayRecovery    = entry
        } catch {
            logger.error("fetchRecovery: \(error, privacy: .public)")
            secondaryFailures += 1
        }

        // D-D1: warn if 2+ secondary calls failed
        if secondaryFailures >= 2 {
            partialLoadWarning = true
        }

        // PERF-5: insights / LSS / coach tip — once per day only
        if analyticsLoadedDate != today {
            // Collect all results before assigning — batches into one SwiftUI render pass
            let iResult  = (try? await APIService.shared.fetchInsights()) ?? []
            let tResult  = (try? await APIService.shared.fetchLifeStressTrend(days: 7)) ?? []
            let cResult  = try? await APIService.shared.fetchDailyCoachTip()
            let sdResult = try? await APIService.shared.fetchSmartDay()
            let wrResult = try? await APIService.shared.fetchWeeklyReport()
            insights     = iResult
            lssTrend     = tResult
            coachTip     = cResult
            smartDay     = sdResult
            weeklyReport = wrResult
            analyticsLoadedDate = today
        }

        sleepStages  = await HealthKitService.shared.fetchLastNightSleepStages()
        sleepWindow  = await HealthKitService.shared.fetchLastNightSleepWindow()
        await AlertService.shared.fetch()
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

// D-B1: Simple actor flag for racing load vs timeout
private actor ActorFlag {
    private(set) var value = false
    func set() { value = true }
}
