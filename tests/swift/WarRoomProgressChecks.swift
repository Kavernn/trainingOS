import Foundation

// Compile only with WarRoomModels, WarRoomProgress and WarRoomProgressStore.
// Standalone doubles isolate all network and settings writes.
final class APIService {
    static let shared = APIService()
    static let warRoomContextIdentity = "isolated-fixture"
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
        var releaseOld: CheckedContinuation<WarRoomHistory, Error>?
        let racing = WarRoomProgressStore(read: {
            readCount += 1
            if readCount == 1 { return history(wins(40), context: "old") }
            if readCount == 2 { return try await withCheckedThrowingContinuation { releaseOld = $0 } }
            return history([row], context: "new")
        }, now: { today })
        await racing.refresh()
        let oldRequest = Task { await racing.refresh(force: true) }
        while releaseOld == nil { await Task.yield() }
        let changed = Task { await racing.configurationChanged() }
        // Wait until the explicit context invalidation has happened, without a timer.
        while racing.progress != nil { await Task.yield() }
        releaseOld?.resume(returning: history(wins(40), context: "old"))
        await changed.value
        await oldRequest.value
        check(racing.progress?.victories == 1 && racing.progress?.history.context == "new", "late response from old context is rejected")
        let active = project([battle("2026-09-20", .active), row])
        check(active.badges.first { $0.id == "return" }?.earned == false, "active row is not an explicit loss")
        for week in mixed.weeks {
            let keys = Set(week.days.map(\.key))
            check(week.victories == mixed.days.filter { keys.contains($0.key) && $0.state == .victory }.count, "weekly bar and calendar share results \(week.id)")
        }
        await freshnessChecks()
        print("War Room focused checks complete")
    }
}

extension Calendar {
    static var mtl: Calendar {
        var c = Calendar(identifier: .iso8601); c.timeZone = DateFormatter.isoDate.timeZone; return c
    }
}

extension WarRoomProgressChecks {
    @MainActor static func freshnessChecks() async {
        var clock = today
        var reads = 0
        var response = history([])
        var failure: Error?
        let store = WarRoomProgressStore(read: {
            reads += 1
            if let failure { throw failure }
            return response
        }, now: { clock }, contextIdentity: { "A" })
        for _ in 0..<4 { await store.refresh() }
        check(reads == 1 && store.progress?.complete == true, "first opening + three nearby returns use one read")
        print("AFTER A first+3returns requests=\(reads)")
        var count = reads
        clock = clock.addingTimeInterval(61)
        await store.refresh()
        check(reads == count + 1, "expired automatic opening reads again")
        print("AFTER B expired requests=\(reads-count)")
        count = reads
        await store.refresh(force: true)
        check(reads == count + 1, "manual refresh bypasses fresh age")
        print("AFTER C manual requests=\(reads-count)")
        count = reads
        let before = store.progress
        store.invalidate() // Confirmed API mutation; a queued/failed API write does not call this.
        response = history([battle("2026-09-28")])
        let message = await store.confirmedVictory(date: "2026-09-28", status: .victory, before: before)
        await store.refresh()
        check(reads == count + 1 && message != nil && store.progress?.victories == 1, "confirmed victory invalidates immediately and return reuses result")
        print("AFTER D accepted+return requests=\(reads-count)")
        store.invalidate()
        response = history([battle("2026-09-28", .lost)])
        await store.refresh()
        check(store.progress?.victories == 0, "correction invalidates fresh history")
        store.invalidate()
        response = history([battle("2026-01-03")])
        await store.refresh()
        check(store.progress?.victories == 1 && store.progress?.history.battles.first?.date == "2026-01-03", "backfill keeps its real business date")
        store.invalidate()
        response = history([])
        await store.refresh()
        check(store.progress?.victories == 0, "a confirmed deletion would reload rather than reuse")

        response = history(wins(7))
        await store.refresh(force: true)
        failure = URLError(.notConnectedToInternet)
        await store.refresh(force: true)
        check(store.progress?.victories == 7 && store.error != nil, "failed refresh preserves complete snapshot")
        count = reads
        failure = nil
        await store.refresh()
        check(reads == count + 1 && store.error == nil, "failure does not advance freshness")
        failure = CancellationError()
        await store.refresh(force: true)
        check(store.progress?.victories == 7 && store.error == nil, "transport cancellation is silent and non-destructive")
        count = reads
        failure = nil
        await store.refresh()
        check(reads == count + 1, "transport cancellation does not renew freshness")
        response = history([battle("2026-09-28")], complete: false)
        await store.refresh(force: true)
        check(store.progress?.complete == true && store.progress?.victories == 7 && store.error != nil, "partial read cannot silently downgrade complete history")
        count = reads
        await store.refresh()
        check(reads == count + 1, "coverage failure is not treated as fresh")
        var partialReads = 0
        let partial = WarRoomProgressStore(read: { partialReads += 1; return history(wins(40), complete: false) }, now: { today })
        await partial.refresh()
        check(partial.progress?.level == nil && partial.progress?.complete == false && partial.progress?.badges.contains(where: \.earned) == false, "first partial response has no total level or earned badge")
        await partial.refresh()
        check(partialReads == 2, "partial coverage cannot enter complete-history freshness")

        var scope = "A"
        var scopedReads = 0
        var oldReply: CheckedContinuation<WarRoomHistory, Error>?
        let scoped = WarRoomProgressStore(read: {
            scopedReads += 1
            if scopedReads == 2 { return try await withCheckedThrowingContinuation { oldReply = $0 } }
            return history(scopedReads == 1 ? wins(7) : [])
        }, now: { today }, contextIdentity: { scope })
        await scoped.refresh()
        let old = Task { await scoped.refresh(force: true) }
        while oldReply == nil { await Task.yield() }
        scope = "B"
        check(scoped.progress == nil, "old account snapshot hidden before new read")
        await scoped.refresh()
        oldReply?.resume(returning: history(wins(40)))
        await old.value
        check(scoped.progress?.victories == 0 && scopedReads == 3, "old account late response cannot replace current history")

        var dateReads = 0
        clock = f.date(from: "2026-09-27")!.addingTimeInterval(86390)
        let dated = WarRoomProgressStore(read: {
            dateReads += 1
            return WarRoomHistory(battles: [battle("2026-09-27")], complete: true, startDate: "2026-01-01", context: "fixture", throughDate: "2026-09-27")
        }, now: { clock })
        await dated.refresh()
        let previousWeek = dated.progress?.weeks.last?.date
        clock = clock.addingTimeInterval(20)
        await dated.refresh()
        check(dateReads == 1 && dated.progress?.today == "2026-09-28" && dated.progress?.weeks.last?.date != previousWeek, "fresh history reprojects new business day and week without download")
        check(dated.progress?.curve.last?.isToday == true && dated.progress?.days.first(where: { $0.key == "2026-09-28" })?.state == .ongoing, "reprojected today stays unknown rather than lost")

        await concurrentChecks()
        await receptionClockChecks()
    }

    @MainActor static func concurrentChecks() async {
        var reads = 0
        var gates: [CheckedContinuation<WarRoomHistory, Error>] = []
        let store = WarRoomProgressStore(read: {
            reads += 1
            return try await withCheckedThrowingContinuation { gates.append($0) }
        }, now: { today })
        let a = Task { await store.refresh() }
        while gates.count < 1 { await Task.yield() }
        let b = Task { await store.refresh(force: true) }
        await Task.yield()
        a.cancel()
        gates[0].resume(returning: history([]))
        await a.value; await b.value
        check(reads == 1 && store.progress?.complete == true && store.error == nil, "concurrent manual/automatic reads share task despite one waiter cancellation")

        let obsolete = Task { await store.refresh(force: true) }
        while gates.count < 2 { await Task.yield() }
        store.invalidate()
        store.invalidate()
        let following = Task { await store.refresh(force: true) }
        await Task.yield()
        gates[1].resume(returning: history(wins(40)))
        while gates.count < 3 { await Task.yield() }
        check(store.progress?.victories == 0, "response preceding mutations is never published")
        gates[2].resume(returning: history([battle("2026-09-28")]))
        await obsolete.value; await following.value
        check(reads == 3 && store.progress?.victories == 1, "mutation burst coalesces to exactly one following read")
        await store.refresh()
        check(reads == 3, "only accepted following response becomes fresh")
    }

    @MainActor static func receptionClockChecks() async {
        var clock = today
        var reads = 0
        var gate: CheckedContinuation<WarRoomHistory, Error>?
        let store = WarRoomProgressStore(read: {
            reads += 1
            if reads == 1 { return try await withCheckedThrowingContinuation { gate = $0 } }
            return history([])
        }, now: { clock }, freshness: 10)
        let initial = Task { await store.refresh() }
        while gate == nil { await Task.yield() }
        clock = clock.addingTimeInterval(100)
        gate?.resume(returning: history([]))
        await initial.value
        clock = clock.addingTimeInterval(9)
        await store.refresh()
        check(reads == 1, "freshness starts at accepted reception, not request start")
        clock = clock.addingTimeInterval(1)
        await store.refresh()
        check(reads == 2, "injected freshness expires at its exact boundary")
    }
}
