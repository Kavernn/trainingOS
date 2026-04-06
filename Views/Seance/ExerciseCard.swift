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
    @Binding var logResult: ExerciseLogResult?
    var onLogged: (() -> Void)? = nil

    @StateObject private var evm: ExerciseViewModel
    @ObservedObject private var units = UnitSettings.shared
    @AppStorage("exo_notes_data") private var exoNotesData: String = "{}"

    init(name: String, scheme: String, weightData: WeightData?,
         equipmentType: String = "machine", trackingType: String = "reps",
         bodyWeight: Double = 0, isSecondSession: Bool = false, isBonusSession: Bool = false,
         restSeconds: Int? = nil, prescription: ExercisePrescription? = nil,
         suggestion: ProgressionSuggestion? = nil,
         logResult: Binding<ExerciseLogResult?>, onLogged: (() -> Void)? = nil) {
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
        self._logResult      = logResult
        self.onLogged        = onLogged
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

    private var equipmentLabel: String {
        switch equipmentType {
        case "barbell":    return "Barre"
        case "ez-bar":     return "EZ-Bar"
        case "dumbbell":   return "Haltères"
        case "bodyweight": return "Poids corps"
        case "cable":      return "Câble"
        default:           return "Machine"
        }
    }

    private var weightColumnLabel: String {
        switch equipmentType {
        case "barbell":    return "POIDS PAR CÔTÉ (\(units.label.uppercased()))"
        case "dumbbell":   return "POIDS PAR HALTÈRE (\(units.label.uppercased()))"
        case "bodyweight": return "LEST (\(units.label.uppercased()))"
        case "ez-bar":     return "POIDS TOTAL (\(units.label.uppercased()))"
        default:           return "POIDS (\(units.label.uppercased()))"
        }
    }

    private func rpeColor(_ v: Double) -> Color {
        if v >= 9 { return .red }
        if v >= 8 { return .orange }
        if v >= 7 { return .yellow }
        return .green
    }

    private func doLog() {
        if let result = evm.logExercise(alreadyLoggedViaBinding: logResult != nil) {
            logResult = result
            onLogged?()
            triggerNotificationFeedback(.success)
        }
    }

    // MARK: - Set rows

    @ViewBuilder private func setRows() -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("SET")
                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                    .frame(width: 28, alignment: .leading)
                Text(weightColumnLabel)
                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                Spacer()
                Text("REPS")
                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                    .frame(width: 56, alignment: .center)
                Text("RIR")
                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.cyan.opacity(0.7))
                    .frame(width: 70, alignment: .center)
                Button {
                    withAnimation {
                        evm.setBySetMode.toggle()
                        if evm.setBySetMode { evm.currentSetIndex = 0 }
                    }
                } label: {
                    Image(systemName: evm.setBySetMode ? "list.number" : "arrow.forward.circle")
                        .font(.system(size: 14))
                        .foregroundColor(evm.setBySetMode ? .orange : .gray.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            ForEach(evm.sets.indices, id: \.self) { i in
                let isActive = evm.setBySetMode && i == evm.currentSetIndex
                let isDone   = evm.setBySetMode && i < evm.currentSetIndex
                HStack(spacing: 8) {
                    Text("S\(i + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isDone ? .green : isActive ? .orange : .gray)
                        .frame(width: 28)
                    TextField(evm.perSetHint(for: i), text: $evm.sets[i].weight)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(8).background(Color(hex: "191926")).cornerRadius(8)
                        .disabled(evm.setBySetMode && !isActive && !isDone)
                    let repsInvalid = !evm.sets[i].reps.isEmpty && Int(evm.sets[i].reps) == nil
                    TextField(evm.lastRepsParts.indices.contains(i) ? evm.lastRepsParts[i] : "0",
                              text: $evm.sets[i].reps)
                        .keyboardType(.numberPad)
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
                    HStack(spacing: 0) {
                        Button { if evm.sets[i].rir > 0 { evm.sets[i].rir -= 1 } } label: {
                            Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .frame(width: 26, height: 36)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Text("\(evm.sets[i].rir)")
                            .font(.system(size: 13, weight: .black)).foregroundColor(.cyan)
                            .frame(width: 18, alignment: .center)
                        Button { if evm.sets[i].rir < 6 { evm.sets[i].rir += 1 } } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                .foregroundColor(.cyan)
                                .frame(width: 26, height: 36)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .frame(width: 70)
                    .padding(.vertical, 0).padding(.horizontal, 0)
                    .background(Color(hex: "191926")).cornerRadius(8)
                    .disabled(evm.setBySetMode && !isActive && !isDone)

                    if isActive {
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
                        .buttonStyle(.plain)
                    } else if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18)).foregroundColor(.green.opacity(0.6))
                    }
                }
                .padding(isActive ? 6 : 0)
                .background(isActive ? Color.orange.opacity(0.06) : Color.clear)
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.2), value: evm.currentSetIndex)
            }
            if !evm.repsStr.isEmpty {
                HStack {
                    Text("→ \(evm.repsStr)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.top, 2)
            }
            if evm.setBySetMode {
                Text("Set \(evm.currentSetIndex + 1)/\(evm.sets.count) — appuie ✓ après chaque set")
                    .font(.system(size: 11)).foregroundColor(.orange.opacity(0.7))
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
        switch equipmentType {
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
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(scheme).font(.system(size: 12)).foregroundColor(.gray)
                }
                Spacer()
                RestTimerBadge(restSeconds: restSeconds, onTap: { evm.showRestTimer = true })
                    .padding(.trailing, 4)
                if let r = logResult {
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(units.format(r.weight))
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(.white)
                            Text(equipmentLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                                .foregroundColor(.green.opacity(0.7))
                        }
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 18))
                            Button(action: { evm.isEditing = true }) {
                                Image(systemName: "pencil.circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                    }
                }
            }

            // Inline coaching chip
            if logResult == nil, let s = suggestion, s.suggestionType != "maintain" {
                CoachingChip(suggestion: s)
            }

            if alreadyLogged && !evm.isEditing {
                if evm.isSkipped {
                    HStack(spacing: 8) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        Text("Sauté")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                        Spacer()
                        Button(action: { evm.isSkipped = false }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                } else if let r = logResult {
                    HStack(spacing: 12) {
                        if isTimeBased {
                            HStack(spacing: 4) {
                                Image(systemName: "timer").font(.system(size: 11)).foregroundColor(.gray)
                                Text(r.reps.split(separator: ",").compactMap { Int($0) }.map { evm.formatDuration($0) }.joined(separator: ", "))
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
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(rpeColor(rpe))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)
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
                // Prescription chip
                if let p = prescription {
                    HStack(spacing: 6) {
                        Text(p.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.purple.opacity(0.12))
                            .cornerRadius(6)
                        if let note = p.note {
                            Text(note)
                                .font(.system(size: 10))
                                .foregroundColor(.orange.opacity(0.8))
                                .lineLimit(1)
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

                if !isTimeBased, evm.lastReps != "—", !evm.lastReps.isEmpty {
                    Button {
                        for i in evm.sets.indices {
                            evm.sets[i].weight = evm.perSetHint(for: i)
                            let parts = evm.lastRepsParts
                            evm.sets[i].reps = parts.indices.contains(i) ? parts[i] : (parts.first ?? "")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                            Text("Reprendre la dernière séance")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.orange.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
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
                                        .font(.system(size: 10, weight: .bold)).foregroundColor(.yellow.opacity(0.6))
                                        .frame(width: 32)
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
                        Image(systemName: "minus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(evm.sets.count > 1 ? .red.opacity(0.45) : .gray.opacity(0.2))
                    }
                    .disabled(evm.sets.count <= 1)
                    .buttonStyle(.plain)
                    Text("\(evm.sets.count) set\(evm.sets.count > 1 ? "s" : "")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    Button {
                        if evm.sets.count < 8 { evm.sets.append(SetInput()) }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(evm.sets.count < 8 ? .green.opacity(0.55) : .gray.opacity(0.2))
                    }
                    .disabled(evm.sets.count >= 8)
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 2)

                if !isTimeBased, evm.avgWeight != nil {
                    avgTotalRow
                }

                HStack(spacing: 6) {
                    Text("RPE")
                        .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                    Spacer()
                    ForEach([6, 7, 8, 9, 10], id: \.self) { val in
                        let selected = Int(evm.exerciseRPE) == val
                        Button {
                            evm.exerciseRPE = Double(val)
                            triggerImpact(style: .light)
                        } label: {
                            Text("\(val)")
                                .font(.system(size: 13, weight: selected ? .black : .medium))
                                .foregroundColor(selected ? .black : .gray)
                                .frame(width: 32, height: 26)
                                .background(selected ? rpeColor(Double(val)) : Color(hex: "1a1a2e"))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)

                HStack(spacing: 6) {
                    Image(systemName: "bandage").font(.system(size: 11)).foregroundColor(.red.opacity(0.6))
                    TextField("Zone douloureuse (optionnel)", text: $evm.painZone)
                        .font(.system(size: 12)).foregroundColor(evm.painZone.isEmpty ? .gray : .red)
                }
                .padding(.top, 2)

                HStack(spacing: 6) {
                    Image(systemName: "note.text").font(.system(size: 11)).foregroundColor(.cyan.opacity(0.6))
                    let noteBinding = Binding<String>(
                        get: { exoNote },
                        set: { saveExoNote($0) }
                    )
                    TextField("Notes techniques (persistent)", text: noteBinding, axis: .vertical)
                        .font(.system(size: 12))
                        .foregroundColor(exoNote.isEmpty ? .gray : .cyan)
                        .lineLimit(1...3)
                }
                .padding(.top, 2)

                HStack {
                    if evm.isEditing {
                        Button(action: { evm.isEditing = false }) {
                            Text("Annuler")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    } else {
                        Button(action: { evm.isSkipped = true; triggerImpact(style: .light) }) {
                            Text("Sauter")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                        }
                    }
                    Spacer()
                    Button(action: doLog) {
                        HStack(spacing: 6) {
                            Image(systemName: evm.isEditing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.up.circle.fill")
                                .font(.system(size: 38))
                            if evm.isEditing {
                                Text("Mettre à jour")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .foregroundColor(evm.canLog ? .orange : .gray)
                    }
                    .disabled(!evm.canLog)
                    .padding(.top, 8)
                }

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
                                Text(evm.exerciseRPE < 7.5 ? "RPE bas — essaie +1 rep" : "RPE élevé — maintiens le poids")
                                    .font(.system(size: 11)).foregroundColor(.yellow.opacity(0.7))
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
                VStack(spacing: 4) {
                    let sparkData = history.reversed().compactMap { $0.weight }.filter { $0 > 0 }
                    if sparkData.count >= 3 {
                        Chart {
                            ForEach(Array(sparkData.enumerated()), id: \.offset) { i, w in
                                AreaMark(x: .value("", i), y: .value("", w))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.0)],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                    .interpolationMethod(.catmullRom)
                                LineMark(x: .value("", i), y: .value("", w))
                                    .foregroundStyle(Color.orange.opacity(0.75))
                                    .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 32)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                            .foregroundColor(.gray.opacity(0.5))
                        Text(history[0].date ?? "—")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text("·").foregroundColor(.gray.opacity(0.3)).font(.system(size: 10))
                        Text(units.format(history[0].weight ?? 0))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.65))
                        Text(history[0].reps ?? "—")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        if let note = history[0].note, !note.isEmpty {
                            Text(note)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(note.hasPrefix("+") ? .green : .yellow)
                        }
                        Spacer()
                        if history.count > 1 {
                            Button(action: { evm.showHistory.toggle() }) {
                                HStack(spacing: 2) {
                                    Text(evm.showHistory ? "Moins" : "+\(history.count - 1)")
                                        .font(.system(size: 9))
                                    Image(systemName: evm.showHistory ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9))
                                }
                                .foregroundColor(.gray.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if evm.showHistory && history.count > 1 {
                        VStack(spacing: 3) {
                            ForEach(Array(history.dropFirst().prefix(4)), id: \.date) { entry in
                                HStack {
                                    Text(entry.date ?? "—").font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
                                    Spacer()
                                    Text(units.format(entry.weight ?? 0)).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.5))
                                    Text(entry.reps ?? "—").font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
                                    if let note = entry.note, !note.isEmpty {
                                        Text(note).font(.system(size: 9)).foregroundColor(note.hasPrefix("+") ? .green.opacity(0.7) : .yellow.opacity(0.7))
                                    }
                                }
                            }
                        }
                        .padding(8).background(Color(hex: "0d0d1a")).cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(logResult != nil ? Color.green.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(14)
        .onAppear {
            evm.initializeSets()
        }
        .onChange(of: evm.setsCount) {
            evm.syncSetsCount()
        }
        .onChange(of: logResult == nil) { _, isNil in
            if isNil { evm.resetAfterClear() }
        }
        .sheet(isPresented: $evm.showRestTimer) {
            RestTimerSheet(autoStartSeconds: restSeconds)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}
