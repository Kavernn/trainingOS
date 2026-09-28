import Foundation
import Combine

@MainActor
final class WarRoomProgressStore: ObservableObject {
    static let shared = WarRoomProgressStore()
    @Published private(set) var progress: WarRoomProgress?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var generation = 0
    private var feedback = WarRoomVictoryFeedback()
    private let read: () async throws -> WarRoomHistory
    private let now: () -> Date

    init(read: @escaping () async throws -> WarRoomHistory = { try await APIService.shared.getWarRoomProgress() },
         now: @escaping () -> Date = Date.init) {
        self.read = read
        self.now = now
    }

    func refresh(force: Bool = false) async {
        if isLoading && !force { return }
        generation += 1
        let request = generation
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let history = try await read()
            try Task.checkCancellation()
            guard request == generation else { return }
            guard history.throughDate == DateFormatter.isoDate.string(from: now()) else {
                throw URLError(.badServerResponse)
            }
            progress = WarRoomProgress(history: history, calendar: Calendar.mtl,
                                       formatter: DateFormatter.isoDate, today: now())
            error = nil
        } catch is CancellationError {
            // Keep the last coherent projection; cancellation is not a network failure.
        } catch let failure as URLError where failure.code == .cancelled {
        } catch {
            guard request == generation else { return }
            self.error = "Historique indisponible. Réessaie; les données déjà chargées sont conservées."
        }
    }

    func configurationChanged() async {
        // Reject old-context responses, including when the new read fails.
        generation += 1
        progress = nil
        await refresh(force: true)
    }

    func confirmedVictory(date: String, status: BattleStatus, before: WarRoomProgress?) async -> String? {
        await refresh(force: true)
        guard error == nil, status == .victory,
              feedback.accept(date: date, before: before, after: progress), let progress else { return nil }
        let next = progress.nextThreshold.map { " · Prochain palier à \($0)" } ?? " · 100 victoires et plus"
        return "Victoire enregistrée\n\(progress.victories) au total\(next)"
    }
}
