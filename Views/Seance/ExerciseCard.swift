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
    @State private var confirmSkip = false
    @State private var showAdvanced = false

    private enum SetFocus: Hashable { case weight(Int); case reps(Int) }
    @FocusState private var setFocus: SetFocus?

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
            if let secs = restSeconds, secs > 0 {
                RestTimerManager.shared.requestAutoStart(secs, exerciseName: name)
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
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: evm.setBySetMode ? "list.number" : "arrow.forward.circle")
                            .font(.system(size: 12))
                        Text("Set à set")
                            .font(.system(size: 9, weight: .semibold))
                    }
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
                        .focused($setFocus, equals: .weight(i))
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(8).background(Color(hex: "191926")).cornerRadius(8)
                        .disabled(evm.setBySetMode && !isActive && !isDone)
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

                    // Indicateur target vs réalisé
                    if let p = prescription, !evm.sets[i].reps.isEmpty, let entered = Int(evm.sets[i].reps) {
                        Image(systemName: entered >= p.repMin ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(entered >= p.repMin ? .green : .orange)
                            .transition(.opacity)
                    }

                    // Badge RPE par set
                    if !evm.setBySetMode || isDone {
                        Button {
                            let current = evm.sets[i].rpe ?? 5
                            evm.sets[i].rpe = current >= 10 ? nil : current + 1
                            triggerImpact(style: .light)
                        } label: {
                            Text(evm.sets[i].rpe.map { "R\(Int($0))" } ?? "RPE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(evm.sets[i].rpe != nil ? rpeColor(evm.sets[i].rpe!) : .gray.opacity(0.3))
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background(Color(hex: "191926"))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    if isActive {
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
                RestTimerBadge(restSeconds: restSeconds, onTap: {})
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
                    VStack(alignment: .leading, spacing: 4) {
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
                    // Badge PR
                    if !isTimeBased, let previousBest = evm.weightData?.currentWeight, previousBest > 0, r.weight > previousBest {
                        HStack(spacing: 6) {
                            Text("🏆 PR!")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.yellow)
                            Text("Nouveau record → \(units.format(r.weight))")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow.opacity(0.75))
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.08))
                        .cornerRadius(6)
                        .transition(.scale.combined(with: .opacity))
                    }
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
                // Reprendre la dernière séance — en premier pour la découvrabilité
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
                        if evm.sets.count < 12 { evm.sets.append(SetInput()) }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(evm.sets.count < 12 ? .green.opacity(0.55) : .gray.opacity(0.2))
                    }
                    .disabled(evm.sets.count >= 12)
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 2)

                if !isTimeBased, evm.avgWeight != nil {
                    avgTotalRow
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("RPE (1–10)")
                        .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(1...10), id: \.self) { val in
                                let selected = Int(evm.exerciseRPE) == val
                                Button {
                                    evm.exerciseRPE = Double(val)
                                    triggerImpact(style: .light)
                                } label: {
                                    Text("\(val)")
                                        .font(.system(size: 13, weight: selected ? .black : .medium))
                                        .foregroundColor(selected ? .black : .gray)
                                        .frame(width: 30, height: 26)
                                        .background(selected ? rpeColor(Double(val)) : Color(hex: "1a1a2e"))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 4)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showAdvanced ? "chevron.up.circle" : "chevron.down.circle")
                            .font(.system(size: 10))
                        Text(showAdvanced ? "Masquer" : "Zone douleur · Notes")
                            .font(.system(size: 10))
                        if !evm.painZone.isEmpty || !exoNote.isEmpty || !evm.sessionNote.isEmpty {
                            Circle().fill(Color.orange).frame(width: 5, height: 5)
                        }
                    }
                    .foregroundColor(.gray.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

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
                            let noteBinding = Binding<String>(
                                get: { exoNote },
                                set: { saveExoNote($0) }
                            )
                            TextField("Notes techniques (persistent)", text: noteBinding, axis: .vertical)
                                .font(.system(size: 12))
                                .foregroundColor(exoNote.isEmpty ? .gray : .cyan)
                                .lineLimit(1...3)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

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
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    } else {
                        Button(action: { confirmSkip = true }) {
                            Text("Sauter cet exercice")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray.opacity(0.4))
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
                    let defaultCount = min(3, history.count)
                    let visibleEntries = evm.showHistory ? history : Array(history.prefix(defaultCount))
                    VStack(spacing: 3) {
                        ForEach(Array(visibleEntries.enumerated()), id: \.offset) { i, entry in
                            HStack(spacing: 6) {
                                Image(systemName: i == 0 ? "clock.arrow.circlepath" : "circle.fill")
                                    .font(.system(size: i == 0 ? 10 : 5))
                                    .foregroundColor(.gray.opacity(i == 0 ? 0.5 : 0.25))
                                Text(entry.date ?? "—")
                                    .font(.system(size: 10))
                                    .foregroundColor(i == 0 ? .gray : .gray.opacity(0.7))
                                Text("·").foregroundColor(.gray.opacity(0.3)).font(.system(size: 10))
                                Text(units.format(entry.weight ?? 0))
                                    .font(.system(size: 10, weight: i == 0 ? .semibold : .regular))
                                    .foregroundColor(i == 0 ? .white.opacity(0.65) : .white.opacity(0.5))
                                Text(entry.reps ?? "—")
                                    .font(.system(size: 10))
                                    .foregroundColor(i == 0 ? .gray : .gray.opacity(0.6))
                                if let note = entry.note, !note.isEmpty {
                                    Text(note)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(note.hasPrefix("+") ? (i == 0 ? .green : .green.opacity(0.7)) : (i == 0 ? .yellow : .yellow.opacity(0.7)))
                                }
                                Spacer()
                            }
                        }
                    }
                    if history.count > defaultCount {
                        Button(action: { evm.showHistory.toggle() }) {
                            HStack(spacing: 2) {
                                Text(evm.showHistory ? "Moins" : "+\(history.count - defaultCount) sessions")
                                    .font(.system(size: 9))
                                Image(systemName: evm.showHistory ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.gray.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(logResult != nil ? Color.green.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(14)
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
    }
}
