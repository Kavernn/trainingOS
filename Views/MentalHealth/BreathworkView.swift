import SwiftUI

struct BreathworkView: View {
    @State private var techniques: [BreathworkTechnique] = []
    @State private var stats: BreathworkStats?
    @State private var isLoading = true
    @State private var selectedTechnique: BreathworkTechnique?

    var body: some View {
        List {
            // Stats rapides
            if let stats {
                Section {
                    HStack(spacing: 0) {
                        BWStatChip(label: "Sessions", value: "\(stats.sessionsCount)", icon: "checkmark.circle.fill", color: .statusGreen)
                        Divider()
                        BWStatChip(label: "Minutes", value: "\(stats.totalMinutes)", icon: "clock.fill", color: .statusBlue)
                        if let fav = stats.favorite {
                            Divider()
                            BWStatChip(label: "Favori", value: fav, icon: "star.fill", color: .statusYellow)
                        }
                    }
                    .frame(height: 56)
                }
            }

            Section("Choisir une technique") {
                if isLoading {
                    ProgressView()
                } else {
                    ForEach(techniques) { technique in
                        Button { selectedTechnique = technique } label: {
                            TechniqueRow(technique: technique)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Respiration guidée")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedTechnique) { technique in
            BreathworkTimerView(technique: technique)
        }
        .task { await loadData() }
    }

    private func loadData() async {
        // sequential — async let LIFO crash on iOS 26 beta
        let tec = try? await APIService.shared.fetchBreathworkTechniques()
        let st  = try? await APIService.shared.fetchBreathworkStats(days: 7)
        await MainActor.run {
            techniques = tec ?? []
            stats      = st
            isLoading  = false
        }
    }
}

private struct BWStatChip: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color).font(.caption)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TechniqueRow: View {
    let technique: BreathworkTechnique

    private var accentColor: Color {
        switch technique.color {
        case "green":  return .statusGreen
        case "blue":   return .statusBlue
        case "purple": return .statusPurple
        case "cyan":   return .statusCyan
        default:       return .gray
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: technique.icon)
                .font(.title2)
                .foregroundColor(accentColor)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(technique.name).font(.headline)
                    Spacer()
                    Text(technique.difficulty)
                        .font(.caption)
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.12))
                        .cornerRadius(8)
                }
                Text(technique.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text("\(technique.totalSec / 60) min · \(technique.targetCycles) cycles")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Timer View

struct BreathworkTimerView: View {
    let technique: BreathworkTechnique

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPhaseIndex = 0
    @State private var secondsLeft: Int = 0
    @State private var cyclesCompleted = 0
    @State private var totalSecondsElapsed = 0
    @State private var isRunning = false
    @State private var isFinished = false
    @State private var timer: Timer?
    @State private var circleScale: CGFloat = 1.0
    @State private var saveError: String? = nil

    private var currentPhase: BreathworkPhase {
        technique.phases[currentPhaseIndex % technique.phases.count]
    }

    private var accentColor: Color {
        switch technique.color {
        case "green":  return .statusGreen
        case "blue":   return .statusBlue
        case "purple": return .statusPurple
        case "cyan":   return .statusCyan
        default:       return .gray
        }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if isFinished {
                finishedBody
            } else {
                timerBody
            }
        }
        .alert("Note", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    // MARK: Timer body

    private var timerBody: some View {
        VStack(spacing: 32) {
            HStack {
                Button { stopAndDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Arrêter et fermer")
                Spacer()
                Text(technique.name)
                    .font(.headline)
                Spacer()
                Text("\(cyclesCompleted)/\(technique.targetCycles)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)

            Spacer()

            // Cercle animé
            ZStack {
                Circle()
                    .stroke(accentColor.opacity(0.15), lineWidth: 12)
                    .frame(width: 200, height: 200)
                Circle()
                    .stroke(accentColor, lineWidth: 8)
                    .frame(width: 200, height: 200)
                    .scaleEffect(circleScale)
                    .animation(reduceMotion ? .none : .easeInOut(duration: Double(currentPhase.seconds)), value: circleScale)

                VStack(spacing: 6) {
                    Text(currentPhase.label)
                        .font(.title2.bold())
                        .foregroundColor(accentColor)
                    Text("\(secondsLeft)s")
                        .font(.largeTitle.monospacedDigit())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(currentPhase.label) — \(secondsLeft) secondes restantes")
            .accessibilityAddTraits(.updatesFrequently)

            Text(phaseInstruction)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button {
                isRunning ? pauseTimer() : startTimer()
            } label: {
                Label(isRunning ? "Pause" : (cyclesCompleted == 0 && secondsLeft == 0 ? "Commencer" : "Reprendre"),
                      systemImage: isRunning ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(accentColor)
                    .cornerRadius(16)
            }
            .padding(.bottom, 40)
            .accessibilityLabel(isRunning ? "Pause" : (cyclesCompleted == 0 && secondsLeft == 0 ? "Commencer la séance" : "Reprendre"))
        }
        .onAppear { secondsLeft = currentPhase.seconds }
        .onDisappear { pauseTimer() }
    }

    private var phaseInstruction: String {
        switch currentPhase.phase {
        case "inhale":  return "Inspire lentement par le nez"
        case "exhale":  return "Expire doucement par la bouche"
        case "hold":    return "Retiens ta respiration"
        case "holdOut": return "Poumons vides — attends"
        default:        return ""
        }
    }

    // MARK: Finished body

    private var finishedBody: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(accentColor)
            Text("Bien joué !")
                .font(.largeTitle.bold())
            Text("\(cyclesCompleted) cycles complétés · \(totalSecondsElapsed / 60) min \(totalSecondsElapsed % 60) sec")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Fermer") { dismiss() }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(accentColor)
                .cornerRadius(16)
        }
        .onAppear { saveSession() }
    }

    // MARK: Timer logic

    private func startTimer() {
        if secondsLeft == 0 { secondsLeft = currentPhase.seconds }
        isRunning = true
        updateCircle()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            tick()
        }
    }

    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        totalSecondsElapsed += 1
        if secondsLeft > 1 {
            secondsLeft -= 1
        } else {
            // Passer à la phase suivante
            currentPhaseIndex += 1
            if currentPhaseIndex % technique.phases.count == 0 {
                cyclesCompleted += 1
                if cyclesCompleted >= technique.targetCycles {
                    timer?.invalidate()
                    timer = nil
                    isRunning = false
                    isFinished = true
                    triggerImpact(style: .heavy)
                    return
                }
            }
            secondsLeft = currentPhase.seconds
            updateCircle()
            // Haptic cue on every phase transition
            triggerImpact(style: currentPhase.phase == "inhale" ? .light : .medium)
        }
    }

    private func updateCircle() {
        let target: CGFloat = currentPhase.phase == "inhale" ? 1.3 : (currentPhase.phase == "exhale" ? 0.8 : 1.0)
        circleScale = target
    }

    private func stopAndDismiss() {
        timer?.invalidate()
        dismiss()
    }

    private func saveSession() {
        Task {
            do {
                _ = try await APIService.shared.submitBreathworkSession(
                    techniqueId: technique.id,
                    durationSec: totalSecondsElapsed,
                    cycles:      cyclesCompleted
                )
            } catch {
                await MainActor.run {
                    saveError = "Session breathwork non enregistrée — réessaie"
                }
            }
        }
    }
}
