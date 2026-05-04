import SwiftUI
import Combine

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

    // PERF-5: skip expensive analytics if already loaded today
    private var analyticsLoadedDate = ""
    private var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    func loadAll() async {
        let today = todayStr
        // PERF-2: fetchDashboard runs in parallel with the other calls
        async let dash: Void = APIService.shared.fetchDashboard()
        async let d = APIService.shared.fetchDeloadData()
        async let m = APIService.shared.checkMoodDue()
        async let b = APIService.shared.fetchMorningBrief()
        async let s = APIService.shared.fetchSeanceSoirData()
        async let r = APIService.shared.fetchRecoveryData()

        // PERF-5: insights / LSS / coach tip — once per day only
        if analyticsLoadedDate != today {
            async let i = APIService.shared.fetchInsights()
            async let t = APIService.shared.fetchLifeStressTrend(days: 7)
            async let c = APIService.shared.fetchDailyCoachTip()
            async let sd = APIService.shared.fetchSmartDay()
            async let wr = APIService.shared.fetchWeeklyReport()
            // Collect all results before assigning — batches into one SwiftUI render pass
            let iResult  = (try? await i) ?? []
            let tResult  = (try? await t) ?? []
            let cResult  = try? await c
            let sdResult = try? await sd
            let wrResult = try? await wr
            insights     = iResult
            lssTrend     = tResult
            coachTip     = cResult
            smartDay     = sdResult
            weeklyReport = wrResult
            analyticsLoadedDate = today
        }

        do { _ = try await dash        } catch { print("[Dashboard] fetchDashboard: \(error)") }
        do { deload   = try await d   } catch { print("[Dashboard] fetchDeload: \(error)") }
        do { moodDue  = try await m   } catch { print("[Dashboard] checkMoodDue: \(error)") }
        do { morningBrief   = try await b } catch { print("[Dashboard] fetchMorningBrief: \(error)") }
        do { eveningSession = try await s } catch { print("[Dashboard] fetchSeanceSoir: \(error)") }
        do {
            let log = try await r
            let entry = log.first(where: { $0.date == today })
            todaySleepLogged = entry?.sleepHours != nil
            todayRecovery    = entry
        } catch { print("[Dashboard] fetchRecovery: \(error)") }
        async let stages = HealthKitService.shared.fetchLastNightSleepStages()
        async let window = HealthKitService.shared.fetchLastNightSleepWindow()
        sleepStages  = await stages
        sleepWindow  = await window
        await AlertService.shared.fetch()
    }

    func refreshMoodDue() async {
        moodDue = try? await APIService.shared.checkMoodDue()
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
