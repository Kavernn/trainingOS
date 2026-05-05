import SwiftUI
import Charts

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
    var onToggle: () -> Void = {}
    var nextExerciseName: String? = nil
    var isReplaced: Bool = false
    var originalName: String? = nil
    var onSwap: (() -> Void)? = nil

    @StateObject private var evm: ExerciseViewModel
    @ObservedObject private var units = UnitSettings.shared
    @AppStorage("exo_notes_data") private var exoNotesData: String = "{}"
    @State private var confirmSkip = false
    @State private var showAdvanced = false
    @State private var showPlateCalculator = false
    @State private var showMediaSheet = false
    @State private var mediaGifUrl: String? = nil
    @State private var mediaMusclss: [String] = []
    @State private var mediaFetched = false

    private enum SetFocus: Hashable { case weight(Int); case reps(Int) }
    @FocusState private var setFocus: SetFocus?

    private func nextFocus(from f: SetFocus) -> SetFocus? {
        switch f {
        case .weight(let i): return .reps(i)
        case .reps(let i):   return i + 1 < evm.sets.count ? .weight(i + 1) : nil
        }
    }
    private func prevFocus(from f: SetFocus) -> SetFocus? {
        switch f {
        case .weight(let i): return i > 0 ? .reps(i - 1) : nil
        case .reps(let i):   return .weight(i)
        }
    }

    init(name: String, scheme: String, weightData: WeightData?,
         equipmentType: String = "machine", trackingType: String = "reps",
         bodyWeight: Double = 0, isSecondSession: Bool = false, isBonusSession: Bool = false,
         restSeconds: Int? = nil, prescription: ExercisePrescription? = nil,
         suggestion: ProgressionSuggestion? = nil, hint: String? = nil,
         logResult: Binding<ExerciseLogResult?>, onLogged: (() -> Void)? = nil,
         isExpanded: Bool = false, onToggle: @escaping () -> Void = {},
         nextExerciseName: String? = nil,
         isReplaced: Bool = false, originalName: String? = nil,
         onSwap: (() -> Void)? = nil) {
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
        self.onToggle        = onToggle
        self.nextExerciseName = nextExerciseName
        self.isReplaced      = isReplaced
        self.originalName    = originalName
        self.onSwap          = onSwap
        _evm = StateObject(wrappedValue: ExerciseViewModel(
            name: name, scheme: scheme, weightData: weightData,
            equipmentType: equipmentType, trackingType: trackingType,
            bodyWeight: bodyWeight, isSecondSession: isSecondSession,
            isBonusSession: isBonusSession, restSeconds: restSeconds,
            prescription: prescription, suggestion: suggestion))
    }

    // MARK: - View-layer computed

    private var isTimeBased: Bool { trackingType == "time" }

    private var alreadyLogged: Bool { evm.isLogged || logResult != nil || evm.isSkipped }

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
        if let result = evm.logExercise(alreadyLoggedViaBinding: logResult != nil) {
            logResult = result
            onLogged?()
            triggerNotificationFeedback(.success)
            if isExpanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onToggle()
                }
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
                    .frame(width: 56, alignment: .center)
                VStack(spacing: 1) {
                    Text("RIR")
                        .font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(.cyan.opacity(0.7))
                    Text("avant échec")
                        .font(.system(size: 9)).foregroundColor(.gray.opacity(0.45))
                }
                .frame(width: 70, alignment: .center)
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
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
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
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isDone ? .green : isActive ? .orange : .gray)
                        .frame(width: 28)
                    TextField(evm.perSetHint(for: i), text: $evm.sets[i].weight)
                        .keyboardType(.decimalPad)
                        .focused($setFocus, equals: .weight(i))
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(8).background(Color(hex: "191926")).cornerRadius(8)
                        .disabled(evm.setBySetMode && !isActive && !isDone)
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
                        let repsInvalid = !evm.sets[i].reps.isEmpty && Int(evm.sets[i].reps) == nil
                        TextField(evm.lastRepsParts.indices.contains(i) ? evm.lastRepsParts[i] : "0",
                                  text: $evm.sets[i].reps)
                            .keyboardType(.numberPad)
                            .focused($setFocus, equals: .reps(i))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(repsInvalid ? .red : .white)
                            .multilineTextAlignment(.center)
                            .frame(width: 56)
                            .padding(8)
                            .background(Color(hex: "191926"))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red.opacity(repsInvalid ? 0.7 : 0), lineWidth: 1.5)
                            )
                            .disabled(evm.setBySetMode && !isActive && !isDone)
                    }
                    RPEHelper.RIRTiles(
                        rir: $evm.sets[i].rir,
                        disabled: evm.setBySetMode && !isActive && !isDone
                    )
                    .frame(width: 70)

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
                                setFocus = nil
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
                .background(isActive ? Color.orange.opacity(0.06) : Color.clear)
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.2), value: evm.currentSetIndex)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { v in
                            guard isActive && !evm.repCountMode else { return }
                            guard v.translation.width > 60, abs(v.translation.height) < 50 else { return }
                            withAnimation {
                                triggerImpact(style: .medium)
                                setFocus = nil
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let current = setFocus {
                    Button {
                        setFocus = prevFocus(from: current)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .disabled(prevFocus(from: current) == nil)

                    Button {
                        if let next = nextFocus(from: current) {
                            setFocus = next
                        } else {
                            setFocus = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(nextFocus(from: current) != nil ? "Suivant" : "Terminé")
                                .font(.system(size: 14, weight: .semibold))
                            if nextFocus(from: current) != nil {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(.orange)
                    }

                    Spacer()

                    Button("Terminé") { setFocus = nil }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                }
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
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Status indicator
                    ZStack {
                        Circle()
                            .fill(alreadyLogged
                                  ? Color.green.opacity(0.14)
                                  : Color.orange.opacity(0.11))
                            .frame(width: 34, height: 34)
                        Image(systemName: alreadyLogged ? "checkmark" : "dumbbell")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(alreadyLogged ? .green : .orange)
                    }

                    // Name + scheme
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            if isReplaced {
                                Text("remplacé")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(scheme)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    // Right: logged summary OR chevron
                    if alreadyLogged && !evm.isEditing, let r = logResult {
                        HStack(spacing: 8) {
                            noteIconButton
                            VStack(alignment: .trailing, spacing: 2) {
                                if isTimeBased {
                                    Text(r.reps.split(separator: ",").compactMap { Int($0) }
                                            .map { evm.formatDuration($0) }.first ?? "—")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundColor(.white)
                                } else {
                                    Text(units.format(r.weight))
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundColor(.white)
                                    Text(r.reps)
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                            }
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 8) {
                            noteIconButton
                            if !isTimeBased, evm.currentWeight > 0,
                               evm.lastReps != "—", !evm.lastReps.isEmpty {
                                Button {
                                    triggerImpact(style: .medium)
                                    evm.fillFromLastSession()
                                    doLog()
                                } label: {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(Color.orange.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .trailing, spacing: 1) {
                                    if evm.inputHint > 0 {
                                        Text(units.format(evm.inputHint))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                    Text(evm.lastReps)
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray.opacity(0.45))
                                }
                            }
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray.opacity(0.4))
                                .rotationEffect(.degrees(isExpanded ? 0 : 180))
                                .animation(.easeInOut(duration: 0.22), value: isExpanded)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            // MARK: Expanded content
            if isExpanded {
                Divider()
                    .background(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 12) {

                    // Demo button + swap button + equipment picker
                    HStack {
                        Button {
                            triggerImpact(style: .light)
                            fetchMedia()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "play.circle.fill").font(.system(size: 12))
                                Text("Démo").font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.purple)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        if !alreadyLogged, let onSwap {
                            Button {
                                triggerImpact(style: .light)
                                onSwap()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 11))
                                    Text("Changer").font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.gray.opacity(0.7))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
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
                                Image(systemName: equipmentIcon(evm.equipmentType))
                                    .font(.system(size: 11))
                                Text(equipmentLabel)
                                    .font(.system(size: 12, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(evm.equipmentType == equipmentType ? .gray.opacity(0.6) : .cyan)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background((evm.equipmentType == equipmentType ? Color.white : Color.cyan).opacity(0.07))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Inline coaching chip
                    if logResult == nil, let s = suggestion, s.suggestionType != "maintain" {
                        CoachingChip(suggestion: s)
                    }

                    // Hint technique
                    if let h = hint, !h.isEmpty {
                        Text(h)
                            .font(.system(size: 12, weight: .regular))
                            .italic()
                            .foregroundColor(.gray.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Already-logged state
                    if alreadyLogged && !evm.isEditing {
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
                                Button { evm.isEditing = true } label: {
                                    Label("Modifier", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    logResult = nil
                                    evm.resetAfterClear()
                                } label: {
                                    Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                                }
                            }
                        }
                    } else {
                        // Form (not logged, or editing)

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
                            HStack {
                                Text("RECOMMANDÉ")
                                    .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundColor(.gray)
                                Spacer()
                                Text(units.format(evm.currentWeight))
                                    .font(.system(size: 13, weight: .bold)).foregroundColor(.orange.opacity(0.7))
                            }
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
                            Button {
                                if evm.sets.count < 12 { evm.sets.append(SetInput()) }
                            } label: {
                                Image(systemName: "plus.circle").font(.system(size: 20))
                                    .foregroundColor(evm.sets.count < 12 ? .green.opacity(0.55) : .gray.opacity(0.2))
                            }
                            .disabled(evm.sets.count >= 12).buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.top, 2)

                        if !isTimeBased, evm.avgWeight != nil { avgTotalRow }

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text("EFFORT ESTIMÉ")
                                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                Spacer()
                                let rpe = evm.exerciseRPE
                                let rir = RPEHelper.rirFromRPE(rpe)
                                Text("RIR \(rir == 4 ? "4+" : "\(rir)")  ·  RPE \(String(format: "%.0f", rpe))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(RPEHelper.color(for: rpe))
                            }
                            Text(RPEHelper.feedback(for: evm.exerciseRPE))
                                .font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                            if let hint = RPEHelper.progressionHint(for: evm.exerciseRPE) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.forward.circle")
                                        .font(.system(size: 9)).foregroundColor(.cyan.opacity(0.65))
                                    Text(hint)
                                        .font(.system(size: 10)).foregroundColor(.cyan.opacity(0.65))
                                }
                            }
                        }
                        .padding(.top, 4)

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

                        if showAdvanced {
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
                                    let noteBinding = Binding<String>(get: { exoNote }, set: { saveExoNote($0) })
                                    TextField("Notes techniques (persistent)", text: noteBinding, axis: .vertical)
                                        .font(.system(size: 12))
                                        .foregroundColor(exoNote.isEmpty ? .gray : .cyan)
                                        .lineLimit(1...3)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Rest timer — integrated in form (always 120s, manual start only)
                        RestTimerBadge(restSeconds: 120, onTap: {
                            RestTimerManager.shared.start(seconds: 120, exerciseName: name)
                        })
                        .padding(.top, 4)

                        VStack(spacing: 8) {
                            Button(action: doLog) {
                                HStack(spacing: 8) {
                                    Image(systemName: evm.isEditing ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                    Text(evm.isEditing ? "Mettre à jour" : "Logger")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(evm.canLog ? Color.orange : Color(hex: "1a1a2e"))
                                .foregroundColor(evm.canLog ? .white : .gray)
                                .opacity(evm.canLog ? 1 : 0.6)
                                .cornerRadius(12)
                            }
                            .disabled(!evm.canLog)
                            .buttonStyle(SpringButtonStyle())

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

                    // History
                    if let history = weightData?.history, !history.isEmpty {
                        let historyPerSide: (Double) -> Double = { stored in
                            switch evm.equipmentType {
                            case "barbell":  return max(0, (stored - 45) / 2)
                            case "dumbbell": return stored / 2
                            default:         return stored
                            }
                        }
                        let showPerSide = evm.equipmentType == "barbell" || evm.equipmentType == "dumbbell"
                        VStack(spacing: 4) {
                            let sparkData = history.reversed().compactMap { $0.weight.map(historyPerSide) }.filter { $0 > 0 }
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
                            let defaultCount = min(3, history.count)
                            let visibleEntries = evm.showHistory ? history : Array(history.prefix(defaultCount))
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

                    // Footer — next exercise
                    if let next = nextExerciseName {
                        HStack(spacing: 5) {
                            Text("Suivant")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.gray.opacity(0.3))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.gray.opacity(0.3))
                            Text(next)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray.opacity(0.45))
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(hex: "11111c"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    alreadyLogged
                        ? Color.green.opacity(0.28)
                        : (isExpanded ? Color.orange.opacity(0.18) : Color.white.opacity(0.07)),
                    lineWidth: 1
                )
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if let focus = setFocus {
                    switch focus {
                    case .weight(let i):
                        Button("Reps →") { setFocus = .reps(i) }
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.orange)
                    case .reps(let i):
                        if i < evm.sets.count - 1 {
                            Button("Set \(i + 2) →") { setFocus = .weight(i + 1) }
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(.orange)
                        } else {
                            Button("Ok") { setFocus = nil }
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(.orange)
                        }
                    }
                } else {
                    Button("Ok") { setFocus = nil }
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.orange)
                }
            }
        }
        .onAppear {
            evm.initializeSets()
            if !evm.painZone.isEmpty || !exoNote.isEmpty { showAdvanced = true }
        }
        .onChange(of: evm.setsCount) {
            evm.syncSetsCount()
        }
        .onChange(of: logResult == nil) { _, isNil in
            if isNil { evm.resetAfterClear() }
        }
        .confirmationDialog("Sauter \(name) ?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Sauter cet exercice", role: .destructive) {
                evm.isSkipped = true
                triggerImpact(style: .light)
            }
            Button("Continuer", role: .cancel) {}
        }
        .sheet(isPresented: $showPlateCalculator) {
            PlateCalculatorSheet(
                initialTotal: plateCalculatorInitialTotal,
                onApply: { perSide in
                    let perSideStr = String(format: "%.4g", perSide)
                    for i in evm.sets.indices {
                        evm.sets[i].weight = perSideStr
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMediaSheet) {
            ExerciseMediaSheet(exerciseName: name, gifUrl: mediaGifUrl, muscles: mediaMusclss, tips: nil)
                .presentationDetents([.medium, .large])
        }
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
