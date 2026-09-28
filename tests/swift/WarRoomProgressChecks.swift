import Foundation

// Compile only with WarRoomModels, WarRoomProgress and WarRoomProgressStore.
// Standalone doubles isolate all network and settings writes.
final class APIService {
    static let shared = APIService()
    func getWarRoomProgress() async throws -> WarRoomHistory { throw URLError(.notConnectedToInternet) }
}
extension DateFormatter {
    static let isoDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Montreal") ?? .current
        return f
    }()
}

@main
struct WarRoomProgressChecks {
    static let f = DateFormatter.isoDate
    static let today = f.date(from: "2026-09-28")!
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = f.timeZone; return c }
    static func battle(_ date: String, _ status: BattleStatus = .victory, updated: String = "1") -> WarRoomBattle {
        WarRoomBattle(id: date, date: date, status: status, notes: nil, createdAt: "0", updatedAt: updated)
    }
    static func history(_ battles: [WarRoomBattle], complete: Bool = true, context: String = "personal") -> WarRoomHistory {
        WarRoomHistory(battles: battles, complete: complete, startDate: "2026-01-01", context: context, throughDate: "2026-09-28")
    }
    static func project(_ rows: [WarRoomBattle], complete: Bool = true, context: String = "personal") -> WarRoomProgress {
        WarRoomProgress(history: history(rows, complete: complete, context: context), calendar: calendar, formatter: f, today: today)
    }
    static func wins(_ count: Int) -> [WarRoomBattle] {
        (0..<count).map { battle(f.string(from: calendar.date(byAdding: .day, value: -$0, to: today)!)) }
    }
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); print("PASS \(label)")
    }
    @MainActor static func main() async {
        let row = battle("2026-09-27")
        check(project([row, row]).victories == 1, "duplicate date counts once")
        check(project([row, battle(row.date, .lost, updated: "2")]).victories == 0, "correction overrides old victory")
        check(project([battle(row.date, .lost, updated: "2"), row]).victories == 0, "duplicate authority independent of response order")
        check(project([]).victories == 0, "deletion recomputes total")
        let mixed = project([battle("2026-01-02"), battle("2026-09-20", .lost), row, battle("2026-09-29")])
        check(mixed.victories == 2, "future results excluded; backfill uses business date")
        check(mixed.days.first { $0.key == "2026-09-26" }?.state == .unreported, "absent day is unreported")
        check(mixed.days.first { $0.key == "2026-09-20" }?.state == .recorded, "explicit lost is recorded")
        check(mixed.days.first { $0.key == "2026-09-28" }?.state == .ongoing, "today is ongoing")
        check(mixed.curve.first?.cumulative == 1 && mixed.curve.last?.cumulative == 2, "curve includes pre-period baseline")
        check(mixed.curve.last?.cumulative == mixed.victories, "curve agrees with total")
        check(mixed.weeks.reduce(0) { $0 + $1.victories } == mixed.calendarWeeks.flatMap { $0 }.filter { $0.state == .victory }.count, "chart projections agree for fixture")
        check(mixed.weeks.last?.partial == true, "current week marked partial")
        check(mixed.calendarWeeks.count == 12 && mixed.weeks.count == 8, "12 calendar weeks and 8 rhythm weeks")
        for (index, threshold) in WarRoomProgress.thresholds.enumerated() {
            check(project(wins(threshold)).level == index + 1, "level threshold \(threshold)")
            check(project(wins(threshold - 1)).nextThreshold == threshold, "next threshold \(threshold)")
        }
        let over = project(wins(110))
        check(over.victories == 110 && over.nextThreshold == nil && over.progressFraction == 1, "above 100 retains total")
        check(over.badges.count == 4 && over.badges.filter(\.earned).count == 3, "four badges; gaps never earn comeback")
        check(mixed.badges.first { $0.id == "return" }?.date == "2026-09-27", "comeback requires explicit lost before victory")
        check(project([row]).badges.first { $0.id == "return" }?.earned == false, "missing days are not losses")
        let partial = project(wins(40), complete: false)
        check(partial.level == nil && partial.nextThreshold == nil && !partial.badges.contains(where: \.earned), "partial history cannot claim total milestones")
        check(partial.coverage.contains("2026-08-20"), "partial coverage names oldest received date")
        let started = WarRoomHistory(battles: [row], complete: true, startDate: "2026-09-25", context: "personal", throughDate: "2026-09-28")
        let recent = WarRoomProgress(history: started, calendar: calendar, formatter: f, today: today)
        check(recent.days.first { $0.key == "2026-09-24" }?.state == .outside, "before tracking is outside, not a loss")
        check(recent.days.first { $0.key == "2026-09-29" }?.state == .outside, "future calendar day is outside")
        var gate = WarRoomVictoryFeedback()
        let before = project([]), after = project([row])
        check(gate.accept(date: row.date, before: before, after: after), "confirmed new victory celebrates")
        check(!gate.accept(date: row.date, before: before, after: after), "same operation replay does not celebrate")
        check(!gate.accept(date: row.date, before: after, after: after), "refresh and correction without increase do not celebrate")
        check(!gate.accept(date: row.date, before: before, after: project([row], context: "changed")), "old context cannot celebrate")

        var response = history([])
        var fail = false
        let store = WarRoomProgressStore(read: { if fail { throw URLError(.notConnectedToInternet) }; return response }, now: { today })
        await store.refresh()
        let previous = store.progress
        response = history([row])
        let feedback = await store.confirmedVictory(date: row.date, status: .victory, before: previous)
        check(store.progress?.victories == 1 && feedback != nil, "Dashboard confirmed save refreshes shared War Room")
        await store.refresh(force: true)
        let replay = await store.confirmedVictory(date: row.date, status: .victory, before: previous)
        check(replay == nil, "refresh cannot replay feedback")
        fail = true
        await store.refresh(force: true)
        check(store.progress?.victories == 1 && store.error != nil, "network error preserves snapshot instead of zero")
        let cancelled = WarRoomProgressStore(read: { throw CancellationError() }, now: { today })
        await cancelled.refresh()
        check(cancelled.error == nil && cancelled.progress == nil, "cancellation does not show connection failure")
        await store.configurationChanged()
        check(store.progress == nil, "changed context rejects previous snapshot even on read failure")
        var readCount = 0
        let racing = WarRoomProgressStore(read: {
            readCount += 1
            let call = readCount
            if call == 1 { try await Task.sleep(nanoseconds: 50_000_000) }
            return history(call == 1 ? wins(40) : [row], context: call == 1 ? "old" : "new")
        }, now: { today })
        let oldRequest = Task { await racing.refresh() }
        while readCount == 0 { await Task.yield() }
        await racing.refresh(force: true)
        await oldRequest.value
        check(racing.progress?.victories == 1 && racing.progress?.history.context == "new", "late response from old context is rejected")
        let active = project([battle("2026-09-20", .active), row])
        check(active.badges.first { $0.id == "return" }?.earned == false, "active row is not an explicit loss")
        for week in mixed.weeks {
            let keys = Set(week.days.map(\.key))
            check(week.victories == mixed.days.filter { keys.contains($0.key) && $0.state == .victory }.count, "weekly bar and calendar share results \(week.id)")
        }
        print("War Room focused checks complete")
    }
}

extension Calendar {
    static var mtl: Calendar {
        var c = Calendar(identifier: .iso8601); c.timeZone = DateFormatter.isoDate.timeZone; return c
    }
}
