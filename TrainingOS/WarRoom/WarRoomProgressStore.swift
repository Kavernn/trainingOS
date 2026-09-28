import Foundation
import Combine

@MainActor
final class WarRoomProgressStore: ObservableObject {
    static let shared = WarRoomProgressStore()
    @Published private var snapshot: WarRoomProgress?
    // The existing shared owner is scoped to the actual API identity, never to a programme/day.
    var progress: WarRoomProgress? { scope == contextIdentity() ? snapshot : nil }
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var generation = 0
    private var scope: String?
    private var receivedAt: Date?
    private var acceptedGeneration: Int?
    private var attemptedGeneration: Int?
    private var feedback = WarRoomVictoryFeedback()
    private let read: () async throws -> WarRoomHistory
    private let now: () -> Date
    private let contextIdentity: () -> String
    private let freshness: TimeInterval
    private struct Flight {
        let id: UUID
        let generation: Int
        let scope: String
        let task: Task<Void, Never>
    }
    private var flight: Flight?

    init(read: @escaping () async throws -> WarRoomHistory = { try await APIService.shared.getWarRoomProgress() },
         now: @escaping () -> Date = Date.init,
         freshness: TimeInterval = 60,
         contextIdentity: @escaping () -> String = { APIService.warRoomContextIdentity }) {
        self.read = read
        self.now = now
        self.freshness = max(0, freshness)
        self.contextIdentity = contextIdentity
    }

    /// Automatic openings reuse a complete, accepted snapshot. Manual refresh bypasses age only.
    func refresh(force: Bool = false) async {
        await load(force: force, followInvalidation: true)
    }

    private func alignContext() {
        let current = contextIdentity()
        guard scope != current else { return }
        generation += 1
        flight?.task.cancel()
        flight = nil
        scope = current
        snapshot = nil
        receivedAt = nil
        acceptedGeneration = nil
        attemptedGeneration = nil
        feedback = WarRoomVictoryFeedback()
        error = nil
        isLoading = false
    }

    /// Reproject once per business date, even when the history is reused across midnight.
    func reprojectForCurrentDate() {
        alignContext()
        guard let snapshot, snapshot.today != DateFormatter.isoDate.string(from: now()) else { return }
        self.snapshot = WarRoomProgress(history: snapshot.history, calendar: Calendar.mtl,
                                        formatter: DateFormatter.isoDate, today: now())
    }

    private func load(force: Bool, followInvalidation: Bool) async {
        reprojectForCurrentDate()
        let currentScope = contextIdentity()
        let current: Flight
        if let flight {
            current = flight
        } else {
            if !force, let receivedAt, acceptedGeneration == generation,
               snapshot?.complete == true, error == nil,
               (0..<freshness).contains(now().timeIntervalSince(receivedAt)) { return }
            let id = UUID()
            let request = generation
            let requestDay = DateFormatter.isoDate.string(from: now())
            attemptedGeneration = request
            isLoading = true
            // Store-owned task: cancelling a view's waiter must not cancel another consumer's read.
            let task = Task { [weak self] in
                guard let self else { return }
                await self.receive(id: id, generation: request, scope: currentScope, requestDay: requestDay)
            }
            current = Flight(id: id, generation: request, scope: currentScope, task: task)
            flight = current
        }
        await current.task.value
        // Coalesce mutations during the read into one following read, never retry failures in a loop.
        if followInvalidation, current.scope == contextIdentity(), generation != current.generation {
            if let next = flight {
                await next.task.value
            } else if attemptedGeneration != generation {
                await load(force: false, followInvalidation: false)
            }
        }
    }

    private func receive(id: UUID, generation request: Int, scope requestScope: String, requestDay: String) async {
        defer {
            if flight?.id == id { flight = nil; isLoading = false }
        }
        do {
            let history = try await read()
            try Task.checkCancellation()
            guard request == generation, requestScope == contextIdentity(), scope == requestScope else { return }
            let today = DateFormatter.isoDate.string(from: now())
            guard history.throughDate == today || history.throughDate == requestDay else {
                throw URLError(.badServerResponse)
            }
            if !history.complete, let snapshot, snapshot.complete, snapshot.history.context == history.context {
                receivedAt = nil
                error = "Historique reçu incomplet. Les données déjà chargées sont conservées."
                return
            }
            if snapshot?.history.context != history.context { feedback = WarRoomVictoryFeedback() }
            snapshot = WarRoomProgress(history: history, calendar: Calendar.mtl,
                                       formatter: DateFormatter.isoDate, today: now())
            acceptedGeneration = request
            receivedAt = history.complete ? now() : nil
            error = nil
        } catch is CancellationError {
            if request == generation, requestScope == scope { receivedAt = nil }
        } catch let failure as URLError where failure.code == .cancelled {
            if request == generation, requestScope == scope { receivedAt = nil }
        } catch {
            guard request == generation, requestScope == contextIdentity(), scope == requestScope else { return }
            receivedAt = nil
            self.error = "Historique indisponible. Réessaie; les données déjà chargées sont conservées."
        }
    }

    /// Called only after a confirmed server mutation, including corrections/backfills.
    func invalidate() {
        alignContext()
        generation += 1
        receivedAt = nil
    }

    func configurationChanged() async {
        invalidate()
        snapshot = nil
        acceptedGeneration = nil
        await refresh(force: true)
    }

    func confirmedVictory(date: String, status: BattleStatus, before: WarRoomProgress?) async -> String? {
        await refresh(force: true)
        guard error == nil, acceptedGeneration == generation, status == .victory,
              feedback.accept(date: date, before: before, after: progress), let progress else { return nil }
        let next = progress.nextThreshold.map { " · Prochain palier à \($0)" } ?? " · 100 victoires et plus"
        return "Victoire enregistrée\n\(progress.victories) au total\(next)"
    }
}
