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
    @Published var peakPrediction: PeakPredictionResponse?
    @Published var coachTip: CoachTip?

    private var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    func loadAll() async {
        await APIService.shared.fetchDashboard()
        async let d = APIService.shared.fetchDeloadData()
        async let m = APIService.shared.checkMoodDue()
        async let b = APIService.shared.fetchMorningBrief()
        async let s = APIService.shared.fetchSeanceSoirData()
        async let i = APIService.shared.fetchInsights()
        async let r = APIService.shared.fetchRecoveryData()
        async let t = APIService.shared.fetchLifeStressTrend(days: 7)
        async let p = APIService.shared.fetchPeakPrediction()
        async let c = APIService.shared.fetchDailyCoachTip()

        deload         = try? await d
        moodDue        = try? await m
        brief          = try? await b
        soirData       = try? await s
        insights       = (try? await i) ?? []
        lssTrend       = (try? await t) ?? []
        peakPrediction = try? await p
        coachTip       = try? await c
        if let log = try? await r {
            let entry = log.first(where: { $0.date == todayStr })
            todaySleepLogged = entry?.sleepHours != nil
            todayRecovery    = entry
        }
        await AlertService.shared.fetch()
    }

    func refreshMoodDue() async {
        moodDue = try? await APIService.shared.checkMoodDue()
    }
}
