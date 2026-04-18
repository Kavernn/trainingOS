import SwiftUI
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var insights: [InsightEntry] = []
    @Published var deload: DeloadReport?
    @Published var moodDue: MoodDueStatus?
    @Published var brief: MorningBriefData?
    @Published var soirData: SeanceSoirData?
    @Published var todaySleepLogged = false
    @Published var todayRecovery: RecoveryEntry?
    @Published var lssTrend: [LifeStressScore] = []
    @Published var coachTip: CoachTip?

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
            insights = (try? await i) ?? []
            lssTrend = (try? await t) ?? []
            coachTip = try? await c
            analyticsLoadedDate = today
        }

        _ = try? await dash
        deload   = try? await d
        moodDue  = try? await m
        brief    = try? await b
        soirData = try? await s
        if let log = try? await r {
            let entry = log.first(where: { $0.date == today })
            todaySleepLogged = entry?.sleepHours != nil
            todayRecovery    = entry
        }
        await AlertService.shared.fetch()
    }

    func refreshMoodDue() async {
        moodDue = try? await APIService.shared.checkMoodDue()
    }
}
