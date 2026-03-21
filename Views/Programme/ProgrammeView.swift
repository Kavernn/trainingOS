import SwiftUI

private let kBaseURL = "https://training-os-rho.vercel.app"

struct ProgrammeView: View {
    @State private var fullProgram: [String: [String: String]] = [:]
    @State private var exerciseOrder: [String: [String]] = [:]
    @State private var schedule: [String: String] = [:]
    @State private var eveningSchedule: [String: String] = [:]
    @State private var inventory: [String] = []
    @State private var inventorySchemes: [String: String] = [:]
    @State private var isLoading = true
    @State private var addTarget: SeanceName?      // seance courante pour l'ajout
    @State private var editTarget: ExerciseTarget? // exercice à éditer

    private let dayNames    = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    private let seanceOrder = ["Push A", "Pull A", "Legs", "Push B", "Pull B + Full Body", "Yoga / Tai Chi", "Recovery"]

    var orderedSeances: [String] {
        seanceOrder.filter { fullProgram[$0] != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.orange)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            WeekScheduleCard(schedule: schedule, dayNames: dayNames)
                                .padding(.horizontal, 16)

                            EveningScheduleCard(
                                eveningSchedule: $eveningSchedule,
                                dayNames: dayNames,
                                sessions: orderedSeances,
                                onSave: { Task { await saveEveningSchedule() } }
                            )
                            .padding(.horizontal, 16)

                            ForEach(orderedSeances, id: \.self) { seance in
                                EditableSeanceProgramCard(
                                    seance:   seance,
                                    exercises: Binding(
                                        get: { fullProgram[seance] ?? [:] },
                                        set: { fullProgram[seance] = $0 }
                                    ),
                                    orderedNames: Binding(
                                        get: { exerciseOrder[seance] ?? (fullProgram[seance]?.keys.sorted() ?? []) },
                                        set: { exerciseOrder[seance] = $0 }
                                    ),
                                    onAdd:    { addTarget = SeanceName(id: seance) },
                                    onEdit:   { ex, scheme in editTarget = ExerciseTarget(seance: seance, exercise: ex, scheme: scheme) },
                                    onDelete: { ex in Task { await deleteExercise(seance: seance, exercise: ex) } },
                                    onReorder: { order in Task { await reorderExercises(seance: seance, order: order) } }
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Programme")
            .navigationBarTitleDisplayMode(.large)
            .keyboardOkButton()
            .sheet(item: $addTarget) { sn in
                AddExerciseSheet(seance: sn.id, inventory: inventory, inventorySchemes: inventorySchemes) { ex, scheme in
                    Task { await addExercise(seance: sn.id, exercise: ex, scheme: scheme) }
                }
            }
            .sheet(item: $editTarget) { target in
                EditSchemeSheet(target: target) { newName, newScheme in
                    Task { await editExercise(seance: target.seance, oldName: target.exercise, newName: newName, scheme: newScheme) }
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: – Load

    private func applyJSON(_ json: [String: Any]) {
        if let raw = json["full_program"] as? [String: [String: Any]] {
            fullProgram = raw.mapValues { $0.compactMapValues { $0 as? String } }
        }
        schedule         = (json["schedule"] as? [String: String]) ?? [:]
        inventory        = (json["inventory"] as? [String]) ?? []
        inventorySchemes = (json["inventory_schemes"] as? [String: String]) ?? [:]
        if let order = json["exercise_order"] as? [String: [String]] {
            exerciseOrder = order
        }
    }

    private func loadData() async {
        let url = URL(string: "\(kBaseURL)/api/programme_data")!
        // Affichage immédiat depuis cache
        if let cached = CacheService.shared.load(for: "programme_data"),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            await MainActor.run { applyJSON(json); isLoading = false }
        }
        // Fetch programme + evening schedule en parallèle
        async let progFetch = URLSession.shared.data(from: url)
        async let eveningFetch = URLSession.shared.data(from: URL(string: "\(kBaseURL)/api/evening_schedule")!)
        if let (data, _) = try? await progFetch,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            CacheService.shared.save(data, for: "programme_data")
            await MainActor.run { applyJSON(json); isLoading = false }
        } else {
            await MainActor.run { isLoading = false }
        }
        if let (eData, _) = try? await eveningFetch,
           let eJson = try? JSONSerialization.jsonObject(with: eData) as? [String: String] {
            await MainActor.run { eveningSchedule = eJson }
        }
    }

    private func saveEveningSchedule() async {
        guard let url = URL(string: "\(kBaseURL)/api/evening_schedule") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: eveningSchedule)
        _ = try? await URLSession.shared.data(for: req)
        CacheService.shared.clear(for: "seance_soir_data")
    }

    // MARK: – Mutations

    private func postProgramme(_ body: [String: Any]) async {
        guard let url = URL(string: "\(kBaseURL)/api/programme") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
        // Invalide les deux caches pour que la séance recharge dans le bon ordre
        CacheService.shared.clear(for: "programme_data")
        CacheService.shared.clear(for: "seance_data")
    }

    private func addExercise(seance: String, exercise: String, scheme: String) async {
        await postProgramme(["action": "add", "jour": seance, "exercise": exercise, "scheme": scheme])
        await MainActor.run {
            fullProgram[seance, default: [:]][exercise] = scheme
            exerciseOrder[seance, default: []].append(exercise)
        }
    }

    private func deleteExercise(seance: String, exercise: String) async {
        await postProgramme(["action": "remove", "jour": seance, "exercise": exercise])
        await MainActor.run {
            fullProgram[seance]?.removeValue(forKey: exercise)
            exerciseOrder[seance]?.removeAll { $0 == exercise }
        }
    }

    private func reorderExercises(seance: String, order: [String]) async {
        // Guard: don't send if order is a subset of the actual exercises
        // (incomplete orderedNames would silently drop missing exercises)
        let actual = fullProgram[seance]?.count ?? 0
        guard order.count >= actual else { return }
        await postProgramme(["action": "reorder", "jour": seance, "ordre": order])
    }

    private func editExercise(seance: String, oldName: String, newName: String, scheme: String) async {
        if oldName != newName {
            // rename synce tous les jours du programme + inventaire
            await postProgramme(["action": "rename", "jour": seance, "old_exercise": oldName, "new_exercise": newName])
            await postProgramme(["action": "scheme", "jour": seance, "exercise": newName, "scheme": scheme])
            await MainActor.run {
                // Swift Dicts are value types — must read, mutate, then write back
                for key in fullProgram.keys {
                    if let oldScheme = fullProgram[key]?[oldName] {
                        fullProgram[key]?[newName] = oldScheme
                        fullProgram[key]?.removeValue(forKey: oldName)
                    }
                }
                fullProgram[seance]?[newName] = scheme
            }
        } else {
            await postProgramme(["action": "scheme", "jour": seance, "exercise": oldName, "scheme": scheme])
            await MainActor.run { fullProgram[seance]?[oldName] = scheme }
        }
    }
}

// MARK: - Models

struct SeanceName: Identifiable {
    let id: String   // id == seance name
}

struct ExerciseTarget: Identifiable {
    var id: String { "\(seance)/\(exercise)" }
    let seance: String
    let exercise: String
    let scheme: String
}

// MARK: - Editable Seance Card

private struct ProgramRowHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct EditableSeanceProgramCard: View {
    let seance: String
    @Binding var exercises: [String: String]
    @Binding var orderedNames: [String]
    let onAdd:     () -> Void
    let onEdit:    (String, String) -> Void
    let onDelete:  (String) -> Void
    let onReorder: ([String]) -> Void

    @State private var expanded    = true
    @State private var dragging:   String? = nil
    @State private var dragY:      CGFloat = 0
    @State private var rowHeights: [String: CGFloat] = [:]

    var color: Color {
        switch seance {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .gray
        }
    }

    /// Exercises in user-defined order; unordered extras appended alphabetically.
    var orderedPairs: [(String, String)] {
        let named = orderedNames.compactMap { n -> (String, String)? in
            guard let s = exercises[n] else { return nil }
            return (n, s)
        }
        let extra = exercises.keys.filter { !orderedNames.contains($0) }.sorted()
        return named + extra.map { ($0, exercises[$0]!) }
    }

    private var proposedDrop: Int {
        guard let name = dragging,
              let from = orderedNames.firstIndex(of: name) else { return 0 }
        let h = (rowHeights[name] ?? 46)
        let steps = Int((dragY / h).rounded())
        return max(0, min(orderedNames.count - 1, from + steps))
    }

    private func shiftFor(_ cardName: String) -> CGFloat {
        guard let dr = dragging, dr != cardName,
              let from = orderedNames.firstIndex(of: dr),
              let idx  = orderedNames.firstIndex(of: cardName) else { return 0 }
        let to = proposedDrop
        let h  = rowHeights[dr] ?? 46
        if from < to, idx > from, idx <= to { return -h }
        if from > to, idx >= to,  idx < from { return  h }
        return 0
    }

    private func dragGesture(for name: String) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { val in
                if dragging == nil {
                    dragging = name
                    triggerImpact(style: .light)
                }
                dragY = val.translation.height
            }
            .onEnded { _ in
                if let dr = dragging {
                    let to = proposedDrop
                    if let from = orderedNames.firstIndex(of: dr), from != to {
                        withAnimation(.spring(response: 0.25)) {
                            orderedNames.move(fromOffsets: IndexSet(integer: from),
                                              toOffset: to > from ? to + 1 : to)
                        }
                        onReorder(orderedNames)
                    }
                }
                withAnimation(.spring(response: 0.25)) { dragging = nil; dragY = 0 }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(seance.prefix(1)))
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(color)
                    )
                Text(seance)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(color)
                Spacer()
                Text("\(exercises.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .cornerRadius(8)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(color)
                        .padding(7)
                        .background(color.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }

            if expanded {
                Divider().background(Color.white.opacity(0.07))

                ForEach(orderedPairs, id: \.0) { name, scheme in
                    let isDragging = dragging == name
                    HStack(spacing: 0) {
                        // ≡ Drag handle
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.5))
                            .frame(width: 40)
                            .contentShape(Rectangle())
                            .gesture(dragGesture(for: name))

                        // Exercise row (tap → edit, trash → delete)
                        ExerciseRow(
                            name:     name,
                            scheme:   scheme,
                            color:    color,
                            onTap:    { onEdit(name, scheme) },
                            onDelete: { onDelete(name) }
                        )
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ProgramRowHeightKey.self,
                                value: [name: geo.size.height]
                            )
                        }
                    )
                    .scaleEffect(isDragging ? 1.02 : 1.0, anchor: .center)
                    .background(isDragging ? color.opacity(0.06) : Color.clear)
                    .offset(y: isDragging ? dragY : shiftFor(name))
                    .zIndex(isDragging ? 1 : 0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: shiftFor(name))
                    .animation(.spring(response: 0.2,  dampingFraction: 0.9),  value: isDragging)

                    if name != orderedPairs.last?.0 {
                        Divider().background(Color.white.opacity(0.04)).padding(.leading, 40)
                    }
                }
                .onPreferenceChange(ProgramRowHeightKey.self) { rowHeights.merge($0) { $1 } }
            }
        }
        .background(Color(hex: "11111c"))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
        .cornerRadius(14)
    }
}

struct ExerciseRow: View {
    let name: String
    let scheme: String
    let color: Color
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Scheme badge
                Text(scheme)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(color.opacity(0.15))
                    .cornerRadius(6)
                    .lineLimit(1)
                // Delete button
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.6))
                        .padding(6)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .alert("Supprimer \(name) ?", isPresented: $confirmDelete) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    let seance: String
    let inventory: [String]
    let inventorySchemes: [String: String]
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scheme = "3x8-12"

    private var filtered: [String] {
        name.isEmpty ? inventory : inventory.filter { $0.localizedCaseInsensitiveContains(name) }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !scheme.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 0) {
                    // Name field (also filters inventory)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Nom de l'exercice...", text: $name)
                            .foregroundColor(.white)
                        if !name.isEmpty {
                            Button { name = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(hex: "11111c"))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Scheme field
                    HStack {
                        Text("Schéma :")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        TextField("ex: 4x6-8", text: $scheme)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color(hex: "11111c"))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // Inventory suggestions
                    if !filtered.isEmpty {
                        List(filtered, id: \.self) { ex in
                            Button {
                                name = ex
                                // Hérite le default_scheme de l'inventaire
                                if let defaultScheme = inventorySchemes[ex] {
                                    scheme = defaultScheme
                                }
                            } label: {
                                HStack {
                                    Text(ex)
                                        .foregroundColor(.white)
                                        .font(.system(size: 14))
                                    Spacer()
                                    if name == ex {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color(hex: "11111c"))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Ajouter à \(seance)")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !scheme.isEmpty else { return }
                        onAdd(trimmed, scheme)
                        dismiss()
                    }
                    .foregroundColor(canSave ? .orange : .gray)
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Edit Scheme Sheet

struct EditSchemeSheet: View {
    let target: ExerciseTarget
    let onSave: (String, String) -> Void  // (newName, newScheme)

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var scheme: String = ""

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !scheme.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nom de l'exercice")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        TextField("Nom", text: $name)
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color(hex: "11111c"))
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schéma de sets/reps")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        TextField("ex: 4x6-8", text: $scheme)
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color(hex: "11111c"))
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }

                    // Suggestions rapides
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["3x5", "4x5-7", "3x8-10", "4x8-10", "3x10-12", "4x12-15", "3x15"], id: \.self) { s in
                                Button { scheme = s } label: {
                                    Text(s)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(scheme == s ? .black : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(scheme == s ? Color.orange : Color(hex: "11111c"))
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Modifier l'exercice")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !scheme.isEmpty else { return }
                        onSave(trimmed, scheme)
                        dismiss()
                    }
                    .foregroundColor(canSave ? .orange : .gray)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear { name = target.exercise; scheme = target.scheme }
    }
}

// MARK: - Week Schedule Card (unchanged)

struct WeekScheduleCard: View {
    let schedule: [String: String]
    let dayNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SEMAINE TYPE")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let seance = schedule[dayNames[i]] ?? "Repos"
                    VStack(spacing: 4) {
                        Text(dayNames[i])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                        Text(seanceShort(seance))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(seanceColor(seance))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(seanceColor(seance).opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }

    private func seanceShort(_ s: String) -> String {
        switch s {
        case "Push A":             return "PSH A"
        case "Pull A":             return "PLL A"
        case "Legs":               return "LEGS"
        case "Push B":             return "PSH B"
        case "Pull B + Full Body": return "PLL B"
        case "Yoga / Tai Chi":     return "YOGA"
        case "Recovery":           return "REC"
        default:                   return "—"
        }
    }

    private func seanceColor(_ s: String) -> Color {
        switch s {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .gray
        }
    }
}

// MARK: - Evening Schedule Card

struct EveningScheduleCard: View {
    @Binding var eveningSchedule: [String: String]
    let dayNames: [String]
    let sessions: [String]
    let onSave: () -> Void

    private let none = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SÉANCE DU SOIR")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.indigo)
                    Text("Optionnel — apparaît sur le dashboard le soir")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "moon.fill").foregroundColor(.indigo).font(.system(size: 14))
            }

            HStack(spacing: 6) {
                ForEach(dayNames, id: \.self) { day in
                    let current = eveningSchedule[day] ?? none
                    Menu {
                        Button(none) {
                            eveningSchedule.removeValue(forKey: day)
                            onSave()
                        }
                        ForEach(sessions, id: \.self) { s in
                            Button(s) {
                                eveningSchedule[day] = s
                                onSave()
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(day)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.gray)
                            Text(shortLabel(current))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(current == none ? Color.gray.opacity(0.4) : sessionColor(current))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background((current == none ? Color.gray : sessionColor(current)).opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }

    private func shortLabel(_ s: String) -> String {
        switch s {
        case "Push A":             return "PSH A"
        case "Pull A":             return "PLL A"
        case "Legs":               return "LEGS"
        case "Push B":             return "PSH B"
        case "Pull B + Full Body": return "PLL B"
        case "Yoga / Tai Chi":     return "YOGA"
        case "Recovery":           return "REC"
        default:                   return "—"
        }
    }

    private func sessionColor(_ s: String) -> Color {
        switch s {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .indigo
        }
    }
}
