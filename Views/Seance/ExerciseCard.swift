import SwiftUI
import Charts

// MARK: - StepperInput

struct StepperInput: View {
    @Binding var valueStr: String
    let increment: Double
    let minimum: Double
    let placeholder: Double
    var isInteger: Bool = false
    var isDisabled: Bool = false
    var autoFocus: Bool = false

    @FocusState private var isManualFocused: Bool
    @State private var holdTask: Task<Void, Never>? = nil
    @GestureState private var minusHeld = false
    @GestureState private var plusHeld = false

    private var currentValue: Double {
        valueStr.isEmpty
            ? placeholder
            : Double(valueStr.replacingOccurrences(of: ",", with: ".")) ?? placeholder
    }

    private var displayText: String {
        guard !valueStr.isEmpty else { return "" }
        return isInteger ? "\(Int(currentValue))" : formatted(currentValue)
    }

    private var placeholderText: String {
        isInteger ? "\(Int(placeholder))" : formatted(placeholder)
    }

    private func formatted(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }

    var body: some View {
        HStack(spacing: 0) {
            stepIcon(systemName: "minus", isHeld: minusHeld)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($minusHeld) { _, state, _ in state = true }
                        .onChanged { _ in startHold(-1) }
                        .onEnded   { _ in stopHold() }
                )
                .disabled(isDisabled)

            ZStack {
                Text(valueStr.isEmpty ? placeholderText : displayText)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(valueStr.isEmpty ? .gray.opacity(0.35) : .white)
                    .frame(minWidth: 52, alignment: .center)
                    .allowsHitTesting(false)

                TextField("", text: $valueStr)
                    .keyboardType(isInteger ? .numberPad : .decimalPad)
                    .focused($isManualFocused)
                    .opacity(0.01)
                    .frame(minWidth: 52)
                    .disabled(isDisabled)
                    .multilineTextAlignment(.center)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isDisabled else { return }
                isManualFocused = true
            }

            stepIcon(systemName: "plus", isHeld: plusHeld)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($plusHeld) { _, state, _ in state = true }
                        .onChanged { _ in startHold(1) }
                        .onEnded   { _ in stopHold() }
                )
                .disabled(isDisabled)
        }
        .background(Color(hex: "191926"))
        .cornerRadius(10)
        .onChange(of: isManualFocused) { _, focused in
            if !focused { validateInput() }
        }
        .onAppear {
            guard autoFocus else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isManualFocused = true
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isManualFocused {
                    Spacer()
                    Button("Terminé") { isManualFocused = false }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(systemName: String, isHeld: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 44, height: 44)
            .foregroundColor(isDisabled ? .gray.opacity(0.2) : .white.opacity(isHeld ? 1.0 : 0.7))
            .scaleEffect(isHeld ? 0.82 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: isHeld)
            .contentShape(Rectangle())
    }

    private func startHold(_ direction: Int) {
        guard holdTask == nil else { return }
        step(direction)
        holdTask = Task {
            // 400ms avant le début du rapid-fire
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let loopStart = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(loopStart)
                let ns: UInt64 = elapsed < 1.0 ? 200_000_000   // 200ms — lent
                               : elapsed < 2.5 ? 80_000_000    //  80ms — moyen
                               :                 30_000_000    //  30ms — rapide (~83 lbs/s)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                await MainActor.run { step(direction) }
            }
        }
    }

    private func stopHold() {
        holdTask?.cancel()
        holdTask = nil
    }

    private func step(_ direction: Int) {
        let newVal = max(minimum, currentValue + Double(direction) * increment)
        apply(newVal)
        triggerImpact(style: .light)
    }

    private func apply(_ val: Double) {
        let clamped = max(minimum, val)
        valueStr = isInteger ? "\(Int(clamped))" : formatted(clamped)
    }

    private func validateInput() {
        guard !valueStr.isEmpty else { return }
        let v = Double(valueStr.replacingOccurrences(of: ",", with: ".")) ?? minimum
        apply(v)
    }
}

// MARK: - Hold To Log Button

private struct HoldToLogButton: View {
    let label: String
    let icon: String
    let isEnabled: Bool
    let logFlash: Bool
    let onLog: () -> Void

    @GestureState private var isHolding = false

    var body: some View {
        let holding = isHolding && isEnabled
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(logFlash ? Color.green : Color(hex: "1a1a2e"))
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20))
                Text(holding ? "Maintenir..." : label)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(logFlash ? .black : (isEnabled ? .white : .gray))
        }
        .frame(maxWidth: .infinity).frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(holding ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: holding)
        .animation(.easeInOut(duration: 0.12), value: logFlash)
        .opacity(isEnabled ? 1 : 0.6)
        .gesture(
            LongPressGesture(minimumDuration: 0.4)
                .updating($isHolding) { _, state, _ in state = true }
                .onEnded { _ in onLog() }
        )
    }
}

// MARK: - Exercise Card

struct ExerciseCard: View {
    let name: String
    let scheme: String
    let weightData: WeightData?
    var equipmentType: String = "machine"
    var trackingType: String = "reps"
    var bodyWeight: Double = 0
    var isSecondSession: Bool = false
    var isBonusSession: Bool = false
    var restSeconds: Int? = nil
    var prescription: ExercisePrescription? = nil
    var suggestion: ProgressionSuggestion? = nil
    var hint: String? = nil
    @Binding var logResult: ExerciseLogResult?
    var onLogged: (() -> Void)? = nil
    // Expand/collapse (controlled by parent)
    var isExpanded: Bool = false
    var isFocused: Bool = false
    var onToggle: () -> Void = {}
    var nextExerciseName: String? = nil
    var isReplaced: Bool = false
    var originalName: String? = nil
    var onSwap: (() -> Void)? = nil
    var movementPattern: String = ""

    @StateObject private var evm: ExerciseViewModel
    @ObservedObject private var units = UnitSettings.shared
    @ObservedObject private var restTimer = RestTimerManager.shared
    @AppStorage("exo_notes_data") private var exoNotesData: String = "{}"
    @AppStorage("auto_start_rest_timer") private var autoStartTimer = false
    @AppStorage("show_rir_column") private var showRIRColumn = false
    @State private var confirmSkip = false
    @State private var confirmSwapAfterLog = false
    @State private var showAdvanced = false
    @State private var showPlateCalculator = false
    @State private var showMediaSheet = false
    @State private var mediaGifUrl: String? = nil
    @State private var mediaMusclss: [String] = []
    @State private var mediaFetched = false
    // Hold-to-log
    @State private var logFlash = false
    // Undo window
    @State private var showUndo = false
    @State private var undoCountdown = 8
    @State private var undoTask: Task<Void, Never>?
    // Draft saved indicator
    @State private var showSaved = false

    init(name: String, scheme: String, weightData: WeightData?,
         equipmentType: String = "machine", trackingType: String = "reps",
         bodyWeight: Double = 0, isSecondSession: Bool = false, isBonusSession: Bool = false,
         restSeconds: Int? = nil, prescription: ExercisePrescription? = nil,
         suggestion: ProgressionSuggestion? = nil, hint: String? = nil,
         logResult: Binding<ExerciseLogResult?>, onLogged: (() -> Void)? = nil,
         isExpanded: Bool = false, isFocused: Bool = false, onToggle: @escaping () -> Void = {},
         nextExerciseName: String? = nil,
         isReplaced: Bool = false, originalName: String? = nil,
         onSwap: (() -> Void)? = nil,
         movementPattern: String = "") {
        self.name            = name
        self.scheme          = scheme
        self.weightData      = weightData
        self.equipmentType   = equipmentType
        self.trackingType    = trackingType
        self.bodyWeight      = bodyWeight
        self.isSecondSession = isSecondSession
        self.isBonusSession  = isBonusSession
        self.restSeconds     = restSeconds
        self.prescription    = prescription
        self.suggestion      = suggestion
        self.hint            = hint
        self._logResult      = logResult
        self.onLogged        = onLogged
        self.isExpanded      = isExpanded
        self.isFocused       = isFocused
        self.onToggle        = onToggle
        self.nextExerciseName = nextExerciseName
        self.isReplaced      = isReplaced
        self.originalName    = originalName
        self.onSwap          = onSwap
        self.movementPattern = movementPattern
        _evm = StateObject(wrappedValue: ExerciseViewModel(
            name: name, scheme: scheme, weightData: weightData,
            equipmentType: equipmentType, trackingType: trackingType,
            bodyWeight: bodyWeight, isSecondSession: isSecondSession,
            isBonusSession: isBonusSession, restSeconds: restSeconds,
            prescription: prescription, suggestion: suggestion))
    }

    // MARK: - View-layer computed

    private var isTimeBased: Bool { trackingType == "time" }

    private var canLogHint: String {
        if isTimeBased { return "Entre la durée pour logger" }
        if evm.equipmentType == "bodyweight" { return "Entre les reps pour logger" }
        let hasWeight = evm.sets.contains { !$0.weight.trimmingCharacters(in: .whitespaces).isEmpty }
        let hasReps   = evm.sets.contains { !$0.reps.isEmpty }
        if !hasWeight && !hasReps { return "Entre poids et reps pour logger" }
        if !hasWeight { return "Entre le poids pour logger" }
        return "Entre les reps pour logger"
    }

    private var weightIncrement: Double {
        let isLower = ["squat", "hinge"].contains(movementPattern.lowercased())
        if units.isKg { return isLower ? 2.5 : 1.25 }
        return isLower ? 5.0 : 2.5
    }

    private var alreadyLogged: Bool { evm.isLogged || logResult != nil || evm.isSkipped }

    private func adjustAllWeights(_ direction: Int) {
        for i in evm.sets.indices {
            let base = evm.sets[i].weight.isEmpty
                ? (Double(evm.perSetHint(for: i).replacingOccurrences(of: ",", with: ".")) ?? 0)
                : (Double(evm.sets[i].weight.replacingOccurrences(of: ",", with: ".")) ?? 0)
            let newVal = max(0, base + Double(direction) * weightIncrement)
            evm.sets[i].weight = newVal.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(newVal))"
                : String(format: "%.1f", newVal)
        }
        triggerImpact(style: .medium)
    }

    private var borderColor: Color {
        if alreadyLogged { return .green.opacity(0.28) }
        if isFocused     { return .orange.opacity(0.30) }
        if isExpanded    { return .orange.opacity(0.12) }
        return .white.opacity(0.07)
    }

    private var exoNote: String {
        (try? JSONDecoder().decode([String: String].self, from: Data(exoNotesData.utf8)))?[name] ?? ""
    }
    private func saveExoNote(_ note: String) {
        var notes = (try? JSONDecoder().decode([String: String].self, from: Data(exoNotesData.utf8))) ?? [:]
        if note.isEmpty { notes.removeValue(forKey: name) } else { notes[name] = note }
        if let d = try? JSONEncoder().encode(notes), let s = String(data: d, encoding: .utf8) {
            exoNotesData = s
        }
    }

    private var hasNote: Bool { !exoNote.isEmpty || !evm.sessionNote.isEmpty }

    private var noteIconButton: some View {
        Button {
            triggerImpact(style: .light)
            if !isExpanded { onToggle() }
            withAnimation(.easeInOut(duration: 0.2)) { showAdvanced = true }
        } label: {
            Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                .font(.system(size: 14))
                .foregroundColor(hasNote ? .orange : .gray.opacity(0.35))
        }
        .buttonStyle(.plain)
    }

    private var equipmentLabel: String {
        switch evm.equipmentType {
        case "barbell":    return "Barre"
        case "ez-bar":     return "EZ-Bar"
        case "dumbbell":   return "Haltères"
        case "bodyweight": return "Poids corps"
        case "cable":      return "Câble"
        default:           return "Machine"
        }
    }

    private var weightColumnLabel: String {
        switch evm.equipmentType {
        case "barbell":    return "POIDS PAR CÔTÉ (\(units.label.uppercased()))"
        case "dumbbell":   return "POIDS PAR HALTÈRE (\(units.label.uppercased()))"
        case "bodyweight": return "LEST (\(units.label.uppercased()))"
        case "ez-bar":     return "POIDS TOTAL (\(units.label.uppercased()))"
        default:           return "POIDS (\(units.label.uppercased()))"
        }
    }

    private func equipmentIcon(_ type: String) -> String {
        switch type {
        case "barbell", "ez-bar": return "minus.circle.fill"
        case "dumbbell":          return "dumbbell.fill"
        case "bodyweight":        return "figure.walk"
        case "cable":             return "arrow.up.and.down.circle"
        default:                  return "gearshape.fill"
        }
    }

    private func rpeColor(_ v: Double) -> Color { RPEHelper.color(for: v) }

    private func fetchMedia() {
        guard !mediaFetched else { showMediaSheet = true; return }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "https://training-os-rho.vercel.app/api/exercise/media?name=\(encoded)") else { return }
        Task {
            if let (data, _) = try? await URLSession.authed.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                await MainActor.run {
                    mediaGifUrl  = json["gif_url"] as? String
                    mediaMusclss = json["muscles"] as? [String] ?? []
                    mediaFetched = true
                    showMediaSheet = true
                }
            } else {
                await MainActor.run { mediaFetched = true; showMediaSheet = true }
            }
        }
    }

    private func doLog() {
        guard !showUndo else { return }
        if let result = evm.logExercise(alreadyLoggedViaBinding: logResult != nil) {
            logResult = result
            onLogged?()
            triggerNotificationFeedback(.success)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showUndo = true }
            if autoStartTimer, let secs = restSeconds, secs > 0 {
                RestTimerManager.shared.start(seconds: secs, exerciseName: name)
            }
            undoCountdown = 8
            undoTask?.cancel()
            undoTask = Task { @MainActor in
                for i in stride(from: 7, through: 0, by: -1) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    undoCountdown = i
                }
                withAnimation(.easeOut(duration: 0.3)) { showUndo = false }
            }
        }
    }

    // MARK: - Set rows

    @ViewBuilder private func setRows() -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("SET")
                    .font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(.gray)
                    .frame(width: 28, alignment: .leading)
                Text(weightColumnLabel)
                    .font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(.gray)
                if evm.equipmentType != "bodyweight" {
                    HStack(spacing: 2) {
                        Button { adjustAllWeights(-1) } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 18)
                                .foregroundColor(.gray.opacity(0.7))
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        Button { adjustAllWeights(1) } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 18)
                                .foregroundColor(.orange.opacity(0.85))
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if evm.equipmentType == "barbell" {
                    Button {
                        triggerImpact(style: .light)
                        showPlateCalculator = true
                    } label: {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange.opacity(0.8))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("REPS")
                    .font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(.gray)
                    .frame(width: 140, alignment: .center)
                // W-C2 — hide RIR column for time-based exercises
                if showRIRColumn && !isTimeBased {
                    HStack(spacing: 3) {
                        VStack(spacing: 1) {
                            Text("RIR")
                                .font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(.cyan.opacity(0.7))
                            Text("avant échec")
                                .font(.system(size: 9)).foregroundColor(.gray.opacity(0.45))
                        }
                        CardInfoButton(title: "RPE & RIR", entries: InfoEntry.rpeRirEntries)
                    }
                    .frame(width: 70, alignment: .center)
                }
            }
            ForEach(evm.sets.indices, id: \.self) { i in
                let isActive = evm.setBySetMode && i == evm.currentSetIndex
                let isDone   = evm.setBySetMode && i < evm.currentSetIndex
                HStack(spacing: 8) {
                    if isActive && !evm.repCountMode {
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange.opacity(0.35))
                            .transition(.opacity)
                    }
                    Text("S\(i + 1)")
                        .font(.system(size: isActive ? 16 : 11, weight: .bold))
                        .foregroundColor(isDone ? .green : isActive ? .orange : .gray)
                        .frame(width: 28)
                        .onLongPressGesture(minimumDuration: 0.35) {
                            guard i > 0 else { return }
                            evm.sets[i].weight = evm.sets[i - 1].weight
                            evm.sets[i].reps   = evm.sets[i - 1].reps
                            triggerImpact(style: .medium)
                        }
                    VStack(spacing: 2) {
                        StepperInput(
                            valueStr: $evm.sets[i].weight,
                            increment: weightIncrement,
                            minimum: 0,
                            placeholder: Double(evm.perSetHint(for: i)
                                .replacingOccurrences(of: ",", with: ".")) ?? 0,
                            isDisabled: evm.setBySetMode && !isActive && !isDone,
                            autoFocus: i == 0 && !alreadyLogged && !evm.setBySetMode
                        )
                        if evm.equipmentType == "barbell" || evm.equipmentType == "dumbbell" {
                            let rawVal = Double(evm.sets[i].weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                            let totalLbs = evm.totalWeight(for: units.toStorage(rawVal))
                            if totalLbs > 0 {
                                Text("= \(units.format(totalLbs, decimals: 0))")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.gray.opacity(0.45))
                            }
                        }
                    }
                    if evm.repCountMode && isActive {
                        Text(evm.currentRepCount > 0 ? "\(evm.currentRepCount)" : "—")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.purple)
                            .multilineTextAlignment(.center)
                            .frame(width: 56)
                            .padding(8)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        StepperInput(
                            valueStr: $evm.sets[i].reps,
                            increment: 1,
                            minimum: 1,
                            placeholder: Double(evm.lastRepsParts.indices.contains(i)
                                ? evm.lastRepsParts[i] : "1") ?? 1,
                            isInteger: true,
                            isDisabled: evm.setBySetMode && !isActive && !isDone
                        )
                        .frame(width: 140)
                    }
                    // W-C2 — hide RIR tiles for time-based exercises
                    if showRIRColumn && !isTimeBased {
                        RPEHelper.RIRTiles(
                            rir: $evm.sets[i].rir,
                            disabled: evm.setBySetMode && !isActive && !isDone
                        )
                        .frame(width: 70)
                    }

                    if let p = prescription, !evm.sets[i].reps.isEmpty, let entered = Int(evm.sets[i].reps) {
                        Image(systemName: entered >= p.repMin ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(entered >= p.repMin ? .green : .orange)
                            .transition(.opacity)
                    }

                    if isActive && !evm.repCountMode {
                        Button {
                            withAnimation {
                                triggerImpact(style: .medium)
                                if evm.currentSetIndex < evm.sets.count - 1 {
                                    evm.currentSetIndex += 1
                                } else {
                                    evm.setBySetMode = false
                                    doLog()
                                }
                            }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(SpringButtonStyle(scale: 0.88))
                    } else if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18)).foregroundColor(.green.opacity(0.6))
                    }
                }
                .padding(isActive ? 6 : 0)
                .background(isActive ? Color.orange.opacity(0.12) : Color.clear)
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.2), value: evm.currentSetIndex)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { v in
                            guard isActive && !evm.repCountMode else { return }
                            guard v.translation.width > 60, abs(v.translation.height) < 50 else { return }
                            withAnimation {
                                triggerImpact(style: .medium)
                                if evm.currentSetIndex < evm.sets.count - 1 {
                                    evm.currentSetIndex += 1
                                } else {
                                    evm.setBySetMode = false
                                    doLog()
                                }
                            }
                        }
                )
            }
            if !evm.repsStr.isEmpty {
                HStack {
                    Text("→ \(evm.repsStr)").font(.system(size: 11)).foregroundColor(.gray)
                    Spacer()
                }
                .padding(.top, 2)
            }
            if evm.repCountMode {
                repCounterSection
            } else if evm.setBySetMode {
                Text("Set \(evm.currentSetIndex + 1)/\(evm.sets.count) — appuie ✓ après chaque set")
                    .font(.system(size: 11)).foregroundColor(.orange.opacity(0.7))
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder private var repCounterSection: some View {
        VStack(spacing: 16) {
            Divider().background(Color.purple.opacity(0.2)).padding(.top, 4)

            Text("SET \(evm.currentSetIndex + 1) / \(evm.sets.count)")
                .font(.system(size: 11, weight: .bold)).tracking(2)
                .foregroundColor(.purple.opacity(0.7))

            Text("\(evm.currentRepCount)")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundColor(.purple)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: evm.currentRepCount)
                .frame(minWidth: 100)

            HStack(spacing: 36) {
                Button {
                    evm.decrementRep()
                    triggerImpact(style: .light)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.gray.opacity(0.45))
                }
                .buttonStyle(.plain)

                Button {
                    evm.tapRep()
                    triggerImpact(style: .medium)
                } label: {
                    ZStack {
                        Circle().fill(Color.purple.opacity(0.12)).frame(width: 112, height: 112)
                        Circle().stroke(Color.purple.opacity(0.35), lineWidth: 2).frame(width: 112, height: 112)
                        VStack(spacing: 4) {
                            Image(systemName: "hand.tap.fill").font(.system(size: 24))
                            Text("REP").font(.system(size: 14, weight: .black))
                        }
                        .foregroundColor(.purple)
                    }
                }
                .buttonStyle(SpringButtonStyle(scale: 0.92))

                Button {
                    evm.currentRepCount = 0
                    triggerImpact(style: .light)
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.gray.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            let isLastSet = evm.currentSetIndex == evm.sets.count - 1
            Button {
                let allDone = evm.confirmCurrentSet()
                triggerImpact(style: .medium)
                if allDone { doLog() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isLastSet ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.system(size: 18))
                    Text(isLastSet ? "Logger l'exercice" : "Set terminé →")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(evm.currentRepCount > 0
                    ? (isLastSet ? Color.orange : Color.purple)
                    : Color.gray.opacity(0.1))
                .foregroundColor(evm.currentRepCount > 0 ? .white : .gray)
                .cornerRadius(12)
            }
            .disabled(evm.currentRepCount == 0)
            .buttonStyle(SpringButtonStyle())
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func timeSetRows() -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { secs in
                    Button { for i in evm.sets.indices { evm.sets[i].duration = secs } } label: {
                        Text(evm.formatDuration(secs))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.cyan.opacity(0.15))
                            .foregroundColor(.cyan)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            HStack {
                Text("SET").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray).frame(width: 28, alignment: .leading)
                Text("DURÉE").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                Spacer()
            }
            ForEach(evm.sets.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Text("S\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundColor(.gray).frame(width: 28)
                    Button { if evm.sets[i].duration > 5 { evm.sets[i].duration -= 5 } } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 24)).foregroundColor(.gray)
                    }.buttonStyle(.plain)
                    Text(evm.formatDuration(evm.sets[i].duration))
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .frame(minWidth: 64, alignment: .center)
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .background(Color(hex: "191926")).cornerRadius(8)
                    Button { evm.sets[i].duration += 5 } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundColor(.cyan)
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }
            HStack {
                Text("→ \(evm.sets.map { evm.formatDuration($0.duration) }.joined(separator: ", "))")
                    .font(.system(size: 11)).foregroundColor(.gray)
                Spacer()
            }.padding(.top, 2)
        }
    }

    @ViewBuilder private var avgTotalRow: some View {
        switch evm.equipmentType {
        case "barbell", "dumbbell":
            if let avg = evm.avgWeight {
                let avgLbs = units.toStorage(avg)
                let total  = evm.totalWeight(for: avgLbs)
                HStack {
                    Text("MOY. → TOTAL")
                        .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                    Spacer()
                    Text("\(units.format(avgLbs)) → \(units.format(total))")
                        .font(.system(size: 14, weight: .black)).foregroundColor(.orange)
                }
                .padding(.top, 2)
            }
        case "bodyweight":
            if bodyWeight > 0 {
                HStack {
                    Text("TOTAL")
                        .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                    Spacer()
                    Text(units.format(bodyWeight))
                        .font(.system(size: 14, weight: .black)).foregroundColor(.orange)
                }
                .padding(.top, 2)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header — always visible, tap to expand/collapse
            headerButton

            // MARK: Expanded content
            if isExpanded { expandedContent }
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(borderColor, lineWidth: 1))
        .onAppear {
            evm.initializeSets()
            if !evm.painZone.isEmpty || !exoNote.isEmpty { showAdvanced = true }
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded, !alreadyLogged else { return }
            for i in evm.sets.indices where evm.sets[i].weight.isEmpty {
                let hint = evm.perSetHint(for: i)
                guard hint != "0.0", !hint.isEmpty else { continue }
                evm.sets[i].weight = hint
            }
            for i in evm.sets.indices where evm.sets[i].reps.isEmpty {
                let hint = evm.lastRepsParts.indices.contains(i) ? evm.lastRepsParts[i] : ""
                guard let reps = Int(hint), reps > 0 else { continue }
                evm.sets[i].reps = hint
            }
        }
        .onChange(of: evm.setsCount) {
            evm.syncSetsCount()
        }
        .onChange(of: logResult == nil) { _, isNil in
            if isNil { evm.resetAfterClear() }
        }
        .onChange(of: evm.isEditing) { _, editing in
            if editing {
                undoTask?.cancel(); undoTask = nil
                withAnimation(.easeOut(duration: 0.2)) { showUndo = false }
            }
        }
        .confirmationDialog("Changer l'exercice ?", isPresented: $confirmSwapAfterLog, titleVisibility: .visible) {
            Button("Changer et effacer le log", role: .destructive) {
                logResult = nil
                evm.resetAfterClear()
                triggerImpact(style: .medium)
                onSwap?()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le log de cet exercice sera effacé.")
        }
        .confirmationDialog(Text("Sauter \(name) ?"), isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Sauter cet exercice", role: .destructive) {
                evm.isSkipped = true
                triggerImpact(style: .light)
            }
            Button("Continuer", role: .cancel) {}
        }
        .sheet(isPresented: $showPlateCalculator) { plateCalculatorSheetView }
        .sheet(isPresented: $showMediaSheet) { mediaSheetView }
    }

    @ViewBuilder private var headerButton: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(alreadyLogged ? Color.green.opacity(0.14) : Color.orange.opacity(0.11))
                        .frame(width: 34, height: 34)
                    Image(systemName: alreadyLogged ? "checkmark" : "dumbbell")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(alreadyLogged ? .green : .orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        if isReplaced {
                            Text("remplacé")
                                .font(.system(size: 9, weight: .semibold)).foregroundColor(.orange)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12)).clipShape(Capsule())
                        }
                        let hasCoaching = logResult == nil && (
                            (suggestion?.suggestionType != "maintain" && suggestion != nil) ||
                            (hint != nil && !(hint?.isEmpty ?? true))
                        )
                        if hasCoaching {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                                .padding(3)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    Text(scheme).font(.system(size: 12)).foregroundColor(.gray)
                }
                Spacer()
                headerTrailing
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var headerTrailing: some View {
        if alreadyLogged && !evm.isEditing, let r = logResult {
            HStack(spacing: 8) {
                noteIconButton
                if restTimer.isRunning, restTimer.exerciseName == name {
                    HStack(spacing: 4) {
                        Image(systemName: "timer").font(.system(size: 10)).foregroundColor(.cyan)
                        Text(evm.formatDuration(restTimer.remaining))
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.1)).clipShape(Capsule())
                }
                VStack(alignment: .trailing, spacing: 2) {
                    if isTimeBased {
                        Text(r.reps.split(separator: ",").compactMap { Int($0) }
                                .map { evm.formatDuration($0) }.first ?? "—")
                            .font(.system(size: 13, weight: .black)).foregroundColor(.white)
                    } else {
                        Text(units.format(r.weight)).font(.system(size: 13, weight: .black)).foregroundColor(.white)
                        Text(r.reps).font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
                Button {
                    evm.isEditing = true
                    if !isExpanded { onToggle() }
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.gray.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 8) {
                noteIconButton
                if !isTimeBased, evm.lastReps != "—", !evm.lastReps.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        if let sw = suggestion?.suggestedWeight, sw > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundColor(.cyan)
                                Text(units.format(sw))
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(.cyan)
                            }
                        } else if evm.inputHint > 0 {
                            Text(units.format(evm.inputHint))
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.35))
                        }
                        Text(evm.lastReps).font(.system(size: 10)).foregroundColor(.gray.opacity(0.45))
                    }
                }
                Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.4))
                    .rotationEffect(.degrees(isExpanded ? 0 : 180))
                    .animation(.easeInOut(duration: 0.22), value: isExpanded)
            }
        }
    }

    @ViewBuilder private var expandedContent: some View {
        Divider().background(Color.white.opacity(0.07))
        VStack(alignment: .leading, spacing: 12) {
            expandedTopBar
            if logResult == nil, let s = suggestion, s.suggestionType != "maintain" {
                CoachingChip(suggestion: s)
            }
            if let h = hint, !h.isEmpty {
                Text(h).font(.system(size: 12, weight: .regular)).italic()
                    .foregroundColor(.gray.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if alreadyLogged && !evm.isEditing { loggedStateDisplay } else { formView }
            historySection
            if let next = nextExerciseName {
                HStack(spacing: 5) {
                    Text("Suivant").font(.system(size: 11, weight: .semibold)).foregroundColor(.gray.opacity(0.3))
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundColor(.gray.opacity(0.3))
                    Text(next).font(.system(size: 11, weight: .medium)).foregroundColor(.gray.opacity(0.45))
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .onChange(of: evm.draftSavedAt) { _ in
            guard !evm.isLogged else { return }
            withAnimation(.easeIn(duration: 0.15)) { showSaved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.4)) { showSaved = false }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showSaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                    Text("Sauvegardé").font(.system(size: 10))
                }
                .foregroundColor(.green.opacity(0.7))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.green.opacity(0.08))
                .cornerRadius(6)
                .padding(12)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var expandedTopBar: some View {
        HStack {
            Button { triggerImpact(style: .light); fetchMedia() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.circle.fill").font(.system(size: 12))
                    Text("Démo").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.purple).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.purple.opacity(0.1)).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            if let onSwap {
                Button {
                    if alreadyLogged {
                        confirmSwapAfterLog = true
                    } else {
                        triggerImpact(style: .light)
                        onSwap()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 11))
                        Text("Changer").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.gray.opacity(0.7)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.06)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if !isTimeBased {
                Button {
                    withAnimation {
                        evm.setBySetMode.toggle()
                        if evm.setBySetMode { evm.currentSetIndex = 0 }
                        if !evm.setBySetMode { evm.repCountMode = false }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: evm.setBySetMode ? "list.number" : "arrow.forward.circle")
                            .font(.system(size: 12))
                        Text("Set à set")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(evm.setBySetMode && !evm.repCountMode ? .orange : .gray.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.05)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation {
                        if evm.repCountMode {
                            evm.repCountMode = false
                        } else {
                            evm.repCountMode = true
                            evm.setBySetMode = true
                            evm.currentSetIndex = 0
                            evm.currentRepCount = 0
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 12))
                        Text("Compteur")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(evm.repCountMode ? .purple : .gray.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.05)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Menu {
                Button { evm.equipmentType = "barbell" }    label: { Label("Barre",       systemImage: "minus.circle.fill") }
                Button { evm.equipmentType = "ez-bar" }     label: { Label("EZ-Bar",      systemImage: "waveform") }
                Button { evm.equipmentType = "dumbbell" }   label: { Label("Haltères",    systemImage: "dumbbell.fill") }
                Button { evm.equipmentType = "machine" }    label: { Label("Machine",     systemImage: "gearshape.fill") }
                Button { evm.equipmentType = "cable" }      label: { Label("Câble",       systemImage: "arrow.up.and.down.circle") }
                Button { evm.equipmentType = "bodyweight" } label: { Label("Poids corps", systemImage: "figure.walk") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: equipmentIcon(evm.equipmentType)).font(.system(size: 11))
                    Text(equipmentLabel).font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(evm.equipmentType == equipmentType ? .gray.opacity(0.6) : .cyan)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background((evm.equipmentType == equipmentType ? Color.white : Color.cyan).opacity(0.07))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var loggedStateDisplay: some View {
        if evm.isSkipped {
            HStack(spacing: 8) {
                Image(systemName: "forward.fill").font(.system(size: 13)).foregroundColor(.gray)
                Text("Sauté").font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
                Spacer()
                Button(action: { evm.isSkipped = false }) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12)).foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(Color.white.opacity(0.04)).cornerRadius(8)
        } else if let r = logResult {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    if isTimeBased {
                        HStack(spacing: 4) {
                            Image(systemName: "timer").font(.system(size: 11)).foregroundColor(.gray)
                            Text(r.reps.split(separator: ",").compactMap { Int($0) }
                                    .map { evm.formatDuration($0) }.joined(separator: ", "))
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "scalemass.fill").font(.system(size: 11)).foregroundColor(.gray)
                            Text(units.format(r.weight)).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        }
                        Text("·").foregroundColor(.gray)
                        HStack(spacing: 4) {
                            Image(systemName: "repeat").font(.system(size: 11)).foregroundColor(.gray)
                            Text(r.reps).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                    if let rpe = r.rpe {
                        Text("·").foregroundColor(.gray)
                        Text("RPE \(String(format: "%.1f", rpe))")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(rpeColor(rpe))
                    }
                    Spacer()
                }
                if !isTimeBased,
                   let previousBest = evm.weightData?.currentWeight,
                   previousBest > 0, r.weight > previousBest {
                    HStack(spacing: 6) {
                        Text("🏆 PR!").font(.system(size: 11, weight: .black)).foregroundColor(.yellow)
                        Text("Nouveau record → \(units.format(r.weight))").font(.system(size: 10)).foregroundColor(.yellow.opacity(0.75))
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.08)).cornerRadius(6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(Color.green.opacity(0.08)).cornerRadius(8)
            .contextMenu {
                Button { evm.isEditing = true } label: { Label("Modifier", systemImage: "pencil") }
                Button(role: .destructive) {
                    logResult = nil
                    evm.resetAfterClear()
                } label: { Label("Réinitialiser", systemImage: "arrow.counterclockwise") }
            }
        }
    }

    @ViewBuilder private var formView: some View {
        if !isTimeBased, evm.lastReps != "—", !evm.lastReps.isEmpty {
            Button {
                triggerImpact(style: .medium)
                evm.fillFromLastSession()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                    Text("Reprendre la dernière séance").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.orange.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.08)).cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        if let p = prescription {
            HStack(spacing: 6) {
                Text(p.label)
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.purple)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.purple.opacity(0.12)).cornerRadius(6)
                if let note = p.note {
                    Text(note).font(.system(size: 10)).foregroundColor(.orange.opacity(0.8)).lineLimit(1)
                }
                Spacer()
            }
        }
        if evm.currentWeight > 0 {
            // W-D3 — only show RECOMMANDÉ when there's a real non-zero weight
            HStack {
                Text("RECOMMANDÉ")
                    .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundColor(.gray)
                Spacer()
                Text(units.format(evm.currentWeight))
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.orange.opacity(0.7))
            }
        } else if !alreadyLogged {
            // W-D3 — first use: neutral placeholder instead of "RECOMMANDÉ 0.0"
            Text("Entre ta charge de départ")
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !isTimeBased && !evm.warmupSets.isEmpty {
            Button {
                withAnimation { evm.showWarmup.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: evm.showWarmup ? "chevron.down" : "flame")
                        .font(.system(size: 11)).foregroundColor(.yellow.opacity(0.7))
                    Text("Échauffement (\(Int(evm.currentWeight)) \(UnitSettings.shared.label))")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.yellow.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            if evm.showWarmup {
                VStack(spacing: 4) {
                    ForEach(evm.warmupSets, id: \.pct) { ws in
                        HStack {
                            Text("\(ws.pct)%")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.yellow.opacity(0.6)).frame(width: 32)
                            Text("1×5 @ \(UnitSettings.shared.format(ws.weight, decimals: 1))")
                                .font(.system(size: 12)).foregroundColor(.gray)
                        }
                    }
                }
                .padding(8).background(Color.yellow.opacity(0.05)).cornerRadius(8)
            }
        }
        if isTimeBased { timeSetRows() } else { setRows() }
        HStack(spacing: 12) {
            Button {
                if evm.sets.count > 1 { evm.sets.removeLast() }
            } label: {
                Image(systemName: "minus.circle").font(.system(size: 20))
                    .foregroundColor(evm.sets.count > 1 ? .red.opacity(0.45) : .gray.opacity(0.2))
            }
            .disabled(evm.sets.count <= 1).buttonStyle(.plain)
            Text("\(evm.sets.count) set\(evm.sets.count > 1 ? "s" : "")")
                .font(.system(size: 11, weight: .medium)).foregroundColor(.gray)
            // W-C1 — show "Max" label and accessibility hint when set limit is reached
            Button {
                if evm.sets.count < 12 { evm.sets.append(SetInput()) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle").font(.system(size: 20))
                        .foregroundColor(evm.sets.count < 12 ? .green.opacity(0.55) : .gray.opacity(0.2))
                    if evm.sets.count >= 12 {
                        Text("Max")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                }
            }
            .disabled(evm.sets.count >= 12)
            .accessibilityLabel(evm.sets.count >= 12 ? "Maximum 12 séries atteint" : "Ajouter une série")
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 2)
        if !isTimeBased, evm.avgWeight != nil { avgTotalRow }
        effortRow
        if showAdvanced {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced = false }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.up.circle").font(.system(size: 10))
                    Text("Masquer").font(.system(size: 10))
                }
                .foregroundColor(.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        if showAdvanced { advancedFields }
        RestTimerBadge(restSeconds: 120, onTap: {
            RestTimerManager.shared.start(seconds: 120, exerciseName: name)
        })
        .padding(.top, 4)
        logSection
        logStatusRow
        // W-B2 — network error banner
        if let err = evm.logError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                Spacer()
                Button {
                    evm.logError = nil
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.2), lineWidth: 1))
        }
    }

    @ViewBuilder private var advancedFields: some View {
        let noteBinding = Binding<String>(get: { exoNote }, set: { saveExoNote($0) })
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bandage").font(.system(size: 11)).foregroundColor(.red.opacity(0.6))
                TextField("Zone douloureuse (optionnel)", text: $evm.painZone)
                    .font(.system(size: 12)).foregroundColor(evm.painZone.isEmpty ? .gray : .red)
            }
            HStack(spacing: 6) {
                Image(systemName: "note").font(.system(size: 11)).foregroundColor(.orange.opacity(0.6))
                TextField("Note de séance (effacée après)", text: $evm.sessionNote, axis: .vertical)
                    .font(.system(size: 12))
                    .foregroundColor(evm.sessionNote.isEmpty ? .gray : .orange)
                    .lineLimit(1...2)
            }
            HStack(spacing: 6) {
                Image(systemName: "note.text").font(.system(size: 11)).foregroundColor(.cyan.opacity(0.6))
                TextField("Notes techniques (persistent)", text: noteBinding, axis: .vertical)
                    .font(.system(size: 12))
                    .foregroundColor(exoNote.isEmpty ? .gray : .cyan)
                    .lineLimit(1...3)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder private var logStatusRow: some View {
        if let status = evm.logStatus {
            HStack(spacing: 6) {
                switch status {
                case .success(let newW):
                    Image(systemName: "arrow.up.circle.fill").foregroundColor(.green)
                    Text("Loggé! \(units.format(newW))")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.green)
                case .stagné:
                    Image(systemName: "equal.circle.fill").foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stagné — même poids").font(.system(size: 13, weight: .semibold)).foregroundColor(.yellow)
                        if let hint = RPEHelper.progressionHint(for: evm.exerciseRPE) {
                            Text(hint).font(.system(size: 11)).foregroundColor(.yellow.opacity(0.7))
                        } else {
                            Text(RPEHelper.feedback(for: evm.exerciseRPE))
                                .font(.system(size: 11)).foregroundColor(.yellow.opacity(0.7))
                        }
                    }
                case .loading:
                    ProgressView().tint(.orange).scaleEffect(0.8)
                    Text("Envoi...").font(.system(size: 13, weight: .semibold)).foregroundColor(.orange)
                case .error(let msg):
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    Text(msg).font(.system(size: 13, weight: .semibold)).foregroundColor(.red)
                }
            }
        }
    }

    @ViewBuilder private var historySection: some View {
        if let history = weightData?.history, !history.isEmpty {
            let historyPerSide: (Double) -> Double = { stored in
                switch evm.equipmentType {
                case "barbell":  return max(0, (stored - 45) / 2)
                case "dumbbell": return stored / 2
                default:         return stored
                }
            }
            let showPerSide = evm.equipmentType == "barbell" || evm.equipmentType == "dumbbell"
            let sparkData: [Double] = history.reversed().compactMap { entry -> Double? in
                guard let w = entry.weight else { return nil }
                return historyPerSide(w)
            }.filter { $0 > 0 }
            let defaultCount = min(3, history.count)
            let visibleEntries = evm.showHistory ? history : Array(history.prefix(defaultCount))
            VStack(spacing: 4) {
                if sparkData.count >= 3 {
                    Chart {
                        ForEach(Array(sparkData.enumerated()), id: \.offset) { i, w in
                            AreaMark(x: .value("", i), y: .value("", w))
                                .foregroundStyle(LinearGradient(
                                    colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.0)],
                                    startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("", i), y: .value("", w))
                                .foregroundStyle(Color.orange.opacity(0.75))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 32)
                }
                if showPerSide {
                    HStack {
                        Text(evm.equipmentType == "barbell" ? "poids par côté" : "par haltère")
                            .font(.system(size: 9)).foregroundColor(.gray.opacity(0.45))
                        Spacer()
                    }
                }
                VStack(spacing: 3) {
                    ForEach(Array(visibleEntries.enumerated()), id: \.offset) { i, entry in
                        HStack(spacing: 6) {
                            Image(systemName: i == 0 ? "clock.arrow.circlepath" : "circle.fill")
                                .font(.system(size: i == 0 ? 10 : 5))
                                .foregroundColor(.gray.opacity(i == 0 ? 0.5 : 0.25))
                            Text(entry.date ?? "—").font(.system(size: 10)).foregroundColor(i == 0 ? .gray : .gray.opacity(0.7))
                            Text("·").foregroundColor(.gray.opacity(0.3)).font(.system(size: 10))
                            Text(units.format(historyPerSide(entry.weight ?? 0)))
                                .font(.system(size: 10, weight: i == 0 ? .semibold : .regular))
                                .foregroundColor(i == 0 ? .white.opacity(0.65) : .white.opacity(0.5))
                            Text(entry.reps ?? "—").font(.system(size: 10)).foregroundColor(i == 0 ? .gray : .gray.opacity(0.6))
                            if let note = entry.note, !note.isEmpty {
                                Text(note).font(.system(size: 9, weight: .medium))
                                    .foregroundColor(note.hasPrefix("+")
                                                     ? (i == 0 ? .green : .green.opacity(0.7))
                                                     : (i == 0 ? .yellow : .yellow.opacity(0.7)))
                            }
                            Spacer()
                        }
                    }
                }
                if history.count > defaultCount {
                    Button(action: { evm.showHistory.toggle() }) {
                        HStack(spacing: 2) {
                            Text(evm.showHistory ? "Moins" : "+\(history.count - defaultCount) sessions").font(.system(size: 9))
                            Image(systemName: evm.showHistory ? "chevron.up" : "chevron.down").font(.system(size: 9))
                        }
                        .foregroundColor(.gray.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var logSection: some View {
        VStack(spacing: 8) {
            if showUndo {
                Button {
                    undoTask?.cancel(); undoTask = nil
                    withAnimation(.easeOut(duration: 0.25)) { showUndo = false }
                    logResult = nil
                    evm.undoLog()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 16))
                        Text("Annuler le log")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("\(undoCountdown)s")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.orange.opacity(0.14))
                    .foregroundColor(.orange)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                VStack(spacing: 4) {
                    holdToLogButton
                    if !evm.canLog {
                        Text(canLogHint)
                            .font(.system(size: 11))
                            .foregroundColor(.gray.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: evm.canLog)
                    }
                }
            }
            if evm.isEditing {
                Button(action: { evm.isEditing = false }) {
                    Text("Annuler")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.gray.opacity(0.5))
                }
            } else {
                Button(action: { confirmSkip = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Sauter")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.red.opacity(0.7))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.red.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var holdToLogButton: some View {
        HoldToLogButton(
            label: evm.isEditing ? "Mettre à jour" : "Logger",
            icon: evm.isEditing ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle.fill",
            isEnabled: evm.canLog,
            logFlash: logFlash
        ) {
            guard evm.canLog else { return }
            doLog()
            withAnimation(.easeInOut(duration: 0.12)) { logFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.2)) { logFlash = false }
            }
        }
    }

    @ViewBuilder private var plateCalculatorSheetView: some View {
        PlateCalculatorSheet(
            initialTotal: plateCalculatorInitialTotal,
            onApply: { perSide in
                let perSideStr = String(format: "%.4g", perSide)
                for i in evm.sets.indices { evm.sets[i].weight = perSideStr }
            }
        )
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var effortRow: some View {
        let rpe = evm.exerciseRPE
        let rir = RPEHelper.rirFromRPE(rpe)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("EFFORT ESTIMÉ")
                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                Spacer()
                Text("RIR \(rir == 4 ? "4+" : "\(rir)")  ·  RPE \(String(format: "%.0f", rpe))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(RPEHelper.color(for: rpe))
            }
            Text(RPEHelper.feedback(for: rpe))
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            if let hint = RPEHelper.progressionHint(for: rpe) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.circle")
                        .font(.system(size: 9)).foregroundColor(.cyan.opacity(0.65))
                    Text(hint)
                        .font(.system(size: 10)).foregroundColor(.cyan.opacity(0.65))
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var mediaSheetView: some View {
        ExerciseMediaSheet(exerciseName: name, gifUrl: mediaGifUrl, muscles: mediaMusclss, tips: nil)
            .presentationDetents([.medium, .large])
    }

    /// Total weight in display units, computed from current set entries or fallback to last known weight.
    private var plateCalculatorInitialTotal: Double {
        let units = UnitSettings.shared
        // Use average of non-empty weight fields if available
        if let avg = evm.avgWeight, avg > 0 {
            let totalLbs = evm.totalWeight(for: units.toStorage(avg))
            return units.display(totalLbs)
        }
        // Fallback: last logged total weight
        if let current = weightData?.currentWeight, current > 0 {
            return units.display(current)
        }
        return 0
    }
}

// MARK: - Floating Rest Timer Card
struct FloatingRestTimerCard: View {
    @ObservedObject private var timer = RestTimerManager.shared

    private var ringColor: Color {
        if timer.progress > 0.6 { return .green }
        if timer.progress > 0.3 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 22) {
            if let name = timer.exerciseName {
                Text(name.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            // Circular clock
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 18)
                    .frame(width: 200, height: 200)

                // Glow arc
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(ringColor.opacity(0.28), style: StrokeStyle(lineWidth: 28, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.progress)
                    .blur(radius: 8)

                // Main arc
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.progress)

                Text(formatTime(timer.remaining))
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            // +10 / -10 adjustment buttons (visible only while running)
            if timer.isRunning {
                HStack(spacing: 16) {
                    Button { timer.adjust(by: -10) } label: {
                        Text("−10s")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ringColor.opacity(0.85))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(ringColor.opacity(0.1))
                            .cornerRadius(20)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ringColor.opacity(0.25), lineWidth: 1))
                    }
                    Button { timer.adjust(by: 10) } label: {
                        Text("+10s")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ringColor.opacity(0.85))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(ringColor.opacity(0.1))
                            .cornerRadius(20)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ringColor.opacity(0.25), lineWidth: 1))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(.easeInOut(duration: 0.2), value: timer.isRunning)
            }

            // Controls
            HStack(spacing: 28) {
                Button { timer.reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.09))
                        .clipShape(Circle())
                }

                Button {
                    if timer.isRunning { timer.stop() } else { timer.resume() }
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 68, height: 68)
                        .background(ringColor)
                        .clipShape(Circle())
                        .shadow(color: ringColor.opacity(0.55), radius: 14, y: 5)
                }
                .animation(.easeInOut(duration: 0.25), value: timer.isRunning)

                // Close — stops and dismisses the timer completely
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        timer.dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 36)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.appBg.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(ringColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 32, x: 0, y: -8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
