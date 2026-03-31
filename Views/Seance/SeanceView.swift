import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import Charts

struct SeanceView: View {
    @StateObject private var vm = SeanceViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()

                if vm.isLoading {
                    ProgressView().tint(.orange)
                } else if let data = vm.seanceData {
                    seanceContent(data: data)
                } else if let err = vm.error {
                    ErrorView(message: err) { Task { await vm.load() } }
                }
            }
            .navigationTitle("Séance")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private func seanceContent(data: SeanceData) -> some View {
        if data.alreadyLogged {
            AlreadyLoggedSeanceView(data: data, vm: vm)
        } else if data.today == "Yoga / Tai Chi" || data.today == "Recovery" {
            SpecialSeanceView(sessionType: data.today, vm: vm)
        } else {
            WorkoutSeanceView(data: data, vm: vm)
        }
    }
}

// MARK: - Already Logged → Recap + Tomorrow Preview + Extra
struct AlreadyLoggedSeanceView: View {
    let data: SeanceData
    @ObservedObject var vm: SeanceViewModel
    @State private var showExtra = false
    @State private var confirmReset = false
    @State private var animateHeader = false
    @State private var showConfetti = false

    var todaySession: SessionEntry? {
        APIService.shared.dashboard?.sessions[data.todayDate]
    }

    var sessionColor: Color {
        switch data.today {
        case "Push A", "Push B":           return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                       return .yellow
        case "Yoga / Tai Chi":             return .purple
        case "Recovery":                   return .green
        default:                           return .gray
        }
    }

    var tomorrowType: String {
        // Calendar.current (Gregorian): Sun=1, Mon=2, …, Sat=7
        let weekday = Calendar.current.component(.weekday, from: Date())
        let todayIdx = (weekday + 5) % 7   // 0=Lun … 6=Dim
        let tomorrowIdx = (todayIdx + 1) % 7
        let keys = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        return data.schedule[keys[tomorrowIdx]] ?? "Repos"
    }

    var tomorrowColor: Color {
        switch tomorrowType {
        case "Push A", "Push B":           return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                       return .yellow
        case "Yoga / Tai Chi":             return .purple
        case "Recovery":                   return .green
        default:                           return .gray
        }
    }

    var tomorrowExercises: [(String, String)] {
        guard let program = data.fullProgram[tomorrowType] else { return [] }
        // On ajoute .value ici pour transformer le SafeString en String
        return program.map { ($0.key, $0.value.value) }.sorted { $0.0 < $1.0 }
    }
    var body: some View {
        ZStack {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                // ── Header ──────────────────────────────────────────────
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.15))
                            .frame(width: 72, height: 72)
                            .scaleEffect(animateHeader ? 1.0 : 0.5)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                            .scaleEffect(animateHeader ? 1.0 : 0.3)
                            .opacity(animateHeader ? 1.0 : 0.0)
                    }
                    Text("Séance complétée")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(animateHeader ? 1.0 : 0.0)
                        .offset(y: animateHeader ? 0 : 12)
                    Text(data.today)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(sessionColor)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(sessionColor.opacity(0.12))
                        .clipShape(Capsule())
                        .opacity(animateHeader ? 1.0 : 0.0)
                }
                .padding(.top, 24)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                        animateHeader = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showConfetti = true
                    }
                }

                // ── Recap aujourd'hui ────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Text("RÉCAP D'AUJOURD'HUI")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.gray)

                    if let session = todaySession {
                        // RPE + stats row
                        HStack(spacing: 12) {
                            if let rpe = session.rpe {
                                VStack(spacing: 3) {
                                    Text(String(format: "%.1f", rpe))
                                        .font(.system(size: 24, weight: .black))
                                        .foregroundColor(rpeColor(rpe))
                                    Text("RPE")
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(1)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(rpeColor(rpe).opacity(0.08))
                                .cornerRadius(10)
                            }
                            if let exos = session.exos {
                                VStack(spacing: 3) {
                                    Text("\(exos.count)")
                                        .font(.system(size: 24, weight: .black))
                                        .foregroundColor(sessionColor)
                                    Text("EXOS")
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(1)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(sessionColor.opacity(0.08))
                                .cornerRadius(10)
                            }
                        }

                        // Exercise list
                        if let exos = session.exos, !exos.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(exos, id: \.self) { exo in
                                    HStack {
                                        Circle()
                                            .fill(sessionColor.opacity(0.3))
                                            .frame(width: 5, height: 5)
                                        Text(exo)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.85))
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    Divider().background(Color.white.opacity(0.04))
                                }
                            }
                        }

                        // Comment
                        if let comment = session.comment, !comment.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "quote.bubble")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                Text(comment)
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                                    .italic()
                                Spacer()
                            }
                        }
                    } else {
                        Text("Données non disponibles")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                }
                .padding(16)
                .background(Color(hex: "11111c"))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 16)

                // ── Aperçu demain ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("DEMAIN")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(tomorrowType)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(tomorrowColor)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(tomorrowColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if tomorrowExercises.isEmpty {
                        Text(tomorrowType == "Repos" ? "Journée de repos 🛌" : "Aucun exercice défini")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(tomorrowExercises.prefix(5), id: \.0) { name, scheme in
                                HStack {
                                    Circle()
                                        .fill(tomorrowColor.opacity(0.25))
                                        .frame(width: 5, height: 5)
                                    Text(name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.75))
                                    Spacer()
                                    Text(scheme)
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 6)
                                Divider().background(Color.white.opacity(0.04))
                            }
                            if tomorrowExercises.count > 5 {
                                Text("+ \(tomorrowExercises.count - 5) exercices")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(hex: "11111c"))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(tomorrowColor.opacity(0.15), lineWidth: 1))
                .padding(.horizontal, 16)

                // ── Partager la séance ─────────────────────────────────
                let shareText: String = {
                    var parts = ["💪 \(data.today) — TrainingOS"]
                    if let s = todaySession {
                        if let exos = s.exos { parts.append("\(exos.count) exercices : \(exos.prefix(3).joined(separator: ", "))\(exos.count > 3 ? "…" : "")") }
                        if let rpe = s.rpe { parts.append("RPE \(String(format: "%.1f", rpe))") }
                        if let dur = s.durationMin { parts.append("\(Int(dur)) min") }
                    }
                    return parts.joined(separator: "\n")
                }()
                ShareLink(item: shareText) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 15))
                        Text("Partager la séance").font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(hex: "1c1c2e"))
                    .foregroundColor(.white.opacity(0.7))
                    .cornerRadius(14)
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)

                // ── Reset aujourd'hui ───────────────────────────────────
                Button(action: { confirmReset = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16))
                        Text("Réinitialiser la séance")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)

                // ── Séance supplémentaire ────────────────────────────────
                Button(action: { showExtra = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("Faire une séance supplémentaire")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [sessionColor, sessionColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: sessionColor.opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showExtra) {
            ExtraSessionSheet(data: data)
        }
        .confirmationDialog("Réinitialiser la séance d'aujourd'hui ?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Réinitialiser", role: .destructive) { Task { await resetToday() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les données loggées aujourd'hui seront effacées.")
        }
        // Confetti overlay
        if showConfetti {
            ConfettiView()
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        showConfetti = false
                    }
                }
        }
        } // end ZStack
    }

    private func resetToday() async {
        try? await APIService.shared.deleteSession(date: data.todayDate)
        await vm.load()
    }

    private func rpeColor(_ v: Double) -> Color {
        if v <= 4 { return .green }
        if v <= 6 { return .yellow }
        if v <= 8 { return .orange }
        return .red
    }
}

// MARK: - Extra Session Sheet
struct ExtraSessionSheet: View {
    let data: SeanceData
    @StateObject private var extraVM = SeanceViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Group {
                    if data.today == "Yoga / Tai Chi" || data.today == "Recovery" {
                        SpecialSeanceView(sessionType: data.today, vm: extraVM)
                    } else {
                        WorkoutSeanceView(data: data, vm: extraVM)
                    }
                }
            }
            .navigationTitle("Séance supplémentaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Workout Seance (Upper/Lower)
struct GhostData {
    let date: String
    let volume: Double
    let rpe: Double?
    let sets: Int?
}

struct WorkoutSeanceView: View {
    let data: SeanceData
    @ObservedObject var vm: SeanceViewModel
    var isSecondSession: Bool = false
    @State private var rpe: Double = 7
    @State private var comment = ""
    @State private var showFinish = false
    @State private var showFinishConfirm = false
    @State private var ghostData: GhostData? = nil
    @State private var showGhost = true
    @State private var ghostBeaten = false
    
    // Programme edit
    @State private var localProgram: [String: String] = [:]
    @State private var exerciseOrder: [String] = []
    @State private var inventoryTypes: [String: String] = [:]
    @State private var inventoryTracking: [String: String] = [:]
    @State private var inventoryRest: [String: Int] = [:]
    @State private var draggingName: String?
    @State private var dragOffset: CGFloat = 0
    @State private var cardHeights: [String: CGFloat] = [:]
    @State private var inventory: [String] = []
    @State private var addTarget: SeanceName?
    @State private var editTarget: ExerciseTarget?
    @State private var isEditMode = false
    @State private var showRestTimer = false
    @State private var orderSaveError = false

    // Progression
    @State private var showProgressionSheet = false
    @State private var progressionSuggestions: [ProgressionSuggestion] = []
    @State private var didLoadPreCoaching = false

    // Optional add-ons
    @State private var showAddCardio = false
    @State private var showAddHIIT   = false
    @State private var cardioLogged  = false
    @State private var hiitLogged    = false
    
    /// Moyenne des RPE par exercice loggés — fallback 7 si aucun
    private var computedSessionRPE: Double {
        let vals = vm.logResults.values.compactMap(\.rpe)
        guard !vals.isEmpty else { return 7.0 }
        return (vals.reduce(0, +) / Double(vals.count) * 2).rounded() / 2  // arrondi au 0.5
    }

    private var exercises: [(String, String)] {
        let ordered = exerciseOrder.filter { localProgram[$0] != nil }
        let extra   = localProgram.keys.filter { !exerciseOrder.contains($0) }.sorted()
        return (ordered + extra).compactMap { name -> (String, String)? in
            guard let scheme = localProgram[name] else { return nil }
            return (name, scheme)
        }
    }
    private var currentVolume: Double {
        vm.logResults.values.reduce(0.0) { acc, r in
            let s = r.reps.trimmingCharacters(in: .whitespaces).lowercased()
            let reps: Double
            if s.contains(",") {
                reps = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
            } else if let rx = s.range(of: "x"),
                      let sets = Double(s[s.startIndex..<rx.lowerBound]),
                      let rep  = Double(s[rx.upperBound...]) {
                reps = sets * rep
            } else {
                reps = Double(s) ?? 0
            }
            return acc + r.weight * reps
        }
    }

    private struct GhostSnapshot: Codable {
        let sessions: [String: SessionEntry]
    }

    private func computeGhost() {
        if CacheService.shared.load(for: "stats_data") == nil {
            Task { try? await APIService.shared.fetchStatsData(); computeGhost() }
            return
        }
        guard let cached  = CacheService.shared.load(for: "stats_data"),
              let snap    = try? JSONDecoder().decode(GhostSnapshot.self, from: cached)
        else { return }
        let currentExos = Set(localProgram.keys.map { $0.lowercased() })
        guard !currentExos.isEmpty else { return }

        let best = snap.sessions
            .filter { $0.key != data.todayDate && ($0.value.sessionVolume ?? 0) > 0 }
            .compactMap { date, s -> (String, SessionEntry)? in
                guard let exos = s.exos else { return nil }
                let overlap = currentExos.intersection(Set(exos.map { $0.lowercased() })).count
                guard Double(overlap) / Double(min(currentExos.count, exos.count)) >= 0.5 else { return nil }
                return (date, s)
            }
            .max { ($0.1.sessionVolume ?? 0) < ($1.1.sessionVolume ?? 0) }

        if let (date, s) = best, let vol = s.sessionVolume {
            ghostData = GhostData(date: date, volume: vol, rpe: s.rpe, sets: s.totalSets)
        }
    }

    @ViewBuilder private var exerciseSection: some View {
        if isEditMode {
            VStack(spacing: 0) {
                ForEach(exercises, id: \.0) { name, scheme in
                    editModeRow(name: name, scheme: scheme)
                }
                Button { addTarget = SeanceName(id: data.today) } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundColor(.orange)
                        Text("Ajouter un exercice")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(hex: "11111c"))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 16)
        } else {
            VStack(spacing: 12) {
                ForEach(exercises, id: \.0) { name, scheme in
                    draggableCard(name: name, scheme: scheme)
                }
            }
            .onPreferenceChange(CardHeightKey.self) { cardHeights.merge($0) { $1 } }

            if orderSaveError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    Text("Ordre non sauvegardé — réessaie").font(.system(size: 12)).foregroundColor(.red)
                    Spacer()
                    Button { orderSaveError = false } label: {
                        Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func editModeRow(name: String, scheme: String) -> some View {
        HStack(spacing: 12) {
            Button { Task { await deleteExercise(name) } } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22)).foregroundColor(.red)
            }
            Button {
                editTarget = ExerciseTarget(seance: data.today, exercise: name, scheme: scheme)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 14)).foregroundColor(.white)
                        Text(scheme).font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 13)).foregroundColor(.orange.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(hex: "11111c"))
        Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 16)
    }

    @ViewBuilder
    private func draggableCard(name: String, scheme: String) -> some View {
        let isDragging = draggingName == name
        let shift = shiftY(for: name)
        let card = ExerciseCard(
            name: name,
            scheme: scheme,
            weightData: data.weights[name],
            equipmentType: equipmentType(for: name),
            trackingType: trackingType(for: name),
            bodyWeight: APIService.shared.dashboard?.profile.weight ?? 0,
            isSecondSession: isSecondSession,
            isBonusSession: false,
            restSeconds: restSeconds(for: name),
            prescription: data.prescriptions?[name],
            suggestion: data.exerciseSuggestions?[name],
            logResult: $vm.logResults[name],
            onLogged: nil
        )
        card
            .padding(.horizontal, 16)
            .background(GeometryReader { geo in
                Color.clear.preference(key: CardHeightKey.self, value: [name: geo.size.height])
            })
            .overlay(alignment: .topLeading) {
                // Gesture is restricted to the drag handle area so ScrollView can scroll freely
                Color.clear
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(.leading, 16)
                    .gesture(dragGesture(for: name))
            }
            .scaleEffect(isDragging ? 1.03 : 1.0, anchor: .center)
            .shadow(color: isDragging ? .black.opacity(0.45) : .clear, radius: isDragging ? 18 : 0)
            .offset(y: isDragging ? dragOffset : shift)
            .zIndex(isDragging ? 1 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: shift)
            .animation(.spring(response: 0.2, dampingFraction: 0.9), value: isDragging)
    }

    private func dragGesture(for name: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if draggingName == nil {
                        draggingName = name
                        triggerImpact(style: .medium)
                    }
                    dragOffset = drag.translation.height
                default:
                    break
                }
            }
            .onEnded { _ in
                if let dragging = draggingName {
                    let to = proposedDropIndex
                    if let from = exerciseOrder.firstIndex(of: dragging), from != to {
                        withAnimation(.spring(response: 0.28)) {
                            exerciseOrder.move(fromOffsets: IndexSet(integer: from),
                                               toOffset: to > from ? to + 1 : to)
                        }
                        let newOrder = exerciseOrder
                        Task { await saveOrder(newOrder) }
                    }
                }
                withAnimation(.spring(response: 0.28)) {
                    draggingName = nil
                    dragOffset   = 0
                }
            }
    }

    // MARK: - Drag helpers

    private var proposedDropIndex: Int {
        guard let name = draggingName,
              let fromIdx = exerciseOrder.firstIndex(of: name) else { return 0 }
        let slotH = (cardHeights[name] ?? 200) + 12
        let steps = Int((dragOffset / slotH).rounded())
        return max(0, min(exerciseOrder.count - 1, fromIdx + steps))
    }

    private func shiftY(for cardName: String) -> CGFloat {
        guard let dragging = draggingName, dragging != cardName,
              let from = exerciseOrder.firstIndex(of: dragging),
              let idx  = exerciseOrder.firstIndex(of: cardName) else { return 0 }
        let to = proposedDropIndex
        let h  = (cardHeights[dragging] ?? 200) + 12
        if from < to, idx > from, idx <= to { return -h }
        if from > to, idx >= to,  idx < from { return  h }
        return 0
    }
    
    @ViewBuilder private var optionalAddonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPTIONNEL")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 10) {
                Button(action: { showAddCardio = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: cardioLogged ? "checkmark.circle.fill" : "figure.run")
                            .font(.system(size: 14))
                        Text(cardioLogged ? "Cardio ajouté" : "Ajouter Cardio")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(cardioLogged ? Color.green.opacity(0.12) : Color(hex: "11111c"))
                    .foregroundColor(cardioLogged ? .green : .blue)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                        cardioLogged ? Color.green.opacity(0.3) : Color.blue.opacity(0.2), lineWidth: 1))
                }
                .disabled(cardioLogged)

                Button(action: { showAddHIIT = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: hiitLogged ? "checkmark.circle.fill" : "bolt.fill")
                            .font(.system(size: 14))
                        Text(hiitLogged ? "HIIT ajouté" : "Ajouter HIIT")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(hiitLogged ? Color.green.opacity(0.12) : Color(hex: "11111c"))
                    .foregroundColor(hiitLogged ? .green : .red)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                        hiitLogged ? Color.green.opacity(0.3) : Color.red.opacity(0.2), lineWidth: 1))
                }
                .disabled(hiitLogged)
            }
        }
        .padding(.horizontal, 16)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.today.uppercased())
                                .font(.system(size: 13, weight: .black))
                                .tracking(3)
                                .foregroundColor(.orange)
                            Text("Semaine \(data.week)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        TimelineView(.periodic(from: vm.sessionStart, by: 60)) { ctx in
                            let elapsed = Int(ctx.date.timeIntervalSince(vm.sessionStart) / 60)
                            HStack(spacing: 3) {
                                Image(systemName: "clock").font(.system(size: 10))
                                Text("\(elapsed) min")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.cyan.opacity(0.75))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.08))
                            .cornerRadius(6)
                        }
                        Button {
                            withAnimation { isEditMode.toggle() }
                        } label: {
                            Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil.circle")
                                .font(.system(size: 20))
                                .foregroundColor(isEditMode ? .green : .orange)
                        }
                        .padding(.leading, 8)
                        Button {
                            showRestTimer = true
                        } label: {
                            Image(systemName: "timer")
                                .font(.system(size: 20))
                                .foregroundColor(.cyan)
                        }
                        .padding(.leading, 4)
                    }
                    // Progress
                    let done = vm.logResults.count
                    let total = exercises.count
                    HStack {
                        Text(done == total && total > 0 ? "Tous les exercices loggés ✓" : "\(done) / \(total) exercices")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(done == total && total > 0 ? .green : .gray)
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 4)
                        .overlay(
                            GeometryReader { g in
                                let fraction: CGFloat = total > 0 ? CGFloat(done) / CGFloat(total) : 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(done == total && total > 0 ? Color.green : Color.orange)
                                    .frame(width: g.size.width * fraction)
                                    .animation(.spring(response: 0.5), value: done)
                            },
                            alignment: .leading
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Ghost mode banner
                if showGhost, let ghost = ghostData {
                    GhostBanner(
                        ghost: ghost,
                        currentVolume: currentVolume,
                        beaten: ghostBeaten,
                        onDismiss: { withAnimation { showGhost = false } }
                    )
                    .padding(.horizontal, 16)
                    .onChange(of: currentVolume) {
                        if !ghostBeaten && currentVolume >= ghost.volume {
                            ghostBeaten = true
                        }
                    }
                }

                exerciseSection

                optionalAddonsSection

                // Live RPE — visible dès qu'un exercice est loggé
                if !vm.logResults.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 14))
                            .foregroundColor(rpeColor(computedSessionRPE))
                        Text("RPE séance")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.1f", computedSessionRPE))
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(rpeColor(computedSessionRPE))
                        Text("/ 10")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(rpeColor(computedSessionRPE).opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }

                Button(action: { showFinishConfirm = true }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Terminer la séance").font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.orange).foregroundColor(.white).cornerRadius(14)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
                .confirmationDialog(
                    "Terminer la séance ?",
                    isPresented: $showFinishConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Oui, terminer") { showFinish = true }
                    Button("Pas encore", role: .cancel) { }
                } message: {
                    Text("Tu es sûr d'avoir terminé tous tes exercices ?")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showFinish) {
            FinishSessionSheet(
                exercises: exercises.map(\.0),
                logResults: vm.logResults,
                elapsedMin: Date().timeIntervalSince(vm.sessionStart) / 60,
                rpe: $rpe,
                comment: $comment,
                onSubmit: { energy in
                    let dur = Date().timeIntervalSince(vm.sessionStart) / 60
                    Task { await vm.finish(rpe: rpe, comment: comment, durationMin: dur, energyPre: energy, sessionName: data.today) }
                }
            )
            .presentationDetents([.medium, .large])
            .onAppear { rpe = computedSessionRPE }
        }
        .onChange(of: vm.showSuccess) { success in
            guard success else { return }
            vm.showSuccess = false
            Task {
                let sType = isSecondSession ? "evening" : "morning"
                let todayStr = data.todayDate
                if let suggestions = try? await APIService.shared.fetchProgressionSuggestions(
                    date: todayStr, sessionType: sType, sessionName: data.today
                ), !suggestions.filter({ $0.suggestionType != "maintain" }).isEmpty {
                    progressionSuggestions = suggestions
                    showProgressionSheet = true
                } else {
                    await vm.load()
                }
            }
        }
        .sheet(isPresented: $showProgressionSheet) {
            ProgressionSuggestionsSheet(
                suggestions: progressionSuggestions,
                sessionName: data.today
            ) {
                showProgressionSheet = false
                Task { await vm.load() }
            }
        }
        .alert("Erreur", isPresented: .constant(vm.submitError != nil)) {
            Button("OK") { vm.submitError = nil }
        } message: {
            Text(vm.submitError ?? "")
        }
        .sheet(item: $addTarget) { (sn: SeanceName) in
            AddExerciseSheet(seance: sn.id, inventory: inventory, inventorySchemes: [:]) { ex, scheme in
                Task { await addExercise(ex, scheme: scheme) }
            }
        }
        .sheet(item: $editTarget) { target in
            EditSchemeSheet(target: target) { newName, newScheme in
                Task { await editExercise(oldName: target.exercise, newName: newName, scheme: newScheme) }
            }
        }
        .sheet(isPresented: $showRestTimer) {
            RestTimerSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddCardio) {
            AddCardioSheet { cardioLogged = true }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAddHIIT) {
            AddHIITSheet { hiitLogged = true }
                .presentationDetents([.large])
        }
        .onAppear {
            Task { await loadInventory() }
            computeGhost()
            guard !didLoadPreCoaching else { return }
            didLoadPreCoaching = true
            Task {
                let sType = isSecondSession ? "evening" : "morning"
                if let sug = try? await APIService.shared.fetchProgressionSuggestions(
                    date: data.todayDate, sessionType: sType, sessionName: data.today
                ), !sug.filter({ $0.suggestionType != "maintain" }).isEmpty {
                    progressionSuggestions = sug
                    showProgressionSheet = true
                }
            }
        }
        .onChange(of: data.inventoryTypes) { fresh in
            if !fresh.isEmpty { inventoryTypes = fresh }
        }
        .onChange(of: data.inventoryTracking) { fresh in
            if !fresh.isEmpty { inventoryTracking = fresh }
        }
        .onChange(of: data.inventoryRest) { fresh in
            inventoryRest = fresh
        }
    }
    
    private func rpeColor(_ v: Double) -> Color {
        if v <= 4 { return .green }; if v <= 6 { return .yellow }; if v <= 8 { return .orange }; return .red
    }

    // Lookup equipment type with fuzzy name matching.
    // Handles e.g. program "Deadlift" matching inventory "Barbell Deadlift".
    private func equipmentType(for name: String) -> String {
        let types = inventoryTypes.isEmpty ? data.inventoryTypes : inventoryTypes
        return types[name] ?? "machine"
    }

    private func trackingType(for name: String) -> String {
        let tracking = inventoryTracking.isEmpty ? data.inventoryTracking : inventoryTracking
        return tracking[name] ?? "reps"
    }

    private func restSeconds(for name: String) -> Int? {
        let rest = inventoryRest.isEmpty ? data.inventoryRest : inventoryRest
        return rest[name]
    }

    // MARK: - Programme mutations
    
    private func loadInventory() async {
        // Seed immediately from already-loaded seanceData
        let fromCache  = data.fullProgram[data.today]?.mapValues { $0.value } ?? [:]
        let orderCache = data.exerciseOrder[data.today] ?? fromCache.keys.sorted()
        await MainActor.run {
            self.localProgram   = fromCache
            self.exerciseOrder  = orderCache
            self.inventoryTypes    = data.inventoryTypes
            self.inventoryTracking = data.inventoryTracking
            self.inventoryRest     = data.inventoryRest
        }

        // Fetch fresh programme + inventory types from network
        guard let url = URL(string: "\(APIService.shared.baseURL)/api/programme_data"),
              let (networkData, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: networkData) as? [String: Any]
        else { return }

        let inv         = (json["inventory"] as? [String]) ?? []
        let fromNetwork = (json["full_program"] as? [String: [String: String]])?[data.today]
        let orderNet    = (json["exercise_order"] as? [String: [String]])?[data.today]
        let types    = (json["inventory_types"] as? [String: String]) ?? [:]
        let tracking = (json["inventory_tracking"] as? [String: String]) ?? [:]
        let rest     = (json["inventory_rest"] as? [String: Int]) ?? [:]
        await MainActor.run {
            self.inventory = inv
            if !types.isEmpty    { self.inventoryTypes    = types }
            if !tracking.isEmpty { self.inventoryTracking = tracking }
            self.inventoryRest = rest
            if let fresh = fromNetwork {
                self.localProgram  = fresh
                self.exerciseOrder = orderNet ?? self.exerciseOrder
            }
        }
    }
        
        @discardableResult
        private func postProgramme(_ body: [String: Any]) async -> Bool {
            guard let url = URL(string: "\(APIService.shared.baseURL)/api/programme") else { return false }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                return (resp as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }

        private func saveOrder(_ order: [String]) async {
            guard order.count >= localProgram.count else { return }
            let ok = await postProgramme(["action": "reorder", "jour": data.today, "ordre": order])
            if !ok {
                await MainActor.run { orderSaveError = true }
            }
        }

        private func addExercise(_ name: String, scheme: String) async {
            await postProgramme(["action": "add", "jour": data.today, "exercise": name, "scheme": scheme, "block_type": "strength"])
            await MainActor.run { localProgram[name] = scheme }
        }
        
        private func deleteExercise(_ name: String) async {
            // Local-only: remove from this session view without touching the database
            await MainActor.run { localProgram.removeValue(forKey: name) }
        }
        
        private func editExercise(oldName: String, newName: String, scheme: String) async {
            if oldName != newName {
                // rename synce tous les jours du programme + inventaire
                await postProgramme(["action": "rename", "jour": data.today, "old_exercise": oldName, "new_exercise": newName])
                await postProgramme(["action": "scheme", "jour": data.today, "exercise": newName, "scheme": scheme])
                await MainActor.run {
                    localProgram.removeValue(forKey: oldName)
                    localProgram[newName] = scheme
                }
            } else {
                await postProgramme(["action": "scheme", "jour": data.today, "exercise": oldName, "scheme": scheme])
                await MainActor.run { localProgram[oldName] = scheme }
            }
        }
}

// MARK: - Ghost Banner
struct GhostBanner: View {
    let ghost: GhostData
    let currentVolume: Double
    let beaten: Bool
    var onDismiss: () -> Void

    private var progress: Double {
        guard ghost.volume > 0 else { return 0 }
        return min(currentVolume / ghost.volume, 1.0)
    }

    private func shortDate(_ s: String) -> String {
        String(s.suffix(5))  // MM-DD
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("👻")
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text("GHOST · \(shortDate(ghost.date))")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    HStack(spacing: 6) {
                        Text(beaten ? "Battu ! 🔥" : "\(UnitSettings.shared.display(ghost.volume), specifier: "%.0f") \(UnitSettings.shared.label)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(beaten ? .orange : .white)
                        if let rpe = ghost.rpe {
                            Text("RPE \(String(format: "%.1f", rpe))")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                        if let sets = ghost.sets {
                            Text("\(sets) sets")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.gray)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                    Capsule()
                        .fill(beaten
                            ? LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * progress, height: 5)
                        .animation(.spring(response: 0.5), value: progress)
                }
            }
            .frame(height: 5)

            HStack {
                Text(currentVolume > 0
                    ? "\(UnitSettings.shared.display(currentVolume), specifier: "%.0f") / \(UnitSettings.shared.display(ghost.volume), specifier: "%.0f") \(UnitSettings.shared.label)"
                    : "Commence à logger pour suivre ta progression")
                    .font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(beaten ? .orange : .purple)
            }
        }
        .padding(12)
        .background(Color(hex: "0e0e1c"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            beaten ? Color.orange.opacity(0.5) : Color.purple.opacity(0.25), lineWidth: 1
        ))
    }
}

// MARK: - Add Cardio Sheet
struct AddCardioSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cardioType  = "Course"
    @State private var durationMin = ""
    @State private var distanceKm  = ""
    @State private var rpe: Double = 7
    @State private var notes       = ""
    @State private var isLogging      = false
    @State private var confirmDiscard = false

    private var hasUnsavedData: Bool { !durationMin.isEmpty || !notes.isEmpty || rpe != 7 }

    private let types = ["Course", "Vélo", "Natation", "Elliptique", "Rameur", "Marche", "Autre"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Type
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TYPE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(types, id: \.self) { t in
                                        Button(t) { cardioType = t }
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(cardioType == t ? Color.blue.opacity(0.2) : Color(hex: "191926"))
                                            .foregroundColor(cardioType == t ? .blue : .gray)
                                            .cornerRadius(8)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                }
                            }
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Durée + Distance
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DURÉE (MIN)").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                TextField("30", text: $durationMin).keyboardType(.decimalPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DISTANCE (KM)").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                TextField("—", text: $distanceKm).keyboardType(.decimalPad)
                                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                    .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                            }
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // RPE
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(rpe, specifier: "%.1f")").font(.system(size: 18, weight: .black)).foregroundColor(rpeColor(rpe))
                            }
                            Slider(value: $rpe, in: 1...10, step: 0.5).tint(rpeColor(rpe))
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Notes...", text: $notes, axis: .vertical)
                                .font(.system(size: 14)).foregroundColor(.white).tint(.blue)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        Button(action: submit) {
                            HStack {
                                if isLogging { ProgressView().tint(.white) }
                                else { Image(systemName: "checkmark.circle.fill") }
                                Text("Enregistrer Cardio").font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(durationMin.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(isLogging || durationMin.isEmpty)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16).padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Cardio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        if hasUnsavedData { confirmDiscard = true } else { dismiss() }
                    }
                    .foregroundColor(.orange)
                }
            }
            .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            }
            .keyboardOkButton()
        }
    }

    private func rpeColor(_ v: Double) -> Color {
        if v <= 4 { return .green }; if v <= 6 { return .yellow }; if v <= 8 { return .orange }; return .red
    }

    private func submit() {
        isLogging = true
        Task {
            try? await APIService.shared.logCardio(
                type: cardioType,
                durationMin: Double(durationMin.replacingOccurrences(of: ",", with: ".")),
                distanceKm: Double(distanceKm.replacingOccurrences(of: ",", with: ".")),
                avgPace: nil, avgHr: nil, cadence: nil, calories: nil,
                rpe: rpe, notes: notes
            )
            await MainActor.run { isLogging = false; onDone(); dismiss() }
        }
    }
}

// MARK: - HIIT Template
struct HIITTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var sessionType: String
    var rounds: Int
    var workTime: Int
    var restTime: Int
}

// MARK: - Add HIIT Sheet
struct AddHIITSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sessionType = "HIIT"
    @State private var rounds      = "10"
    @State private var workTime    = "20"
    @State private var restTime    = "10"
    @State private var rpe: Double = 8
    @State private var notes       = ""
    @State private var isLogging   = false
    @State private var showSavePrompt = false
    @State private var templateName   = ""

    @AppStorage("hiit_templates") private var templatesData: String = "[]"

    private var templates: [HIITTemplate] {
        (try? JSONDecoder().decode([HIITTemplate].self, from: Data(templatesData.utf8))) ?? []
    }

    private func saveTemplates(_ list: [HIITTemplate]) {
        if let d = try? JSONEncoder().encode(list) {
            templatesData = String(data: d, encoding: .utf8) ?? "[]"
        }
    }

    private func applyTemplate(_ t: HIITTemplate) {
        sessionType = t.sessionType
        rounds      = "\(t.rounds)"
        workTime    = "\(t.workTime)"
        restTime    = "\(t.restTime)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Saved templates
                        if !templates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("TEMPLATES SAUVEGARDÉS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(templates) { t in
                                            HStack(spacing: 4) {
                                                Button(t.name) { applyTemplate(t) }
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.red)
                                                Button {
                                                    saveTemplates(templates.filter { $0.id != t.id })
                                                } label: {
                                                    Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(.gray)
                                                }
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color(hex: "1c1c2e")).cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            .padding(14).background(Color(hex: "11111c")).cornerRadius(14)
                        }

                        // Session type
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TYPE DE SESSION").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("HIIT", text: $sessionType)
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Rounds / Work / Rest
                        HStack(spacing: 10) {
                            ForEach([("RONDES", $rounds), ("TRAVAIL (s)", $workTime), ("REPOS (s)", $restTime)], id: \.0) { label, binding in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                                    TextField("—", text: binding).keyboardType(.numberPad)
                                        .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(10).background(Color(hex: "191926")).cornerRadius(10)
                                }
                            }
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // RPE
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(rpe, specifier: "%.1f")").font(.system(size: 18, weight: .black)).foregroundColor(rpeColor(rpe))
                            }
                            Slider(value: $rpe, in: 1...10, step: 0.5).tint(rpeColor(rpe))
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Notes...", text: $notes, axis: .vertical)
                                .font(.system(size: 14)).foregroundColor(.white).tint(.red)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(14).background(Color(hex: "11111c")).cornerRadius(14)

                        // Save template button
                        Button {
                            templateName = sessionType.isEmpty ? "HIIT" : sessionType
                            showSavePrompt = true
                        } label: {
                            Label("Sauvegarder comme template", systemImage: "bookmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color(hex: "1c1c2e")).cornerRadius(10)
                        }

                        Button(action: submit) {
                            HStack {
                                if isLogging { ProgressView().tint(.white) }
                                else { Image(systemName: "bolt.fill") }
                                Text("Enregistrer HIIT").font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.red).foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(isLogging)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16).padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("HIIT").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
            .keyboardOkButton()
            .alert("Nom du template", isPresented: $showSavePrompt) {
                TextField("Ex: Tabata 20/10", text: $templateName)
                Button("Sauvegarder") {
                    guard !templateName.isEmpty else { return }
                    let t = HIITTemplate(
                        name: templateName,
                        sessionType: sessionType.isEmpty ? "HIIT" : sessionType,
                        rounds:   Int(rounds)   ?? 10,
                        workTime: Int(workTime) ?? 20,
                        restTime: Int(restTime) ?? 10
                    )
                    saveTemplates(templates + [t])
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private func rpeColor(_ v: Double) -> Color {
        if v <= 4 { return .green }; if v <= 6 { return .yellow }; if v <= 8 { return .orange }; return .red
    }

    private func submit() {
        isLogging = true
        Task {
            try? await APIService.shared.logHIIT(
                sessionType: sessionType.isEmpty ? "HIIT" : sessionType,
                rounds:     Int(rounds)   ?? 10,
                workTime:   Int(workTime) ?? 20,
                restTime:   Int(restTime) ?? 10,
                rpe:        rpe,
                notes:      notes,
                secondSession: true
            )
            await MainActor.run { isLogging = false; onDone(); dismiss() }
        }
    }
}


    // MARK: - Exercise Card
    struct ExerciseCard: View {
        let name: String
        let scheme: String
        let weightData: WeightData?
        var equipmentType: String = "machine"
        var trackingType: String = "reps"     // "reps" | "time"
        var bodyWeight: Double = 0
        var isSecondSession: Bool = false
        var isBonusSession: Bool = false
        var restSeconds: Int? = nil
        var prescription: ExercisePrescription? = nil
        var suggestion: ProgressionSuggestion? = nil
        @Binding var logResult: ExerciseLogResult?
        var onLogged: (() -> Void)? = nil
        @ObservedObject private var units = UnitSettings.shared

        private var isTimeBased: Bool { trackingType == "time" }

        // Per-set input model
        private struct SetInput: Identifiable {
            let id = UUID()
            var weight: String = ""
            var reps: String = ""
            var duration: Int = 30   // seconds, used when isTimeBased
            var rir: Int = 3         // Reps In Reserve (0 = failure, 3 = typical target)
        }

        @State private var sets: [SetInput] = []
        @State private var showHistory = false
        @State private var showRestTimer = false
        @State private var logStatus: LogStatus? = nil
        @State private var exerciseRPE: Double = 7
        @State private var painZone: String = ""
        @State private var setBySetMode: Bool = false
        @State private var currentSetIndex: Int = 0
        @State private var showWarmup: Bool = false
        @AppStorage("exo_notes_data") private var exoNotesData: String = "{}"

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

        // Warm-up sets at 40%, 60%, 80% of currentWeight
        private var warmupSets: [(pct: Int, weight: Double)] {
            guard currentWeight > 0 else { return [] }
            return [(40, round(currentWeight * 0.4 / 2.5) * 2.5),
                    (60, round(currentWeight * 0.6 / 2.5) * 2.5),
                    (80, round(currentWeight * 0.8 / 2.5) * 2.5)]
        }
        // Set synchronously before any async call to prevent race conditions
        @State private var isLogged = false
        @State private var isEditing = false

        enum LogStatus { case success(Double), stagné, loading, error(String) }

        private var alreadyLogged: Bool { isLogged || logResult != nil }

        var currentWeight: Double { weightData?.currentWeight ?? 0 }
        var lastReps: String { weightData?.lastReps ?? "—" }

        private var setsCount: Int {
            // Prescription overrides scheme when fatigue/trend adjusts volume
            if let p = prescription { return max(1, min(p.sets, 8)) }
            let s = scheme.lowercased()
            if let x = s.firstIndex(of: "x") {
                let before = String(s[s.startIndex..<x])
                if let n = Int(before) { return max(1, min(n, 8)) }
            }
            return 3
        }

        // Average weight across all filled set rows (nil if none entered)
        private var avgWeight: Double? {
            let vals = sets
                .compactMap { Double($0.weight.replacingOccurrences(of: ",", with: ".")) }
                .filter { $0 > 0 }
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }

        // Total weight (lbs) based on equipment type
        private func totalWeight(for input: Double) -> Double {
            switch equipmentType {
            case "bodyweight": return input   // 0 for no lest, lest amount in lbs for vested
            case "barbell":    return input * 2 + 45
            case "dumbbell":   return input * 2
            default:           return input   // cable, machine
            }
        }

        // Reverse: stored total → per-side hint for the input field
        private var inputHint: Double {
            guard currentWeight > 0 else { return 0 }
            switch equipmentType {
            case "barbell":    return (currentWeight - 45) / 2
            case "dumbbell":   return currentWeight / 2
            case "bodyweight": return 0   // field = additional weight (vest/belt), not body weight
            default:           return currentWeight
            }
        }

        // Per-set hint: use individual set weight from last session if available
        private func perSetHint(for index: Int) -> String {
            if let lastSets = weightData?.history?.first?.sets, index < lastSets.count {
                let w = lastSets[index].weight
                let perSide: Double
                switch equipmentType {
                case "barbell":    perSide = w > 45 ? (w - 45) / 2 : 0
                case "dumbbell":   perSide = w / 2
                case "bodyweight": return "0.0"
                default:           perSide = w
                }
                if perSide > 0 { return units.inputStr(perSide) }
            }
            return inputHint > 0 ? units.inputStr(inputHint) : "0.0"
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

        // Reps joined from non-empty set rows (or duration in seconds for time-based)
        private var repsStr: String {
            if isTimeBased { return sets.map { String($0.duration) }.joined(separator: ",") }
            return sets.compactMap { $0.reps.isEmpty ? nil : $0.reps }.joined(separator: ",")
        }

        // Log enabled when at least one set has both weight and reps filled.
        // For bodyweight, reps alone suffice (weight field = optional lest).
        private var canLog: Bool {
            if isTimeBased     { return sets.contains { $0.duration > 0 } }
            if equipmentType == "bodyweight" {
                return sets.contains { !$0.reps.isEmpty }
            }
            return sets.contains { !$0.weight.isEmpty && !$0.reps.isEmpty }
        }

        // Format seconds → "45s" or "1m30s"
        private func formatDuration(_ secs: Int) -> String {
            guard secs >= 60 else { return "\(secs)s" }
            let m = secs / 60; let s = secs % 60
            return s > 0 ? "\(m)m\(s)s" : "\(m)m"
        }

        // Per-set reps array split from lastReps for placeholder text
        private var lastRepsParts: [String] {
            lastReps.split(separator: ",").map(String.init)
        }

        @ViewBuilder private func setRows() -> some View {
            VStack(spacing: 6) {
                // Set-by-set mode toggle
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
                            setBySetMode.toggle()
                            if setBySetMode { currentSetIndex = 0 }
                        }
                    } label: {
                        Image(systemName: setBySetMode ? "list.number" : "arrow.forward.circle")
                            .font(.system(size: 14))
                            .foregroundColor(setBySetMode ? .orange : .gray.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                ForEach(sets.indices, id: \.self) { i in
                    let isActive = setBySetMode && i == currentSetIndex
                    let isDone   = setBySetMode && i < currentSetIndex
                    HStack(spacing: 8) {
                        Text("S\(i + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isDone ? .green : isActive ? .orange : .gray)
                            .frame(width: 28)
                        TextField(perSetHint(for: i), text: $sets[i].weight)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                            .padding(8).background(Color(hex: "191926")).cornerRadius(8)
                            .disabled(setBySetMode && !isActive && !isDone)
                        let repsInvalid = !sets[i].reps.isEmpty && Int(sets[i].reps) == nil
                        TextField(lastRepsParts.indices.contains(i) ? lastRepsParts[i] : "0",
                                  text: $sets[i].reps)
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
                            .disabled(setBySetMode && !isActive && !isDone)
                        // RIR stepper
                        HStack(spacing: 0) {
                            Button { if sets[i].rir > 0 { sets[i].rir -= 1 } } label: {
                                Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gray)
                                    .frame(width: 26, height: 36)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Text("\(sets[i].rir)")
                                .font(.system(size: 13, weight: .black)).foregroundColor(.cyan)
                                .frame(width: 18, alignment: .center)
                            Button { if sets[i].rir < 6 { sets[i].rir += 1 } } label: {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.cyan)
                                    .frame(width: 26, height: 36)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        .frame(width: 70)
                        .padding(.vertical, 0).padding(.horizontal, 0)
                        .background(Color(hex: "191926")).cornerRadius(8)
                        .disabled(setBySetMode && !isActive && !isDone)

                        // Set-by-set confirm button
                        if isActive {
                            Button {
                                withAnimation {
                                    triggerImpact(style: .medium)
                                    if currentSetIndex < sets.count - 1 {
                                        currentSetIndex += 1
                                    } else {
                                        // All sets done — auto-log
                                        setBySetMode = false
                                        logExercise()
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
                    .animation(.easeInOut(duration: 0.2), value: currentSetIndex)
                }
                if !repsStr.isEmpty {
                    HStack {
                        Text("→ \(repsStr)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                if setBySetMode {
                    Text("Set \(currentSetIndex + 1)/\(sets.count) — appuie ✓ après chaque set")
                        .font(.system(size: 11)).foregroundColor(.orange.opacity(0.7))
                        .padding(.top, 2)
                }
            }
        }

        @ViewBuilder private func timeSetRows() -> some View {
            VStack(spacing: 10) {
                // Quick-set all chips
                HStack(spacing: 6) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { secs in
                        Button { for i in sets.indices { sets[i].duration = secs } } label: {
                            Text(formatDuration(secs))
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

                // Header
                HStack {
                    Text("SET").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray).frame(width: 28, alignment: .leading)
                    Text("DURÉE").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                    Spacer()
                }

                // Per-set stepper rows
                ForEach(sets.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Text("S\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundColor(.gray).frame(width: 28)
                        Button { if sets[i].duration > 5 { sets[i].duration -= 5 } } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 24)).foregroundColor(.gray)
                        }.buttonStyle(.plain)
                        Text(formatDuration(sets[i].duration))
                            .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            .frame(minWidth: 64, alignment: .center)
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            .background(Color(hex: "191926")).cornerRadius(8)
                        Button { sets[i].duration += 5 } label: {
                            Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundColor(.cyan)
                        }.buttonStyle(.plain)
                        Spacer()
                    }
                }

                // Summary
                HStack {
                    Text("→ \(sets.map { formatDuration($0.duration) }.joined(separator: ", "))")
                        .font(.system(size: 11)).foregroundColor(.gray)
                    Spacer()
                }.padding(.top, 2)
            }
        }

        @ViewBuilder private var avgTotalRow: some View {
            switch equipmentType {
            case "barbell", "dumbbell":
                // Show MOY → TOTAL only when formula multiplies the weight
                if let avg = avgWeight {
                    let avgLbs = units.toStorage(avg)
                    let total  = totalWeight(for: avgLbs)
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
                // Always show body weight as total (no avg needed)
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
                // cable / machine: total = input, nothing extra to show
                EmptyView()
            }
        }

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
                    // Bouton repos — toujours visible, ouvre le timer avec preset si configuré
                    Button { showRestTimer = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.system(size: 14, weight: .semibold))
                            if let r = restSeconds {
                                Text(r < 60 ? "\(r)s" : "\(r / 60):\(String(format: "%02d", r % 60))")
                                    .font(.system(size: 12, weight: .bold))
                                    .monospacedDigit()
                            }
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(8)
                    }
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
                                Button(action: { isEditing = true }) {
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                            }
                        }
                    }
                }

                // Inline coaching chip — shown when not yet logged and suggestion is actionable
                if logResult == nil, let s = suggestion, s.suggestionType != "maintain" {
                    CoachingChip(suggestion: s)
                }

                if alreadyLogged && !isEditing {
                    // ── Résumé loggé ──
                    if let r = logResult {
                        HStack(spacing: 12) {
                            if isTimeBased {
                                HStack(spacing: 4) {
                                    Image(systemName: "timer").font(.system(size: 11)).foregroundColor(.gray)
                                    Text(r.reps.split(separator: ",").compactMap { Int($0) }.map { formatDuration($0) }.joined(separator: ", "))
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
                            Button { isEditing = true } label: {
                                Label("Modifier", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                logResult = nil
                                isLogged = false
                                logStatus = nil
                            } label: {
                                Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                            }
                        }
                    }
                } else {
                    // ── Inputs ──

                    // Prescription chip (sets × reps, with fatigue/trend note)
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

                    // Recommended weight hint
                    if currentWeight > 0 {
                        HStack {
                            Text("RECOMMANDÉ")
                                .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundColor(.gray)
                            Spacer()
                            Text(units.format(currentWeight))
                                .font(.system(size: 13, weight: .bold)).foregroundColor(.orange.opacity(0.7))
                        }
                    }

                    // Quick-fill from last session
                    if !isTimeBased, lastReps != "—", !lastReps.isEmpty {
                        Button {
                            for i in sets.indices {
                                sets[i].weight = perSetHint(for: i)
                                let parts = lastRepsParts
                                sets[i].reps = parts.indices.contains(i) ? parts[i] : (parts.first ?? "")
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

                    // Warm-up sets toggle
                    if !isTimeBased && !warmupSets.isEmpty {
                        Button {
                            withAnimation { showWarmup.toggle() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: showWarmup ? "chevron.down" : "flame")
                                    .font(.system(size: 11)).foregroundColor(.yellow.opacity(0.7))
                                Text("Échauffement (\(Int(currentWeight)) \(UnitSettings.shared.label))")
                                    .font(.system(size: 11, weight: .medium)).foregroundColor(.yellow.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)
                        if showWarmup {
                            VStack(spacing: 4) {
                                ForEach(warmupSets, id: \.pct) { ws in
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

                    // Per-set rows
                    if isTimeBased { timeSetRows() } else { setRows() }

                    // Add/remove set rows
                    HStack(spacing: 12) {
                        Button {
                            if sets.count > 1 { sets.removeLast() }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 20))
                                .foregroundColor(sets.count > 1 ? .red.opacity(0.45) : .gray.opacity(0.2))
                        }
                        .disabled(sets.count <= 1)
                        .buttonStyle(.plain)
                        Text("\(sets.count) set\(sets.count > 1 ? "s" : "")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                        Button {
                            if sets.count < 8 { sets.append(SetInput()) }
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 20))
                                .foregroundColor(sets.count < 8 ? .green.opacity(0.55) : .gray.opacity(0.2))
                        }
                        .disabled(sets.count >= 8)
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.top, 2)

                    // Average weight + total (reps mode only)
                    if !isTimeBased, avgWeight != nil {
                        avgTotalRow
                    }

                    // RPE slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("RPE")
                                .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.1f", exerciseRPE))
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(rpeColor(exerciseRPE))
                        }
                        Slider(value: $exerciseRPE, in: 6...10, step: 0.5)
                            .tint(rpeColor(exerciseRPE))
                    }
                    .padding(.top, 4)

                    // Pain zone (optional)
                    HStack(spacing: 6) {
                        Image(systemName: "bandage").font(.system(size: 11)).foregroundColor(.red.opacity(0.6))
                        TextField("Zone douloureuse (optionnel)", text: $painZone)
                            .font(.system(size: 12)).foregroundColor(painZone.isEmpty ? .gray : .red)
                    }
                    .padding(.top, 2)

                    // Notes persistées par exercice
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

                    // Log / Mettre à jour button
                    HStack {
                        if isEditing {
                            Button(action: { isEditing = false }) {
                                Text("Annuler")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        Button(action: logExercise) {
                            HStack(spacing: 6) {
                                Image(systemName: isEditing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.up.circle.fill")
                                    .font(.system(size: 38))
                                if isEditing {
                                    Text("Mettre à jour")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }
                            .foregroundColor(canLog ? .orange : .gray)
                        }
                        .disabled(!canLog)
                        .padding(.top, 8)
                    }

                    // Status
                    if let status = logStatus {
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
                                    Text(exerciseRPE < 7.5 ? "RPE bas — essaie +1 rep" : "RPE élevé — maintiens le poids")
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

                // History — most recent entry always visible
                if let history = weightData?.history, !history.isEmpty {
                    VStack(spacing: 4) {
                        // Sparkline — shown when 3+ entries with weight data
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
                                Button(action: { showHistory.toggle() }) {
                                    HStack(spacing: 2) {
                                        Text(showHistory ? "Moins" : "+\(history.count - 1)")
                                            .font(.system(size: 9))
                                        Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 9))
                                    }
                                    .foregroundColor(.gray.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if showHistory && history.count > 1 {
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
                // No pre-fill: fields start empty so user can dismiss without saving
                if sets.isEmpty { sets = Array(repeating: SetInput(), count: setsCount) }
            }
            .onChange(of: setsCount) {
                if sets.count < setsCount {
                    sets.append(contentsOf: Array(repeating: SetInput(), count: setsCount - sets.count))
                } else if sets.count > setsCount {
                    sets = Array(sets.prefix(setsCount))
                }
            }
            .onChange(of: logResult == nil) { isNil in
                if isNil { isLogged = false; logStatus = nil; isEditing = false }
            }
            .sheet(isPresented: $showRestTimer) {
                RestTimerSheet(autoStartSeconds: restSeconds)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }

        private func logExercise() {
            guard !alreadyLogged || isEditing, canLog else { return }
            guard !repsStr.isEmpty else { return }
            let wasEditing = isEditing
            if isEditing { isLogged = false }
            isLogged = true
            isEditing = false
            logStatus = .loading

            // ── Time-based branch ──
            if isTimeBased {
                let setsPayload: [[String: Any]] = sets.map { ["weight": 0, "reps": String($0.duration)] }
                Task {
                    do {
                        try await APIService.shared.logExercise(
                            exercise: name, weight: 0, reps: repsStr, rpe: exerciseRPE,
                            sets: setsPayload, force: wasEditing, isSecond: isSecondSession, isBonus: isBonusSession,
                            equipmentType: "bodyweight", painZone: painZone)
                        await MainActor.run {
                            logResult = ExerciseLogResult(name: name, weight: 0, reps: repsStr, rpe: exerciseRPE)
                            logStatus = .success(0)
                            onLogged?()
                            triggerNotificationFeedback(.success)
                            if restSeconds != nil { showRestTimer = true }
                        }
                    } catch {
                        await MainActor.run {
                            isLogged = false
                            logStatus = .error("Erreur réseau — réessaie")
                        }
                    }
                }
                return
            }

            // ── Reps-based branch ──
            // For bodyweight with no lest, avgWeight is nil → use 0 (backend resolves body weight for volume)
            let avg   = avgWeight ?? (equipmentType == "bodyweight" ? 0.0 : nil)
            guard let avg = avg else { return }
            let w     = units.toStorage(avg)   // per-side in lbs (0 for bodyweight-only)
            let total = totalWeight(for: w)    // total load: 0 for BW-only, lest for vested, barbell ×2+45…
            // Per-set payload
            let setsPayload: [[String: Any]] = sets.compactMap { s -> [String: Any]? in
                guard !s.reps.isEmpty else { return nil }
                if equipmentType == "bodyweight" {
                    // Send lest weight (0 if no lest) so backend knows it's bodyweight-only
                    let lest = Double(s.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                    return ["weight": units.toStorage(lest), "reps": s.reps, "rir": s.rir]
                }
                guard let sw = Double(s.weight.replacingOccurrences(of: ",", with: ".")),
                      sw > 0 else { return nil }
                let setTotal = totalWeight(for: units.toStorage(sw))
                return ["weight": setTotal, "reps": s.reps, "rir": s.rir]
            }
            Task {
                do {
                    let response = try await APIService.shared.logExercise(
                        exercise: name, weight: total, reps: repsStr, rpe: exerciseRPE,
                        sets: setsPayload, force: wasEditing, isSecond: isSecondSession, isBonus: isBonusSession,
                        equipmentType: equipmentType, painZone: painZone)
                    await MainActor.run {
                        logResult = ExerciseLogResult(name: name, weight: total, reps: repsStr, rpe: exerciseRPE)
                        logStatus = .success(total)
                        onLogged?()
                        triggerNotificationFeedback(.success)
                        if restSeconds != nil { showRestTimer = true }
                    }
                    if response.isPR == true {
                        let content = UNMutableNotificationContent()
                        content.title = "🏆 Nouveau PR !"
                        content.body  = "\(name) — 1RM estimé : \(String(format: "%.1f", response.oneRM ?? 0)) lbs"
                        content.sound = .default
                        let request = UNNotificationRequest(
                            identifier: "pr-\(name)-\(Date().timeIntervalSince1970)",
                            content: content,
                            trigger: nil
                        )
                        try? await UNUserNotificationCenter.current().add(request)
                        await MainActor.run {
                            triggerNotificationFeedback(.success)
                        }
                    }
                } catch {
                    await MainActor.run {
                        isLogged = false
                        logStatus = .error("Erreur réseau — réessaie")
                    }
                }
            }
        }
    }
    
    // MARK: - Finish Sheet
    struct FinishSessionSheet: View {
        let exercises: [String]
        let logResults: [String: ExerciseLogResult]
        let elapsedMin: Double
        @Binding var rpe: Double
        @Binding var comment: String
        var onSubmit: (Int?) -> Void   // (energyPre)
        @Environment(\.dismiss) private var dismiss

        @State private var energyPre: Int = 3   // 1–5
        @State private var confirmDiscard = false
        @State private var aiAnalysis: String? = nil
        @State private var isLoadingAI = false

        private var hasUnsavedData: Bool { !comment.isEmpty || energyPre != 3 }

        var loggedCount: Int { logResults.count }
        
        var body: some View {
            NavigationStack {
                ZStack {
                    Color(hex: "080810").ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 16) {
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundColor(.orange)
                                Text("Terminer la séance").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                                Text("\(loggedCount) / \(exercises.count) exercices loggés").font(.system(size: 14)).foregroundColor(.gray)
                            }.padding(.top, 20)
                            
                            // Durée auto-calculée
                            HStack(spacing: 12) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.cyan)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("DURÉE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    Text("\(Int(elapsedMin)) min")
                                        .font(.system(size: 22, weight: .black))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                            }
                            .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)
                            
                            // Énergie pré-séance
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("ÉNERGIE AVANT LA SÉANCE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                    Spacer()
                                    Text(energyLabel(energyPre))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(energyColor(energyPre))
                                }
                                HStack(spacing: 8) {
                                    ForEach(1...5, id: \.self) { i in
                                        Button(action: { energyPre = i }) {
                                            VStack(spacing: 4) {
                                                Image(systemName: i <= energyPre ? "bolt.fill" : "bolt")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(i <= energyPre ? energyColor(energyPre) : .gray.opacity(0.3))
                                                Text("\(i)").font(.system(size: 9)).foregroundColor(.gray)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)
                            
                            // RPE — pré-rempli depuis la moyenne des RPE par exercice
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("RPE SÉANCE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                        Text("Moy. RPE exercices")
                                            .font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
                                    }
                                    Spacer()
                                    Text("\(rpe, specifier: "%.1f")").font(.system(size: 24, weight: .black)).foregroundColor(.orange)
                                }
                                Slider(value: $rpe, in: 1...10, step: 0.5).tint(.orange)
                            }
                            .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)
                            
                            // Notes
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NOTES").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                TextField("Commentaire optionnel...", text: $comment, axis: .vertical)
                                    .foregroundColor(.white).tint(.orange)
                                    .lineLimit(3, reservesSpace: true)
                                    .submitLabel(.done)
                                    .onSubmit { hideKeyboard() }
                                    .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                            }
                            .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 20)

                            // IA analyse post-séance
                            VStack(alignment: .leading, spacing: 8) {
                                Button(action: loadAIAnalysis) {
                                    HStack(spacing: 6) {
                                        if isLoadingAI {
                                            ProgressView().tint(.purple).scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "brain.head.profile").font(.system(size: 13))
                                        }
                                        Text(isLoadingAI ? "Analyse en cours…" : "Analyse IA post-séance")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(Color.purple.opacity(0.12))
                                    .foregroundColor(.purple)
                                    .cornerRadius(10)
                                }
                                .disabled(isLoadingAI)

                                if let analysis = aiAnalysis {
                                    Text(analysis)
                                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                                        .padding(12).background(Color.purple.opacity(0.08))
                                        .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal, 20)

                            Button(action: {
                                onSubmit(energyPre)
                                dismiss()
                            }) {
                                Text("Enregistrer la séance")
                                    .font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(Color.orange).foregroundColor(.white).cornerRadius(14)
                            }
                            .padding(.horizontal, 20).padding(.bottom, 24)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Annuler") {
                            if hasUnsavedData { confirmDiscard = true } else { dismiss() }
                        }
                        .foregroundColor(.orange)
                    }
                }
                .confirmationDialog("Abandonner la saisie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Abandonner", role: .destructive) { dismiss() }
                    Button("Continuer", role: .cancel) {}
                }
                .keyboardOkButton()
            }
        }

        private func loadAIAnalysis() {
            guard !isLoadingAI else { return }
            isLoadingAI = true
            let exoSummary = logResults.map { k, v in
                "\(k): \(v.reps) @ \(String(format: "%.0f", v.weight))lbs RPE\(String(format: "%.1f", v.rpe ?? rpe))"
            }.joined(separator: ", ")
            let prompt = "Séance terminée en \(Int(elapsedMin)) min. Exercices: \(exoSummary). RPE global: \(String(format: "%.1f", rpe)). Donne une analyse courte (3-4 phrases) : points positifs, point à améliorer, conseil pour la prochaine séance."
            Task {
                do {
                    let url = URL(string: "\(APIService.shared.baseURL)/api/ai/coach")!
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "context": "Post-session analysis",
                        "messages": [["role": "user", "content": prompt]]
                    ])
                    let (data, _) = try await URLSession.shared.data(for: req)
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let reply = json["response"] as? String {
                        await MainActor.run { aiAnalysis = reply; isLoadingAI = false }
                    } else { await MainActor.run { isLoadingAI = false } }
                } catch { await MainActor.run { isLoadingAI = false } }
            }
        }

        private func energyLabel(_ v: Int) -> String {
            switch v {
            case 1: return "Épuisé 😴"
            case 2: return "Fatigué 😕"
            case 3: return "Normal 😐"
            case 4: return "En forme 💪"
            default: return "Excellent ⚡"
            }
        }
        private func energyColor(_ v: Int) -> Color {
            switch v {
            case 1, 2: return .red
            case 3: return .yellow
            default: return .green
            }
        }
    }
    
    // MARK: - HIIT Seance
    struct HIITSeanceView: View {
        let sessionType: String
        @ObservedObject var vm: SeanceViewModel
        @State private var rounds = 8
        @State private var workTime = 40
        @State private var restTime = 20
        @State private var rpe: Double = 7
        @State private var notes = ""
        
        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.run").font(.system(size: 48)).foregroundColor(.red)
                        Text(sessionType).font(.system(size: 24, weight: .black)).foregroundColor(.white)
                    }.padding(.top, 20)
                    
                    VStack(spacing: 12) {
                        StepperRow(title: "ROUNDS", value: $rounds, range: 1...30)
                        StepperRow(title: "WORK (s)", value: $workTime, range: 10...120, step: 5)
                        StepperRow(title: "REST (s)", value: $restTime, range: 5...120, step: 5)
                    }.padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                            Spacer()
                            Text("\(rpe, specifier: "%.1f")").font(.system(size: 20, weight: .black)).foregroundColor(.orange)
                        }
                        Slider(value: $rpe, in: 1...10, step: 0.5).tint(.orange)
                    }
                    .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                        TextField("Notes optionnelles...", text: $notes, axis: .vertical)
                            .foregroundColor(.white).lineLimit(3, reservesSpace: true)
                    }
                    .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 16)
                    
                    Button(action: logHIIT) {
                        Text("Enregistrer HIIT")
                            .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.red).foregroundColor(.white).cornerRadius(14)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
            .alert("HIIT enregistré ✅", isPresented: $vm.showSuccess) {
                Button("OK") { Task { await vm.load() } }
            }
        }
        
        private func logHIIT() {
            Task {
                try? await APIService.shared.logHIIT(
                    sessionType: sessionType, rounds: rounds,
                    workTime: workTime, restTime: restTime, rpe: rpe, notes: notes
                )
                await vm.load()
                await APIService.shared.fetchDashboard()
                vm.showSuccess = true
            }
        }
    }
    
    // MARK: - Inline Coaching Chip

    private struct CoachingChip: View {
        let suggestion: ProgressionSuggestion

        @State private var applied = false
        @State private var ignored = false

        var body: some View {
            if ignored {
                EmptyView()
            } else if applied {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundColor(.green)
                    Text("Appliqué")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.green)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.green.opacity(0.1)).cornerRadius(8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: typeIcon)
                        .font(.system(size: 12)).foregroundColor(typeColor)
                    if let w = suggestion.suggestedWeight {
                        Text(w.fmtLbs())
                            .font(.system(size: 13, weight: .black)).foregroundColor(typeColor)
                    }
                    Text(suggestion.reason)
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                    Spacer()
                    Button("Ignorer") { ignored = true }
                        .font(.system(size: 11)).foregroundColor(.gray)
                    if let w = suggestion.suggestedWeight {
                        Button("Appliquer") {
                            applied = true
                            triggerImpact(style: .light)
                            Task {
                                try? await APIService.shared.applyProgression(
                                    exerciseName: suggestion.exerciseName,
                                    suggestedWeight: w,
                                    suggestedScheme: suggestion.suggestedScheme
                                )
                            }
                        }
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(typeColor)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(typeColor.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(typeColor.opacity(0.2), lineWidth: 1))
                .cornerRadius(8)
            }
        }

        private var typeIcon: String {
            switch suggestion.suggestionType {
            case "increase_weight": return "arrow.up.circle.fill"
            case "increase_sets":   return "plus.circle.fill"
            case "deload":          return "arrow.down.circle.fill"
            case "regression":      return "exclamationmark.circle.fill"
            default:                return "minus.circle"
            }
        }
        private var typeColor: Color {
            switch suggestion.suggestionType {
            case "increase_weight": return .cyan
            case "increase_sets":   return .green
            case "deload":          return .orange
            case "regression":      return .red
            default:                return .gray
            }
        }
    }

    // MARK: - Special (Yoga/Recovery)
    struct SpecialSeanceView: View {
        let sessionType: String
        @ObservedObject var vm: SeanceViewModel
        @State private var rpe: Double = 5
        @State private var comment = ""
        @AppStorage("special_session_logged_date") private var loggedDate: String = ""

        private var alreadyLoggedToday: Bool {
            loggedDate == DateFormatter.isoDate.string(from: Date())
        }

        var color: Color { sessionType == "Yoga / Tai Chi" ? .purple : .green }
        var icon: String  { sessionType == "Yoga / Tai Chi" ? "figure.mind.and.body" : "heart.fill" }

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: icon).font(.system(size: 48)).foregroundColor(color)
                        Text(sessionType).font(.system(size: 24, weight: .black)).foregroundColor(.white)
                    }.padding(.top, 24)

                    if alreadyLoggedToday {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(color)
                            Text("Séance déjà enregistrée aujourd'hui")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(color)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(color.opacity(0.12))
                        .cornerRadius(14)
                        .padding(.horizontal, 16)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text("\(rpe, specifier: "%.1f")").font(.system(size: 20, weight: .black)).foregroundColor(color)
                            }
                            Slider(value: $rpe, in: 1...10, step: 0.5).tint(color)
                        }
                        .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Comment c'était ?", text: $comment, axis: .vertical)
                                .foregroundColor(.white).tint(.orange)
                                .lineLimit(3, reservesSpace: true)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12).background(Color(hex: "191926")).cornerRadius(10)
                        }
                        .padding(16).background(Color(hex: "11111c")).cornerRadius(14).padding(.horizontal, 16)

                        Button(action: logSession) {
                            Text("Enregistrer \(sessionType)")
                                .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(color).foregroundColor(.white).cornerRadius(14)
                        }
                        .padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .alert("Séance enregistrée ✅", isPresented: $vm.showSuccess) {
                Button("OK") { Task { await vm.load() } }
            }
        }

        private func logSession() {
            Task {
                try? await APIService.shared.logSession(exos: [sessionType], rpe: rpe, comment: comment)
                loggedDate = DateFormatter.isoDate.string(from: Date())
                await vm.load()
                await APIService.shared.fetchDashboard()
                vm.showSuccess = true
            }
        }
    }
    
    // MARK: - Stepper Row
    struct StepperRow: View {
        let title: String
        @Binding var value: Int
        let range: ClosedRange<Int>
        var step: Int = 1
        
        var body: some View {
            HStack {
                Text(title).font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 12) {
                    Button(action: { if value - step >= range.lowerBound { value -= step } }) {
                        Image(systemName: "minus.circle.fill").font(.system(size: 28)).foregroundColor(.gray)
                    }
                    Text("\(value)").font(.system(size: 20, weight: .black)).foregroundColor(.white).frame(width: 50, alignment: .center)
                    Button(action: { if value + step <= range.upperBound { value += step } }) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 28)).foregroundColor(.orange)
                    }
                }
            }
            .padding(14).background(Color(hex: "11111c")).cornerRadius(12)
        }
    }
    
    // MARK: - Rest Timer Sheet
    struct RestTimerSheet: View {
        var autoStartSeconds: Int? = nil

        @Environment(\.dismiss)    private var dismiss
        @Environment(\.scenePhase) private var scenePhase
        @State private var totalSeconds = 120
        @State private var remaining    = 120
        @State private var isRunning    = false
        @State private var timerTask:   Task<Void, Never>?
        @State private var beepPlayer:  AVAudioPlayer?

        private static let endDateKey  = "restTimerEndDate"
        private static let totalKey    = "restTimerTotal"
        private static let presetKey   = "restTimerPreset"
        private let presets            = [60, 90, 120, 180]

        private var progress: Double {
            totalSeconds > 0 ? Double(remaining) / Double(totalSeconds) : 0
        }
        private var timerColor: Color {
            if progress > 0.5 { return .green }
            if progress > 0.25 { return .yellow }
            return .red
        }

        var body: some View {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 28) {
                    Text("REPOS")
                        .font(.system(size: 12, weight: .black))
                        .tracking(4)
                        .foregroundColor(.gray)
                        .padding(.top, 8)

                    // Preset chips
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { p in
                            Button {
                                totalSeconds = p
                                remaining = p
                                UserDefaults.standard.set(p, forKey: Self.presetKey)
                            } label: {
                                Text(p < 60 ? "\(p)s" : (p % 60 == 0 ? "\(p / 60) min" : "\(p)s"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(totalSeconds == p ? .black : timerColor)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(totalSeconds == p ? timerColor : timerColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .opacity(isRunning ? 0 : 1)

                    // Ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.07), lineWidth: 14)
                            .frame(width: 180, height: 180)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(timerColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .frame(width: 180, height: 180)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: progress)
                        Text(formatTime(remaining))
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundColor(timerColor)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }

                    // Adjust buttons
                    HStack(spacing: 16) {
                        adjustButton(label: "−10s") {
                            let newVal = max(10, remaining - 10)
                            remaining = newVal
                            if isRunning { rescheduleNotification(seconds: newVal) }
                            else { totalSeconds = newVal }
                        }
                        adjustButton(label: "+10s") {
                            remaining += 10
                            if isRunning { rescheduleNotification(seconds: remaining) }
                            else { totalSeconds = remaining }
                        }
                    }

                    // Play/Pause + Reset
                    HStack(spacing: 20) {
                        Button {
                            stopTimer()
                            remaining = totalSeconds
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 56, height: 56)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }

                        Button {
                            if isRunning { stopTimer() } else { startTimer() }
                        } label: {
                            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 72, height: 72)
                                .background(timerColor)
                                .clipShape(Circle())
                        }

                        // Fermer sans arrêter le timer
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 56, height: 56)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .onAppear { restoreIfNeeded() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { syncFromEndDate() }
            }
            // Ne pas arrêter le timer à la fermeture du sheet
        }

        // MARK: – Timer control

        private func startTimer() {
            guard remaining > 0 else { return }
            isRunning = true
            let endDate = Date().addingTimeInterval(TimeInterval(remaining))
            UserDefaults.standard.set(endDate,      forKey: Self.endDateKey)
            UserDefaults.standard.set(totalSeconds, forKey: Self.totalKey)
            scheduleNotification(seconds: remaining)
            timerTask = Task { await runLoop() }
        }

        private func stopTimer() {
            isRunning = false
            timerTask?.cancel()
            timerTask = nil
            UserDefaults.standard.removeObject(forKey: Self.endDateKey)
            UserDefaults.standard.removeObject(forKey: Self.totalKey)
            cancelNotification()
        }

        /// Recalcule le remaining depuis la endDate persistée (retour premier plan).
        private func syncFromEndDate() {
            guard isRunning,
                  let end = UserDefaults.standard.object(forKey: Self.endDateKey) as? Date else { return }
            let left = Int(end.timeIntervalSinceNow.rounded())
            if left <= 0 {
                remaining  = 0
                isRunning  = false
                timerTask?.cancel()
                timerTask  = nil
                UserDefaults.standard.removeObject(forKey: Self.endDateKey)
                playBeep(hz: 1200)
                triggerNotificationFeedback(.success)
            } else {
                remaining = left
            }
        }

        /// Restaure un timer en cours si l'app a été quittée avec le timer actif.
        private func restoreIfNeeded() {
            if let end = UserDefaults.standard.object(forKey: Self.endDateKey) as? Date {
                let left = Int(end.timeIntervalSinceNow.rounded())
                guard left > 0 else {
                    UserDefaults.standard.removeObject(forKey: Self.endDateKey)
                    applyAutoStartOrPreset()
                    return
                }
                totalSeconds = UserDefaults.standard.integer(forKey: Self.totalKey)
                if totalSeconds == 0 { totalSeconds = left }
                remaining = left
                isRunning = true
                timerTask = Task { await runLoop() }
            } else {
                applyAutoStartOrPreset()
            }
        }

        private func applyAutoStartOrPreset() {
            if let auto = autoStartSeconds, auto > 0 {
                totalSeconds = auto
                remaining    = auto
                UserDefaults.standard.set(auto, forKey: Self.presetKey)
                startTimer()
            } else {
                loadPreset()
            }
        }

        private func loadPreset() {
            let saved = UserDefaults.standard.integer(forKey: Self.presetKey)
            if saved > 0 { totalSeconds = saved; remaining = saved }
        }

        // MARK: – Notifications

        private func scheduleNotification(seconds: Int) {
            cancelNotification()
            let content = UNMutableNotificationContent()
            content.title = "Repos terminé ✅"
            content.body  = "C'est reparti !"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
            let request = UNNotificationRequest(identifier: "restTimer", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }

        private func rescheduleNotification(seconds: Int) {
            let endDate = Date().addingTimeInterval(TimeInterval(seconds))
            UserDefaults.standard.set(endDate, forKey: Self.endDateKey)
            scheduleNotification(seconds: seconds)
        }

        private func cancelNotification() {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["restTimer"])
        }

        // MARK: – Helpers

        private func adjustButton(label: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(timerColor)
                    .frame(width: 80, height: 40)
                    .background(timerColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }

        private func formatTime(_ s: Int) -> String {
            "\(s / 60):\(String(format: "%02d", s % 60))"
        }

        @MainActor
        private func runLoop() async {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                if remaining > 0 {
                    remaining -= 1
                    if remaining <= 3 && remaining > 0 {
                        playBeep(hz: 880)
                        triggerImpact(style: .rigid)
                    } else if remaining == 0 {
                        isRunning = false
                        UserDefaults.standard.removeObject(forKey: Self.endDateKey)
                        playBeep(hz: 1200)
                        triggerNotificationFeedback(.success)
                    }
                }
            }
        }

        private func playBeep(hz: Double) {
            beepPlayer = makeBeep(hz: hz, duration: hz > 1000 ? 0.35 : 0.12)
            beepPlayer?.play()
        }
    }
    
    
    // MARK: - Error View
    struct ErrorView: View {
        let message: String
        let retry: () -> Void
        var body: some View {
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash").font(.system(size: 48)).foregroundColor(.gray)
                Text("Erreur").foregroundColor(.white).font(.headline)
                Text(message).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                Button("Réessayer", action: retry).foregroundColor(.orange)
            }.padding()
        }
    }
    
    // MARK: - ViewModel
    struct ExerciseLogResult {
        let name: String
        let weight: Double
        let reps: String
        var rpe: Double? = nil
    }
    
    @MainActor
    class SeanceViewModel: ObservableObject {
        @Published var seanceData: SeanceData?
        @Published var isLoading = false
        @Published var error: String?
        @Published var logResults: [String: ExerciseLogResult] = [:]
        @Published var showSuccess = false
        @Published var submitError: String?

        let sessionStart = Date()

        var cacheService: CacheService = .shared

        func load() async {
            // Show cached data immediately so the view is usable before network
            if seanceData == nil,
               let cached = cacheService.load(for: "seance_data"),
               let decoded = try? JSONDecoder().decode(SeanceData.self, from: cached) {
                seanceData = decoded
                restoreLogResults(from: decoded)
            }

            if seanceData == nil { isLoading = true }
            error = nil
            do {
                let fresh = try await APIService.shared.fetchSeanceData()
                seanceData = fresh
                restoreLogResults(from: fresh)
            } catch {
                // Only surface error if we have nothing to show
                if seanceData == nil { self.error = error.localizedDescription }
            }
            isLoading = false
        }

        func restoreLogResults(from data: SeanceData) {
            let program = data.fullProgram[data.today] ?? [:]
            var restored: [String: ExerciseLogResult] = [:]
            for exerciseName in program.keys {
                if let first = data.weights[exerciseName]?.history?.first,
                   first.date == data.todayDate,
                   let w = first.weight, let r = first.reps {
                    restored[exerciseName] = ExerciseLogResult(name: exerciseName, weight: w, reps: r)
                }
            }
            logResults = restored
        }
        
        func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil) async {
            let exos = logResults.values.map { "\($0.name) \($0.weight)lbs \($0.reps)" }
            do {
                try await APIService.shared.logSession(exos: exos, rpe: rpe, comment: comment,
                                                       durationMin: durationMin, energyPre: energyPre,
                                                       sessionName: sessionName)
                showSuccess = true
                await APIService.shared.fetchDashboard()
            } catch { submitError = error.localizedDescription }
        }
        
    }





// MARK: - Confetti
private struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var color: Color
    var angle: Double
    var size: CGFloat
}

private struct ConfettiView: View {
    private let colors: [Color] = [.orange, .green, .cyan, .yellow, .pink, .purple]
    @State private var pieces: [ConfettiPiece] = []
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 0.5)
                        .position(x: p.x, y: animate ? geo.size.height + 40 : p.y)
                        .rotationEffect(.degrees(p.angle + (animate ? 360 : 0)))
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeIn(duration: Double.random(in: 1.4...2.4))
                            .delay(Double.random(in: 0...0.5)),
                            value: animate
                        )
                }
            }
            .onAppear {
                pieces = (0..<60).map { _ in
                    ConfettiPiece(
                        x: CGFloat.random(in: 0...geo.size.width),
                        y: CGFloat.random(in: -20...geo.size.height * 0.4),
                        color: colors.randomElement()!,
                        angle: Double.random(in: 0...360),
                        size: CGFloat.random(in: 6...12)
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    animate = true
                }
            }
        }
    }
}

// MARK: - Card Height Preference Key
private struct CardHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
