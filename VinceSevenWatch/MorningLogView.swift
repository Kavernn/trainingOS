import SwiftUI
import WatchKit

struct MorningLogView: View {
    @EnvironmentObject var mgr: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var step     = 0  // 0=énergie, 1=courbatures, 2=humeur, 3=envoyé
    @State private var energy   = 7
    @State private var soreness = 3
    @State private var moodIdx  = 2  // 0=low 1=neutral 2=good 3=great

    private let moodEmojis = ["😔", "😐", "😊", "💪"]
    private let moodKeys   = ["low", "neutral", "good", "great"]

    var body: some View {
        Group {
            switch step {
            case 0: energyView
            case 1: sorenessView
            case 2: moodView
            default: doneView
            }
        }
        .navigationTitle("Log matin")
        .animation(.easeInOut, value: step)
    }

    // MARK: - Steps

    private var energyView: some View {
        VStack(spacing: 6) {
            Text("Énergie")
                .font(.headline)
            Text("\(energy)/10")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.orange)
                .focusable()
                .digitalCrownRotation(
                    Binding(get: { Double(energy) }, set: { energy = Int($0.rounded()) }),
                    from: 1, through: 10, by: 1,
                    sensitivity: .low,
                    isContinuous: false
                )
            Button("Suivant") { step = 1 }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
    }

    private var sorenessView: some View {
        VStack(spacing: 6) {
            Text("Courbatures")
                .font(.headline)
            Text("\(soreness)/10")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(soreness >= 7 ? .red : .orange)
                .focusable()
                .digitalCrownRotation(
                    Binding(get: { Double(soreness) }, set: { soreness = Int($0.rounded()) }),
                    from: 1, through: 10, by: 1,
                    sensitivity: .low,
                    isContinuous: false
                )
            Button("Suivant") { step = 2 }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
    }

    private var moodView: some View {
        VStack(spacing: 6) {
            Text("Humeur")
                .font(.headline)
            Text(moodEmojis[moodIdx])
                .font(.system(size: 50))
                .focusable()
                .digitalCrownRotation(
                    Binding(
                        get: { Double(moodIdx) },
                        set: { moodIdx = min(3, max(0, Int($0.rounded()))) }
                    ),
                    from: 0, through: 3, by: 1,
                    sensitivity: .low,
                    isContinuous: false
                )
            Button("Envoyer") { send() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
    }

    private var doneView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Envoyé !")
                .font(.headline)
        }
        .onAppear {
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
        }
    }

    // MARK: - Submit

    private func send() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let log = WatchRecoveryLog(
            energy: energy,
            soreness: soreness,
            mood: moodKeys[moodIdx],
            date: fmt.string(from: Date())
        )
        mgr.sendRecoveryLog(log)
        step = 3
    }
}
