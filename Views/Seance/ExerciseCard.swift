import SwiftUI
import Charts
import AVFoundation
import UserNotifications

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
    @AppStorage("exo_notes_data")          private var exoNotesData: String = "{}"
    @AppStorage("auto_start_rest_timer")   private var autoStartTimer = false
    @AppStorage("show_rir_column")         private var showRIRColumn = false
    @AppStorage("increment_upper_kg")      private var incrementUpperKg: Double = 1.25
    @AppStorage("increment_lower_kg")      private var incrementLowerKg: Double = 2.5
    @AppStorage("increment_upper_lbs")     private var incrementUpperLbs: Double = 2.5
    @AppStorage("increment_lower_lbs")     private var incrementLowerLbs: Double = 5.0
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
    // Previous session note dismissal
    @State private var hidePreviousNote = false

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
        if units.isKg { return isLower ? incrementLowerKg : incrementUpperKg }
        return isLower ? incrementLowerLbs : incrementUpperLbs
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
        if alreadyLogged { return .green.opacity(0.42) }
        if isFocused     { return Color.forge.opacity(0.30) }
        if isExpanded    { return Color.forge.opacity(0.12) }
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
                .font(.appLabel)
                .foregroundColor(hasNote ? Color.forge : .gray.opacity(0.35))
        }
        .buttonStyle(.plain)
    }

    private var equipmentLabel: String {
        switch evm.equipmentType {
        case "barbell":      return "Barre"
        case "ez-bar":       return "EZ-Bar"
        case "dumbbell":     return "Haltères"
        case "bodyweight":   return "Poids corps"
        case "cable":        return "Câble"
        case "cable_double": return "Câble ×2"
        case "press":        return "Presse"
        case "fixed_weight": return "Poids fixe"
        default:             return "Machine"
        }
    }

    private var weightColumnLabel: String {
        switch evm.equipmentType {
        case "barbell":      return "POIDS PAR CÔTÉ (\(units.label.uppercased()))"
        case "dumbbell":     return "POIDS PAR HALTÈRE (\(units.label.uppercased()))"
        case "cable_double": return "POIDS PAR CÂBLE (\(units.label.uppercased()))"
        case "bodyweight":   return "LEST (\(units.label.uppercased()))"
        case "ez-bar":       return "POIDS TOTAL (\(units.label.uppercased()))"
        case "press":        return "CHARGE MACHINE (\(units.label.uppercased()))"
        case "fixed_weight": return "POIDS FIXE (\(units.label.uppercased()))"
        default:             return "POIDS (\(units.label.uppercased()))"
        }
    }

    private func equipmentIcon(_ type: String) -> String {
        switch type {
        case "barbell", "ez-bar":        return "minus.circle.fill"
        case "dumbbell":                 return "dumbbell.fill"
        case "bodyweight":               return "figure.walk"
        case "cable":                    return "arrow.up.and.down.circle"
        case "cable_double":             return "arrow.left.and.right.circle"
        case "press":                    return "arrow.down.to.line.compact"
        case "fixed_weight":             return "scalemass.fill"
        default:                         return "gearshape.fill"
        }
    }

    private func rpeColor(_ v: Double) -> Color { RPEHelper.color(for: v) }

    private func fetchMedia() {
        guard !mediaFetched else { showMediaSheet = true; return }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "\(APIConfig.base)/api/exercise/media?name=\(encoded)") else { return }
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
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                    .font(.appCaption).fontWeight(.bold).tracking(1).foregroundColor(.gray)
                    .frame(width: 28, alignment: .leading)
                Text(weightColumnLabel)
                    .font(.appCaption).fontWeight(.bold).tracking(1).foregroundColor(.gray)
                if evm.equipmentType != "bodyweight" {
                    HStack(spacing: 2) {
                        Button { adjustAllWeights(-1) } label: {
                            Image(systemName: "minus")
                                .font(.appMicro).fontWeight(.bold)
                                .frame(width: 22, height: 18)
                                .foregroundColor(.gray.opacity(0.7))
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        Button { adjustAllWeights(1) } label: {
                            Image(systemName: "plus")
                                .font(.appMicro).fontWeight(.bold)
                                .frame(width: 22, height: 18)
                                .foregroundColor(Color.forge.opacity(0.85))
                                .background(Color.forge.opacity(0.1))
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
                            .font(.appCaption).fontWeight(.semibold)
                            .foregroundColor(Color.forge.opacity(0.8))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.forge.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(evm.equipmentType == "fixed_weight" ? "REPS (OPT.)" : "REPS")
                    .font(.appCaption).fontWeight(.bold).tracking(1).foregroundColor(.gray)
                    .frame(width: 140, alignment: .center)
                // W-C2 — hide RIR column for time-based exercises
                if showRIRColumn && !isTimeBased {
                    HStack(spacing: 3) {
                        VStack(spacing: 1) {
                            Text("RIR")
                                .font(.appCaption).fontWeight(.bold).tracking(1).foregroundColor(.cyan.opacity(0.7))
                            Text("avant échec")
                                .font(.appMicro).foregroundColor(.gray.opacity(0.45))
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
                            .font(.appMicro).fontWeight(.semibold)
                            .foregroundColor(Color.forge.opacity(0.35))
                            .transition(.opacity)
                    }
                    Text("S\(i + 1)")
                        .font(isActive ? .appBody : .appCaption).fontWeight(.bold)
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
                            autoFocus: false
                        )
                        if evm.equipmentType == "barbell" || evm.equipmentType == "dumbbell" || evm.equipmentType == "cable_double" {
                            let rawVal = Double(evm.sets[i].weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                            let totalLbs = evm.totalWeight(for: units.toStorage(rawVal))
                            if totalLbs > 0 {
                                Text("= \(units.format(totalLbs, decimals: 0))")
                                    .font(.appMicro).fontWeight(.medium)
                                    .foregroundColor(.gray.opacity(0.45))
                            }
                        }
                    }
                    if evm.repCountMode && isActive {
                        Text("—")
                            .font(.appBody).fontWeight(.bold)
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
                            minimum: evm.equipmentType == "fixed_weight" ? 0 : 1,
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
                            .font(.appLabel)
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
                                .font(.appTitle)
                                .foregroundColor(Color.forge)
                        }
                        .buttonStyle(SpringButtonStyle(scale: 0.88))
                    } else if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.appHeadline).foregroundColor(.green.opacity(0.6))
                    }
                }
                .padding(isActive ? 6 : 0)
                .background(isActive ? Color.forge.opacity(0.12) : Color.clear)
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
                    Text("→ \(evm.repsStr)").font(.appCaption).foregroundColor(.gray)
                    Spacer()
                }
                .padding(.top, 2)
            }
            if evm.repCountMode {
                RepCounterSection(evm: evm, doLog: doLog)
            } else if evm.setBySetMode {
                Text("Set \(evm.currentSetIndex + 1)/\(evm.sets.count) — appuie ✓ après chaque set")
                    .font(.appCaption).foregroundColor(Color.forge.opacity(0.7))
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder private func timeSetRows() -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { secs in
                    Button { for i in evm.sets.indices { evm.sets[i].duration = secs } } label: {
                        Text(evm.formatDuration(secs))
                            .font(.appCaption).fontWeight(.semibold)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.cyan.opacity(0.15))
                            .foregroundColor(.cyan)
                            .cornerRadius(8)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            HStack {
                Text("SET").font(.appMicro).fontWeight(.bold).tracking(1).foregroundColor(.gray).frame(width: 28, alignment: .leading)
                Text("DURÉE").font(.appMicro).fontWeight(.bold).tracking(1).foregroundColor(.gray)
                Spacer()
            }
            ForEach(evm.sets.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Text("S\(i + 1)").font(.appCaption).fontWeight(.bold).foregroundColor(.gray).frame(width: 28)
                    Button { if evm.sets[i].duration > 5 { evm.sets[i].duration -= 5 } } label: {
                        Image(systemName: "minus.circle.fill").font(.appTitle).foregroundColor(.gray)
                    }.buttonStyle(.plain)
                    Text(evm.formatDuration(evm.sets[i].duration))
                        .font(.appHeadline).fontWeight(.bold).foregroundColor(.appTextPrimary)
                        .frame(minWidth: 64, alignment: .center)
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .background(Color.appSurfaceInset).cornerRadius(8)
                    Button { evm.sets[i].duration += 5 } label: {
                        Image(systemName: "plus.circle.fill").font(.appTitle).foregroundColor(.cyan)
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }
            HStack {
                Text("→ \(evm.sets.map { evm.formatDuration($0.duration) }.joined(separator: ", "))")
                    .font(.appCaption).foregroundColor(.gray)
                Spacer()
            }.padding(.top, 2)
        }
    }

    @ViewBuilder private var avgTotalRow: some View {
        switch evm.equipmentType {
        case "barbell", "dumbbell", "cable_double":
            if let avg = evm.avgWeight {
                let avgLbs = units.toStorage(avg)
                let total  = evm.totalWeight(for: avgLbs)
                HStack {
                    Text("MOY. → TOTAL")
                        .font(.appMicro).fontWeight(.bold).tracking(1).foregroundColor(.gray)
                    Spacer()
                    Text("\(units.format(avgLbs)) → \(units.format(total))")
                        .font(.appLabel).fontWeight(.black).foregroundColor(Color.forge)
                }
                .padding(.top, 2)
            }
        case "bodyweight":
            if bodyWeight > 0 {
                HStack {
                    Text("TOTAL")
                        .font(.appMicro).fontWeight(.bold).tracking(1).foregroundColor(.gray)
                    Spacer()
                    Text(units.format(bodyWeight))
                        .font(.appLabel).fontWeight(.black).foregroundColor(Color.forge)
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
        .opacity(alreadyLogged && !isExpanded ? 0.72 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: alreadyLogged)
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
                        .font(.appLabel).fontWeight(.semibold)
                        .foregroundColor(alreadyLogged ? .green : .orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name).font(.appHeadline).fontWeight(.bold).foregroundColor(.appTextPrimary)
                        if isReplaced {
                            Text("remplacé")
                                .font(.appMicro).fontWeight(.semibold).foregroundColor(Color.forge)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.forge.opacity(0.12)).clipShape(Capsule())
                        }
                        let hasCoaching = logResult == nil && (
                            (suggestion?.suggestionType != "maintain" && suggestion != nil) ||
                            (hint != nil && !(hint?.isEmpty ?? true))
                        )
                        if hasCoaching {
                            Image(systemName: "bolt.fill")
                                .font(.appMicro)
                                .foregroundColor(Color.forge)
                                .padding(3)
                                .background(Color.forge.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    Text(scheme).font(.appCaption).foregroundColor(.gray)
                }
                Spacer()
                headerTrailing
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var headerTrailing: some View {
        if alreadyLogged && !evm.isEditing, let r = logResult {
            HStack(spacing: 8) {
                noteIconButton
                if restTimer.isRunning, restTimer.exerciseName == name {
                    TimelineView(.periodic(from: restTimer.startDate ?? .now, by: 1)) { ctx in
                        let elapsed = max(0, ctx.date.timeIntervalSince(restTimer.startDate ?? .now))
                        let remaining = max(0, restTimer.totalSeconds - Int(elapsed))
                        HStack(spacing: 4) {
                            Image(systemName: "timer").font(.appMicro).foregroundColor(.cyan)
                            Text(evm.formatDuration(remaining))
                                .font(.appCaption).fontWeight(.bold).foregroundColor(.cyan)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Color.cyan.opacity(0.1)).clipShape(Capsule())
                    }
                }
                VStack(alignment: .trailing, spacing: 2) {
                    if isTimeBased {
                        Text(r.reps.split(separator: ",").compactMap { Int($0) }
                                .map { evm.formatDuration($0) }.first ?? "—")
                            .font(.appLabel).fontWeight(.black).foregroundColor(.appTextPrimary)
                    } else {
                        Text(units.format(r.weight)).font(.appLabel).fontWeight(.black).foregroundColor(.appTextPrimary)
                        Text(r.reps).font(.appMicro).foregroundColor(.gray)
                    }
                }
                Button {
                    evm.isEditing = true
                    if !isExpanded { onToggle() }
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.appTitle)
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
                                Image(systemName: "bolt.fill").font(.appMicro).foregroundColor(.cyan)
                                Text(units.format(sw))
                                    .font(.appCaption).fontWeight(.bold).foregroundColor(.cyan)
                            }
                        } else if evm.inputHint > 0 {
                            Text(units.format(evm.inputHint))
                                .font(.appCaption).fontWeight(.semibold).foregroundColor(.white.opacity(0.35))
                        }
                        Text(evm.lastReps).font(.appMicro).foregroundColor(.gray.opacity(0.45))
                    }
                }
                Image(systemName: "chevron.up").font(.appCaption).fontWeight(.semibold)
                    .foregroundColor(.gray.opacity(0.4))
                    .rotationEffect(.degrees(isExpanded ? 0 : 180))
                    .animation(.easeInOut(duration: 0.22), value: isExpanded)
            }
        }
    }

    @ViewBuilder private var expandedContent: some View {
        Divider().background(Color.white.opacity(0.10))
        VStack(alignment: .leading, spacing: 14) {
            expandedTopBar
            if logResult == nil, let s = suggestion, s.suggestionType != "maintain" {
                CoachingChip(suggestion: s)
            }
            if let h = hint, !h.isEmpty {
                Text(h).font(.appCaption)
                    .foregroundColor(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if alreadyLogged && !evm.isEditing { loggedStateDisplay } else { formView }
            historySection
            if let next = nextExerciseName {
                HStack(spacing: 5) {
                    Text("Suivant").font(.appCaption).fontWeight(.semibold).foregroundColor(.gray.opacity(0.3))
                    Image(systemName: "arrow.right").font(.appMicro).fontWeight(.bold).foregroundColor(.gray.opacity(0.3))
                    Text(next).font(.appCaption).fontWeight(.medium).foregroundColor(.gray.opacity(0.45))
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
                    Image(systemName: "checkmark").font(.appMicro).fontWeight(.bold)
                    Text("Sauvegardé").font(.appMicro)
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
                    Image(systemName: "play.circle.fill").font(.appCaption)
                    Text("Démo").font(.appCaption).fontWeight(.semibold)
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
                        Image(systemName: "arrow.left.arrow.right").font(.appCaption)
                        Text("Changer").font(.appCaption).fontWeight(.semibold)
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
                            .font(.appCaption)
                        Text("Set à set")
                            .font(.appMicro).fontWeight(.semibold)
                    }
                    .foregroundColor(evm.setBySetMode && !evm.repCountMode ? Color.forge : .gray.opacity(0.6))
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
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "hand.tap.fill")
                            .font(.appCaption)
                        Text("Compteur")
                            .font(.appMicro).fontWeight(.semibold)
                    }
                    .foregroundColor(evm.repCountMode ? .purple : .gray.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.05)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Menu {
                Button { evm.equipmentType = "barbell" }      label: { Label("Barre",        systemImage: "minus.circle.fill") }
                Button { evm.equipmentType = "ez-bar" }       label: { Label("EZ-Bar",       systemImage: "waveform") }
                Button { evm.equipmentType = "dumbbell" }     label: { Label("Haltères",     systemImage: "dumbbell.fill") }
                Button { evm.equipmentType = "machine" }      label: { Label("Machine",      systemImage: "gearshape.fill") }
                Button { evm.equipmentType = "cable" }        label: { Label("Câble",        systemImage: "arrow.up.and.down.circle") }
                Button { evm.equipmentType = "cable_double" } label: { Label("Câble ×2",     systemImage: "arrow.left.and.right.circle") }
                Button { evm.equipmentType = "bodyweight" }   label: { Label("Poids corps",  systemImage: "figure.walk") }
                Button { evm.equipmentType = "press" }        label: { Label("Presse",       systemImage: "arrow.down.to.line.compact") }
                Button { evm.equipmentType = "fixed_weight" } label: { Label("Poids fixe",   systemImage: "scalemass.fill") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: equipmentIcon(evm.equipmentType)).font(.appCaption)
                    Text(equipmentLabel).font(.appCaption).fontWeight(.semibold)
                    Image(systemName: "chevron.down").font(.appMicro).fontWeight(.semibold)
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
                Image(systemName: "forward.fill").font(.appLabel).foregroundColor(.gray)
                Text("Sauté").font(.appLabel).foregroundColor(.gray)
                Spacer()
                Button(action: { evm.isSkipped = false }) {
                    Image(systemName: "arrow.counterclockwise").font(.appCaption).foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(Color.white.opacity(0.04)).cornerRadius(8)
        } else if let r = logResult {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    if isTimeBased {
                        HStack(spacing: 4) {
                            Image(systemName: "timer").font(.appCaption).foregroundColor(.gray)
                            Text(r.reps.split(separator: ",").compactMap { Int($0) }
                                    .map { evm.formatDuration($0) }.joined(separator: ", "))
                                .font(.appLabel).fontWeight(.semibold).foregroundColor(.appTextPrimary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "scalemass.fill").font(.appCaption).foregroundColor(.gray)
                            Text(units.format(r.weight)).font(.appLabel).fontWeight(.semibold).foregroundColor(.appTextPrimary)
                        }
                        Text("·").foregroundColor(.gray)
                        HStack(spacing: 4) {
                            Image(systemName: "repeat").font(.appCaption).foregroundColor(.gray)
                            Text(r.reps).font(.appLabel).fontWeight(.semibold).foregroundColor(.appTextPrimary)
                        }
                    }
                    if let rpe = r.rpe {
                        Text("·").foregroundColor(.gray)
                        Text("RPE \(String(format: "%.1f", rpe))")
                            .font(.appLabel).fontWeight(.bold).foregroundColor(rpeColor(rpe))
                    }
                    Spacer()
                }
                if !isTimeBased,
                   let previousBest = evm.weightData?.currentWeight,
                   previousBest > 0, r.weight > previousBest {
                    HStack(spacing: 6) {
                        Text("🏆 PR!").font(.appCaption).fontWeight(.black).foregroundColor(.yellow)
                        Text("Nouveau record → \(units.format(r.weight))").font(.appMicro).foregroundColor(.yellow.opacity(0.75))
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
        // Rappel note dernière séance
        if let prev = evm.weightData?.history?.first(where: { ($0.sessionNotes ?? "").isEmpty == false }),
           let prevNote = prev.sessionNotes, !hidePreviousNote {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "note.text").font(.appCaption).foregroundColor(Color.forge.opacity(0.7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dernière séance · \(prev.date ?? "")")
                        .font(.appMicro).fontWeight(.semibold).foregroundColor(Color.forge.opacity(0.6))
                    Text(prevNote.count > 120 ? String(prevNote.prefix(120)) + "…" : prevNote)
                        .font(.appCaption).foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { withAnimation { hidePreviousNote = true } } label: {
                    Image(systemName: "xmark").font(.appMicro).foregroundColor(.gray.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.forge.opacity(0.07))
            .cornerRadius(8)
        }
        if !isTimeBased, evm.lastReps != "—", !evm.lastReps.isEmpty {
            Button {
                triggerImpact(style: .medium)
                evm.fillFromLastSession()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise").font(.appCaption)
                    Text("Reprendre la dernière séance").font(.appCaption).fontWeight(.semibold)
                }
                .foregroundColor(Color.forge.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.forge.opacity(0.08)).cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        if let p = prescription {
            HStack(spacing: 6) {
                Text(p.label)
                    .font(.appCaption).fontWeight(.bold).foregroundColor(.purple)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.purple.opacity(0.12)).cornerRadius(6)
                if let note = p.note {
                    Text(note).font(.appMicro).foregroundColor(Color.forge.opacity(0.8)).lineLimit(1)
                }
                Spacer()
            }
        }
        if evm.currentWeight > 0 {
            // W-D3 — only show RECOMMANDÉ when there's a real non-zero weight
            HStack {
                Text("RECOMMANDÉ")
                    .font(.appMicro).fontWeight(.semibold).tracking(1).foregroundColor(.gray)
                Spacer()
                Text(units.format(evm.currentWeight))
                    .font(.appLabel).fontWeight(.bold).foregroundColor(Color.forge.opacity(0.7))
            }
        } else if !alreadyLogged {
            // W-D3 — first use: neutral placeholder instead of "RECOMMANDÉ 0.0"
            Text("Entre ta charge de départ")
                .font(.appCaption)
                .foregroundColor(.gray.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !isTimeBased && !evm.warmupSets.isEmpty {
            Button {
                withAnimation { evm.showWarmup.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: evm.showWarmup ? "chevron.down" : "flame")
                        .font(.appCaption).foregroundColor(.yellow.opacity(0.7))
                    Text("Échauffement (\(Int(evm.currentWeight)) \(UnitSettings.shared.label))")
                        .font(.appCaption).fontWeight(.medium).foregroundColor(.yellow.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            if evm.showWarmup {
                VStack(spacing: 4) {
                    ForEach(evm.warmupSets, id: \.pct) { ws in
                        HStack {
                            Text("\(ws.pct)%")
                                .font(.appMicro).fontWeight(.bold).foregroundColor(.yellow.opacity(0.6)).frame(width: 32)
                            Text("1×5 @ \(UnitSettings.shared.format(ws.weight, decimals: 1))")
                                .font(.appCaption).foregroundColor(.gray)
                        }
                    }
                }
                .padding(8).background(Color.yellow.opacity(0.05)).cornerRadius(8)
            }
        }
        if isTimeBased {
            EnduranceTimerSection(
                sets: evm.sets,
                exerciseName: name,
                onSetCompleted: { idx, dur in
                    guard idx < evm.sets.count else { return }
                    evm.sets[idx].duration = dur
                }
            )
        } else { setRows() }
        HStack(spacing: 12) {
            Button {
                if evm.sets.count > 1 { evm.sets.removeLast() }
            } label: {
                Image(systemName: "minus.circle").font(.appTitle)
                    .foregroundColor(evm.sets.count > 1 ? .red.opacity(0.45) : .gray.opacity(0.2))
            }
            .disabled(evm.sets.count <= 1).buttonStyle(.plain)
            Text("\(evm.sets.count) set\(evm.sets.count > 1 ? "s" : "")")
                .font(.appCaption).fontWeight(.medium).foregroundColor(.gray)
            // W-C1 — show "Max" label and accessibility hint when set limit is reached
            Button {
                if evm.sets.count < 12 { evm.sets.append(SetInput()) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle").font(.appTitle)
                        .foregroundColor(evm.sets.count < 12 ? .green.opacity(0.55) : .gray.opacity(0.2))
                    if evm.sets.count >= 12 {
                        Text("Max")
                            .font(.appMicro).fontWeight(.medium)
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
        // Note de séance — toujours visible, sauvegardée au log
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "note").font(.appCaption)
                .foregroundColor(evm.sessionNote.isEmpty ? .gray.opacity(0.35) : Color.forge.opacity(0.7))
                .padding(.top, 1)
            TextField("Note de séance…", text: $evm.sessionNote, axis: .vertical)
                .font(.appCaption)
                .foregroundColor(evm.sessionNote.isEmpty ? .gray : Color.forge)
                .lineLimit(1...3)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(evm.sessionNote.isEmpty ? Color.clear : Color.forge.opacity(0.06))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
            evm.sessionNote.isEmpty ? Color.white.opacity(0.05) : Color.forge.opacity(0.15), lineWidth: 1))
        if showAdvanced {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced = false }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.up.circle").font(.appMicro)
                    Text("Masquer").font(.appMicro)
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
                    .font(.appLabel)
                    .foregroundColor(.red)
                Text(err)
                    .font(.appCaption).fontWeight(.medium)
                    .foregroundColor(.red)
                Spacer()
                Button {
                    evm.logError = nil
                } label: {
                    Image(systemName: "xmark").font(.appMicro).foregroundColor(.gray)
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
                Image(systemName: "bandage").font(.appCaption).foregroundColor(.red.opacity(0.6))
                TextField("Zone douloureuse (optionnel)", text: $evm.painZone)
                    .font(.appCaption).foregroundColor(evm.painZone.isEmpty ? .gray : .red)
            }
            HStack(spacing: 6) {
                Image(systemName: "note.text").font(.appCaption).foregroundColor(.cyan.opacity(0.6))
                TextField("Notes techniques (persistantes)", text: noteBinding, axis: .vertical)
                    .font(.appCaption)
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
                        .font(.appLabel).fontWeight(.semibold).foregroundColor(.green)
                case .stagné:
                    Image(systemName: "equal.circle.fill").foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stagné — même poids").font(.appLabel).fontWeight(.semibold).foregroundColor(.yellow)
                        if let hint = RPEHelper.progressionHint(for: evm.exerciseRPE) {
                            Text(hint).font(.appCaption).foregroundColor(.yellow.opacity(0.7))
                        } else {
                            Text(RPEHelper.feedback(for: evm.exerciseRPE))
                                .font(.appCaption).foregroundColor(.yellow.opacity(0.7))
                        }
                    }
                case .loading:
                    ProgressView().tint(Color.forge).scaleEffect(0.8)
                    Text("Envoi...").font(.appLabel).fontWeight(.semibold).foregroundColor(Color.forge)
                case .error(let msg):
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    Text(msg).font(.appLabel).fontWeight(.semibold).foregroundColor(.red)
                }
            }
        }
    }

    @ViewBuilder private var historySection: some View {
        if let history = weightData?.history, !history.isEmpty {
            let historyPerSide: (Double) -> Double = { stored in
                switch evm.equipmentType {
                case "barbell":                  return max(0, (stored - 45) / 2)
                case "dumbbell", "cable_double": return stored / 2
                default:                         return stored
                }
            }
            let showPerSide = evm.equipmentType == "barbell"
                           || evm.equipmentType == "dumbbell"
                           || evm.equipmentType == "cable_double"
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
                                    colors: [Color.forge.opacity(0.35), Color.forge.opacity(0.0)],
                                    startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("", i), y: .value("", w))
                                .foregroundStyle(Color.forge.opacity(0.75))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 32)
                }
                if showPerSide {
                    HStack {
                        Text(evm.equipmentType == "barbell" ? "poids par côté" : "par haltère")
                            .font(.appMicro).foregroundColor(.gray.opacity(0.45))
                        Spacer()
                    }
                }
                VStack(spacing: 3) {
                    ForEach(Array(visibleEntries.enumerated()), id: \.offset) { i, entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: i == 0 ? "clock.arrow.circlepath" : "circle.fill")
                                    .font(.system(size: i == 0 ? 10 : 5))
                                    .foregroundColor(.gray.opacity(i == 0 ? 0.5 : 0.25))
                                Text(entry.date ?? "—").font(.appMicro).foregroundColor(i == 0 ? .gray : .gray.opacity(0.7))
                                if let note = entry.note, !note.isEmpty {
                                    Text(note).font(.appMicro).fontWeight(.medium)
                                        .foregroundColor(note.hasPrefix("+")
                                                         ? (i == 0 ? .green : .green.opacity(0.7))
                                                         : (i == 0 ? .yellow : .yellow.opacity(0.7)))
                                }
                                Spacer()
                            }
                            if let sets = entry.sets, !sets.isEmpty {
                                let repParts = (entry.reps ?? "").split(separator: ",").map(String.init)
                                ForEach(Array(sets.enumerated()), id: \.offset) { j, s in
                                    let reps = repParts.indices.contains(j) ? repParts[j] : "—"
                                    HStack(spacing: 4) {
                                        Text("S\(j + 1)")
                                            .font(.appMicro).fontWeight(.bold)
                                            .foregroundColor(.gray.opacity(0.4))
                                            .frame(width: 16)
                                        Text(units.format(historyPerSide(s.weight)))
                                            .font(.appMicro).fontWeight(j == 0 && i == 0 ? .semibold : .regular)
                                            .foregroundColor(i == 0 ? .white.opacity(0.65) : .white.opacity(0.5))
                                        Text("×")
                                            .font(.appMicro).foregroundColor(.gray.opacity(0.35))
                                        Text(reps)
                                            .font(.appMicro).foregroundColor(i == 0 ? .gray : .gray.opacity(0.6))
                                    }
                                    .padding(.leading, 16)
                                }
                            } else {
                                HStack(spacing: 6) {
                                    Text("·").foregroundColor(.gray.opacity(0.3)).font(.appMicro)
                                    Text(units.format(historyPerSide(entry.weight ?? 0)))
                                        .font(.appMicro).fontWeight(i == 0 ? .semibold : .regular)
                                        .foregroundColor(i == 0 ? .white.opacity(0.65) : .white.opacity(0.5))
                                    Text(entry.reps ?? "—").font(.appMicro).foregroundColor(i == 0 ? .gray : .gray.opacity(0.6))
                                }
                                .padding(.leading, 16)
                            }
                        }
                    }
                }
                if history.count > defaultCount {
                    Button(action: { evm.showHistory.toggle() }) {
                        HStack(spacing: 2) {
                            Text(evm.showHistory ? "Moins" : "+\(history.count - defaultCount) sessions").font(.appMicro)
                            Image(systemName: evm.showHistory ? "chevron.up" : "chevron.down").font(.appMicro)
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
                            .font(.appBody)
                        Text("Annuler le log")
                            .font(.appBody).fontWeight(.semibold)
                        Spacer()
                        Text("\(undoCountdown)s")
                            .font(.appCaption).fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.forge.opacity(0.14))
                    .foregroundColor(Color.forge)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.forge.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                VStack(spacing: 4) {
                    holdToLogButton
                    if !evm.canLog {
                        Text(canLogHint)
                            .font(.appCaption)
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
                        .font(.appCaption).fontWeight(.medium).foregroundColor(.gray.opacity(0.5))
                }
            } else {
                Button(action: { confirmSkip = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "forward.fill")
                            .font(.appMicro).fontWeight(.bold)
                        Text("Sauter")
                            .font(.appCaption).fontWeight(.semibold)
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
                    .font(.appMicro).fontWeight(.bold).tracking(1).foregroundColor(.gray)
                Spacer()
                Text("RIR \(rir == 4 ? "4+" : "\(rir)")  ·  RPE \(String(format: "%.0f", rpe))")
                    .font(.appMicro).fontWeight(.bold)
                    .foregroundColor(RPEHelper.color(for: rpe))
            }
            Text(RPEHelper.feedback(for: rpe))
                .font(.appCaption).foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            if let hint = RPEHelper.progressionHint(for: rpe) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.circle")
                        .font(.appMicro).foregroundColor(.cyan.opacity(0.65))
                    Text(hint)
                        .font(.appMicro).foregroundColor(.cyan.opacity(0.65))
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

// MARK: - Rep Counter Section (isolated so only this view re-renders on each tap)

private struct RepCounterSection: View {
    @ObservedObject var evm: ExerciseViewModel
    let doLog: () -> Void

    @State private var count: Int = 0

    var body: some View {
        let isLastSet = evm.currentSetIndex == evm.sets.count - 1
        VStack(spacing: 16) {
            Divider().background(Color.purple.opacity(0.2)).padding(.top, 4)

            Text("SET \(evm.currentSetIndex + 1) / \(evm.sets.count)")
                .font(.appCaption).fontWeight(.bold).tracking(2)
                .foregroundColor(.purple.opacity(0.7))

            Text("\(count)")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundColor(.purple)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: count)
                .frame(minWidth: 100)

            HStack(spacing: 36) {
                Button {
                    count = max(0, count - 1)
                    triggerImpact(style: .light)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.gray.opacity(0.45))
                }
                .buttonStyle(.plain)

                Button {
                    count += 1
                    triggerImpact(style: .medium)
                } label: {
                    ZStack {
                        Circle().fill(Color.purple.opacity(0.12)).frame(width: 112, height: 112)
                        Circle().stroke(Color.purple.opacity(0.35), lineWidth: 2).frame(width: 112, height: 112)
                        VStack(spacing: 4) {
                            Image(systemName: "hand.tap.fill").font(.appTitle)
                            Text("REP").font(.appLabel).fontWeight(.black)
                        }
                        .foregroundColor(.purple)
                    }
                }
                .buttonStyle(SpringButtonStyle(scale: 0.92))

                Button {
                    count = 0
                    triggerImpact(style: .light)
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.gray.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            Button {
                let allDone = evm.confirmSet(reps: count)
                count = 0
                triggerImpact(style: .medium)
                if allDone { doLog() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isLastSet ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.appHeadline)
                    Text(isLastSet ? "Logger l'exercice" : "Set terminé →")
                        .font(.appBody).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(count > 0 ? (isLastSet ? Color.forge : Color.purple) : Color.gray.opacity(0.1))
                .foregroundColor(count > 0 ? .white : .gray)
                .cornerRadius(12)
            }
            .disabled(count == 0)
            .buttonStyle(SpringButtonStyle())
        }
        .padding(.top, 4)
        .onChange(of: evm.currentSetIndex) { _ in count = 0 }
    }
}

// MARK: - Endurance Timer

private enum EnduranceTimerState {
    case idle, countdown(Int), running, warning(Int), finished, paused
}

struct EnduranceTimerSection: View {
    let sets: [SetInput]
    let exerciseName: String
    let onSetCompleted: (Int, Int) -> Void   // (setIndex, durationSec)

    @State private var timerState: EnduranceTimerState = .idle
    @State private var currentSetIdx: Int = 0
    @State private var targetDur: Int = 60
    @State private var remaining: Int = 60
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var beepPlayer: AVAudioPlayer? = nil
    @State private var flashGreen: Bool = false

    private let presets = [20, 30, 45, 60, 90, 120, 180]
    private var totalSets: Int { max(1, sets.count) }
    private var isLastSet: Bool { currentSetIdx >= totalSets - 1 }
    private var filledDots: Int {
        if case .finished = timerState { return currentSetIdx + 1 }
        return currentSetIdx
    }

    var body: some View {
        VStack(spacing: 14) {
            if case .idle = timerState { presetBar }
            setHeader
            mainDisplay
            controls
        }
        .padding(.vertical, 4)
        .onAppear { restoreOrSync() }
        .onDisappear { timerTask?.cancel(); timerTask = nil }
    }

    // MARK: Sub-views

    private var presetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { s in
                    Button {
                        targetDur = s; remaining = s
                    } label: {
                        Text(fmt(s))
                            .font(.appCaption).fontWeight(.semibold)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(targetDur == s ? Color.cyan.opacity(0.28) : Color.cyan.opacity(0.10))
                            .foregroundColor(.cyan)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(targetDur == s ? Color.cyan.opacity(0.55) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var setHeader: some View {
        HStack {
            Text("SET \(currentSetIdx + 1) / \(totalSets)")
                .font(.appMicro).fontWeight(.bold).tracking(1.5).foregroundColor(.gray)
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<totalSets, id: \.self) { i in
                    Circle()
                        .fill(i < filledDots ? Color.green : Color.white.opacity(0.12))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    @ViewBuilder private var mainDisplay: some View {
        switch timerState {
        case .idle:
            VStack(spacing: 6) {
                Text(fmt(targetDur))
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                Text("durée cible")
                    .font(.appCaption).foregroundColor(.gray)
            }
            .frame(height: 110)

        case .countdown(let n):
            Text("\(n)")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundColor(.appTextPrimary)
                .contentTransition(.numericText())
                .frame(height: 110)

        case .running:
            arcTimer(color: .cyan)

        case .warning(let n):
            Text("\(n)")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundColor(n <= 3 ? .red : Color.forge)
                .contentTransition(.numericText())
                .frame(height: 110)

        case .finished:
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44)).foregroundColor(.green)
                Text(fmt(targetDur))
                    .font(.appHeadline).fontWeight(.black).foregroundColor(.appTextPrimary)
                Text(isLastSet ? "Tous les sets complétés ✓" : "Set \(currentSetIdx + 1) complété")
                    .font(.appCaption).foregroundColor(.gray)
            }
            .frame(height: 110)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(flashGreen ? 0.7 : 0), lineWidth: 2)
                    .animation(.easeOut(duration: 0.9), value: flashGreen)
            )

        case .paused:
            arcTimer(color: .white.opacity(0.35))
        }
    }

    private func arcTimer(color: Color) -> some View {
        let progress = targetDur > 0 ? Double(remaining) / Double(targetDur) : 1.0
        return ZStack {
            Circle().stroke(color.opacity(0.12), lineWidth: 8)
            Circle().trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: remaining)
            VStack(spacing: 4) {
                Text(fmt(remaining))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(color == Color.cyan ? .white : .gray)
                    .contentTransition(.numericText())
                if case .paused = timerState {
                    Text("en pause").font(.appCaption).foregroundColor(.gray)
                }
            }
        }
        .frame(width: 130, height: 130)
    }

    @ViewBuilder private var controls: some View {
        switch timerState {
        case .idle:
            Button { startCountdown() } label: {
                Label("Démarrer", systemImage: "play.fill")
                    .font(.appLabel).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.cyan).cornerRadius(12)
            }
            .buttonStyle(SpringButtonStyle())

        case .countdown:
            EmptyView()

        case .running, .warning:
            HStack(spacing: 16) {
                iconBtn("pause.fill", fg: .white, bg: Color.white.opacity(0.1)) { pauseTimer() }
                iconBtn("stop.fill",  fg: .red.opacity(0.8), bg: Color.red.opacity(0.1)) { stopTimer() }
            }

        case .paused:
            HStack(spacing: 12) {
                Button { resumeTimer() } label: {
                    Label("Reprendre", systemImage: "play.fill")
                        .font(.appLabel).fontWeight(.semibold).foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Color.cyan).cornerRadius(12)
                }
                .buttonStyle(SpringButtonStyle())
                iconBtn("stop.fill", fg: .red.opacity(0.8), bg: Color.red.opacity(0.1)) { stopTimer() }
            }

        case .finished:
            if !isLastSet {
                Button { nextSet() } label: {
                    Label("Set \(currentSetIdx + 2)", systemImage: "arrow.right.circle.fill")
                        .font(.appLabel).fontWeight(.semibold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.green).cornerRadius(12)
                }
                .buttonStyle(SpringButtonStyle())
            } else {
                Text("Tous les sets terminés — logger ci-dessous")
                    .font(.appCaption).foregroundColor(.green.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
    }

    private func iconBtn(_ icon: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.appHeadline)
                .foregroundColor(fg)
                .frame(width: 52, height: 52).background(bg).clipShape(Circle())
        }
        .buttonStyle(SpringButtonStyle())
    }

    // MARK: Timer logic

    // UserDefaults keys scoped per exercise
    private var udStart:           String { "et_start_\(exerciseName)" }
    private var udTarget:          String { "et_target_\(exerciseName)" }
    private var udSetIdx:          String { "et_setIdx_\(exerciseName)" }
    private var udPausedRemaining: String { "et_paused_\(exerciseName)" }
    private var udLastDur:         String { "et_lastdur_\(exerciseName)" }
    private var notifId:           String { "et_notif_\(exerciseName)" }

    private func syncTarget() {
        guard currentSetIdx < sets.count else { return }
        let prescribed = sets[currentSetIdx].duration
        if prescribed > 0 {
            targetDur = prescribed
        } else {
            // Fall back to last completed duration for this exercise, then preset default
            let saved = UserDefaults.standard.integer(forKey: udLastDur)
            targetDur = saved > 0 ? saved : 60
        }
        remaining = targetDur
    }

    private func saveRunningState() {
        let ud = UserDefaults.standard
        ud.set(Date(), forKey: udStart)
        ud.set(targetDur, forKey: udTarget)
        ud.set(currentSetIdx, forKey: udSetIdx)
        ud.removeObject(forKey: udPausedRemaining)
    }

    private func savePausedState() {
        let ud = UserDefaults.standard
        ud.set(remaining, forKey: udPausedRemaining)
        ud.set(targetDur, forKey: udTarget)
        ud.set(currentSetIdx, forKey: udSetIdx)
        ud.removeObject(forKey: udStart)
    }

    private func clearTimerState() {
        let ud = UserDefaults.standard
        [udStart, udTarget, udSetIdx, udPausedRemaining].forEach { ud.removeObject(forKey: $0) }
    }

    private func scheduleNotification(in seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = exerciseName
        content.body  = "Timer terminé — \(fmt(targetDur)) ✓"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        let req = UNNotificationRequest(identifier: notifId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notifId])
    }

    private func restoreOrSync() {
        let ud = UserDefaults.standard
        // Paused state takes priority (remaining is explicit)
        let pausedRem = ud.integer(forKey: udPausedRemaining)
        if pausedRem > 0 {
            currentSetIdx = ud.integer(forKey: udSetIdx)
            targetDur     = ud.integer(forKey: udTarget)
            remaining     = pausedRem
            timerState    = .paused
            return
        }
        // Running state: compute elapsed since start
        guard let startDate = ud.object(forKey: udStart) as? Date else {
            syncTarget(); return
        }
        let savedTarget = ud.integer(forKey: udTarget)
        guard savedTarget > 0 else { syncTarget(); return }
        currentSetIdx = ud.integer(forKey: udSetIdx)
        targetDur = savedTarget
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let rem = savedTarget - elapsed
        if rem > 0 {
            remaining  = rem
            timerState = .running
            timerTask  = Task { @MainActor in await runLoop() }
        } else {
            // Finished while in background — notification already fired
            remaining = 0
            clearTimerState()
            onSetCompleted(currentSetIdx, savedTarget)
            timerState = .finished
            withAnimation { flashGreen = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { flashGreen = false } }
        }
    }

    private func startCountdown() {
        triggerImpact(style: .light)
        saveRunningState()
        scheduleNotification(in: targetDur + 3)   // +3 for countdown
        timerTask = Task { @MainActor in
            for i in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                timerState = .countdown(i)
                beepPlayer = makeBeep(hz: 800, duration: 0.1)
                beepPlayer?.play()
                triggerImpact(style: .light)
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
            guard !Task.isCancelled else { return }
            remaining  = targetDur
            timerState = .running
            await runLoop()
        }
    }

    private func runLoop() async {
        while remaining > 0 {
            guard !Task.isCancelled else { return }
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            // Sons AVANT décrément — inclut remaining=1 (manquant avec l'ordre inverse)
            if remaining <= 5 {
                beepPlayer = makeBeep(hz: 1000, duration: 0.08)
                beepPlayer?.play()
                triggerImpact(style: .medium)
            }
            remaining -= 1
            if remaining > 0 && remaining <= 5 {
                timerState = .warning(remaining)
            } else if remaining > 5 {
                timerState = .running
            }
        }
        finish()
    }

    private func finish() {
        beepPlayer = makeBeep(hz: 1200, duration: 0.35)
        beepPlayer?.play()
        triggerNotificationFeedback(.success)
        withAnimation { flashGreen = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { flashGreen = false } }
        clearTimerState()
        cancelNotification()
        UserDefaults.standard.set(targetDur, forKey: udLastDur)
        onSetCompleted(currentSetIdx, targetDur)
        timerState = .finished
    }

    private func pauseTimer() {
        timerTask?.cancel(); timerTask = nil
        triggerImpact(style: .light)
        cancelNotification()
        savePausedState()
        timerState = .paused
    }

    private func resumeTimer() {
        triggerImpact(style: .light)
        timerState = .running
        saveRunningState()
        scheduleNotification(in: remaining)
        timerTask = Task { @MainActor in await runLoop() }
    }

    private func stopTimer() {
        timerTask?.cancel(); timerTask = nil
        triggerImpact(style: .medium)
        cancelNotification()
        clearTimerState()
        remaining  = targetDur
        timerState = .idle
    }

    private func nextSet() {
        currentSetIdx += 1
        syncTarget()
        timerState = .idle
        triggerImpact(style: .light)
    }

    private func fmt(_ secs: Int) -> String {
        guard secs >= 60 else { return "\(secs)s" }
        let m = secs / 60; let s = secs % 60
        return s > 0 ? "\(m):\(String(format: "%02d", s))" : "\(m):00"
    }
}
