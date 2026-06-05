import SwiftUI
import WatchKit

struct ActiveSessionView: View {
    let session: WatchActiveSession
    @EnvironmentObject var mgr: WatchSessionManager

    @State private var currentIndex  = 0
    @State private var displayWeight = 0.0  // dans l'unité affichée (kg ou lbs)
    @State private var reps          = 8
    @State private var showCheck     = false

    private var exercise: WatchExercise? { session.exercises[safe: currentIndex] }

    var body: some View {
        Group {
            if let ex = exercise {
                exerciseView(ex)
            } else {
                Label("Séance terminée", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .navigationTitle("\(currentIndex + 1)/\(session.exercises.count)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadExercise() }
    }

    private func exerciseView(_ ex: WatchExercise) -> some View {
        VStack(spacing: 6) {
            Text(ex.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Divider()

            HStack(alignment: .center) {
                // Poids — Digital Crown
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", displayWeight))
                        .font(.title2.bold())
                        .foregroundStyle(.orange)
                        .focusable()
                        .digitalCrownRotation(
                            $displayWeight,
                            from: 0, through: 500,
                            by: mgr.weightIncrement,
                            sensitivity: .medium,
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )
                    Text(mgr.unitIsKg ? "kg" : "lbs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Reps — tap +/−
                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Button { if reps > 1 { reps -= 1 } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        Text("\(reps)")
                            .font(.title2.bold())
                            .frame(minWidth: 28)
                        Button { if reps < 30 { reps += 1 } } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    Text("reps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            Button { logSet(ex: ex) } label: {
                HStack {
                    if showCheck {
                        Image(systemName: "checkmark")
                    } else {
                        Text("Logger")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(showCheck ? .green : .orange)
            .disabled(showCheck)
        }
    }

    private func loadExercise() {
        guard let ex = session.exercises[safe: currentIndex] else { return }
        let lbs = ex.defaultWeightLbs
        displayWeight = mgr.unitIsKg ? lbs * 0.453592 : lbs
        reps = Int(ex.targetReps.split(separator: "-").first.flatMap { Int($0) } ?? 8)
    }

    private func logSet(ex: WatchExercise) {
        let lbs = mgr.unitIsKg ? displayWeight / 0.453592 : displayWeight
        let log = WatchSetLog(
            exerciseId: ex.id,
            exerciseName: ex.name,
            weightLbs: lbs,
            reps: reps,
            rpe: nil,
            timestamp: Date()
        )
        mgr.sendSetLog(log)
        WKInterfaceDevice.current().play(.success)

        withAnimation(.easeInOut(duration: 0.2)) { showCheck = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { showCheck = false }
            let next = currentIndex + 1
            if next < session.exercises.count {
                currentIndex = next
                loadExercise()
            }
        }
    }
}
