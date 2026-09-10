import SwiftUI

// Scratch/debug — vue jetable. Aucun consommateur en prod.
// Objectif : valider si le bug LIFO asyncLet_finish_after_task_completion
// (commits 5a6a976, a554e10 — betas iOS 26 mai 2026) est corrigé en iOS 26.6.1 GA.
// Chaque bouton lance 5 itérations de 12 tâches concurrentes avec sleeps
// aléatoires 50–400ms → complétion non-déterministe = déclencheur historique
// du crash SIGABRT "freed pointer was not the last allocation".
// Supprimer ce fichier + Views/_Scratch/ une fois la décision prise.

struct ConcurrencyProbeView: View {
    @State private var results: [String] = []
    @State private var running = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Button("async let ×12 (5 iter)") { runAsyncLet() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)
                Button("withTaskGroup ×12 (5 iter)") { runTaskGroup() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)
                Button("multi-Task ×12 (5 iter)") { runMultiTask() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)

                Button("Clear") { results.removeAll() }
                    .buttonStyle(.bordered)
                    .disabled(running)

                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(results.indices, id: \.self) { i in
                            Text(results[i])
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Concurrency Probe")
        }
    }

    /// Sleep aléatoire 50–400 ms puis retourne la durée réelle (ns).
    /// Aléa = complétion non-déterministe = trigger du LIFO bug.
    private static func fakeWork() async -> UInt64 {
        let ns = UInt64.random(in: 50_000_000...400_000_000)
        try? await Task.sleep(nanoseconds: ns)
        return ns
    }

    // MARK: - Pattern 1 : async let

    private func runAsyncLet() {
        Task {
            running = true
            defer { running = false }
            append("── async let ×12 ──")
            for iter in 1...5 {
                let t = Date()
                async let a0  = Self.fakeWork()
                async let a1  = Self.fakeWork()
                async let a2  = Self.fakeWork()
                async let a3  = Self.fakeWork()
                async let a4  = Self.fakeWork()
                async let a5  = Self.fakeWork()
                async let a6  = Self.fakeWork()
                async let a7  = Self.fakeWork()
                async let a8  = Self.fakeWork()
                async let a9  = Self.fakeWork()
                async let a10 = Self.fakeWork()
                async let a11 = Self.fakeWork()
                _ = await a0;  _ = await a1;  _ = await a2;  _ = await a3
                _ = await a4;  _ = await a5;  _ = await a6;  _ = await a7
                _ = await a8;  _ = await a9;  _ = await a10; _ = await a11
                append(String(format: "  iter %d: ✅ OK (%.2fs)", iter, Date().timeIntervalSince(t)))
            }
            append("── async let: done ──")
        }
    }

    // MARK: - Pattern 2 : withTaskGroup

    private func runTaskGroup() {
        Task {
            running = true
            defer { running = false }
            append("── withTaskGroup ×12 ──")
            for iter in 1...5 {
                let t = Date()
                await withTaskGroup(of: UInt64.self) { group in
                    for _ in 0..<12 { group.addTask { await Self.fakeWork() } }
                    for await _ in group {}
                }
                append(String(format: "  iter %d: ✅ OK (%.2fs)", iter, Date().timeIntervalSince(t)))
            }
            append("── withTaskGroup: done ──")
        }
    }

    // MARK: - Pattern 3 : multi-Task + acteur compteur

    private func runMultiTask() {
        Task {
            running = true
            defer { running = false }
            append("── multi-Task ×12 ──")
            for iter in 1...5 {
                let t = Date()
                let counter = ProbeCounter()
                await withCheckedContinuation { cont in
                    let box = ContinuationBox(cont)
                    for _ in 0..<12 {
                        Task {
                            _ = await Self.fakeWork()
                            if await counter.increment() == 12 {
                                box.resumeOnce()
                            }
                        }
                    }
                }
                append(String(format: "  iter %d: ✅ OK (%.2fs)", iter, Date().timeIntervalSince(t)))
            }
            append("── multi-Task: done ──")
        }
    }

    private func append(_ s: String) {
        results.append(s)
        print(s)
    }
}

// MARK: - Helpers

actor ProbeCounter {
    private var count = 0
    func increment() -> Int { count += 1; return count }
}

/// Wrapper class-based pour partager la continuation entre 12 Tasks sans race
/// sur resume(). resumeOnce() garantit un seul appel même si la logique de comptage
/// est mal câblée (défensif — ici l'acteur assure déjà 1 seul call).
final class ContinuationBox: @unchecked Sendable {
    private var cont: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    init(_ cont: CheckedContinuation<Void, Never>) { self.cont = cont }

    func resumeOnce() {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume()
    }
}

#Preview {
    ConcurrencyProbeView()
}
