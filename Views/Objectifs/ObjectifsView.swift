import SwiftUI
import UserNotifications

struct ObjectifsView: View {
    @State private var objectifs: [ObjectifEntry] = []
    @State private var isLoading = true
    @State private var showAddGoal = false
    @State private var showArchived = false
    @State private var selectedObjectif: ObjectifEntry? = nil

    private var active:   [ObjectifEntry] { objectifs.filter { !$0.achieved && !$0.archived } }
    private var achieved: [ObjectifEntry] { objectifs.filter { $0.achieved && !$0.archived } }
    private var archived: [ObjectifEntry] { objectifs.filter { $0.archived } }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)

                if isLoading {
                    ProgressView().tint(.orange).scaleEffect(1.3)
                } else if objectifs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "target").font(.system(size: 48)).foregroundColor(.gray)
                        Text("Aucun objectif").foregroundColor(.gray)
                        Button("Ajouter un objectif") { showAddGoal = true }.foregroundColor(.orange)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            // Active
                            if !active.isEmpty {
                                SectionHeader(title: "EN COURS")
                                ForEach(Array(active.enumerated()), id: \.1.id) { i, obj in
                                    ObjectifCard(obj: obj, onArchive: nil)
                                        .onTapGesture { selectedObjectif = obj }
                                        .appearAnimation(delay: Double(i) * 0.06)
                                }
                            }

                            // Achieved
                            if !achieved.isEmpty {
                                SectionHeader(title: "ATTEINTS (\(achieved.count))")
                                ForEach(Array(achieved.enumerated()), id: \.1.id) { i, obj in
                                    ObjectifCard(obj: obj, onArchive: {
                                        Task { await archiveGoal(obj) }
                                    })
                                    .appearAnimation(delay: Double(i) * 0.06)
                                }
                            }

                            // Archived (collapsible)
                            if !archived.isEmpty {
                                Button {
                                    withAnimation { showArchived.toggle() }
                                } label: {
                                    HStack {
                                        SectionHeader(title: "ARCHIVÉS (\(archived.count))")
                                        Spacer()
                                        Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 11)).foregroundColor(.gray)
                                    }
                                }
                                .buttonStyle(.plain)
                                if showArchived {
                                    ForEach(Array(archived.enumerated()), id: \.1.id) { i, obj in
                                        ObjectifCard(obj: obj, onArchive: nil)
                                            .opacity(0.5)
                                            .appearAnimation(delay: Double(i) * 0.04)
                                    }
                                }
                            }

                            Spacer(minLength: 80)
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Objectifs")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddGoal) {
                AddGoalSheet { await loadData() }
            }
            .sheet(item: $selectedObjectif) { obj in
                EditGoalSheet(obj: obj) { await loadData() }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showAddGoal = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        objectifs = (try? await APIService.shared.fetchObjectifsData()) ?? []
        isLoading = false
    }

    private func archiveGoal(_ obj: ObjectifEntry) async {
        try? await APIService.shared.archiveObjectif(exercise: obj.exercise)
        if let idx = objectifs.firstIndex(where: { $0.id == obj.id }) {
            objectifs[idx] = ObjectifEntry(
                exercise: obj.exercise, current: obj.current, goal: obj.goal,
                achieved: obj.achieved, deadline: obj.deadline, note: obj.note, archived: true
            )
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold)).tracking(2)
            .foregroundColor(.gray)
    }
}

struct ObjectifCard: View {
    let obj: ObjectifEntry
    var onArchive: (() -> Void)? = nil
    @ObservedObject private var units = UnitSettings.shared
    @State private var celebrate = false

    var pct: Double {
        guard obj.goal > 0 else { return 0 }
        return min(obj.current / obj.goal, 1.0)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(obj.exercise)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    if !obj.deadline.isEmpty {
                        Text("Deadline: \(obj.deadline)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                if obj.achieved {
                    HStack(spacing: 8) {
                        Label("Atteint", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                            .scaleEffect(celebrate ? 1.0 : 0.4)
                            .opacity(celebrate ? 1.0 : 0)
                        if let archive = onArchive {
                            Button(action: archive) {
                                Label("Archiver", systemImage: "archivebox")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color(hex: "191926")).cornerRadius(8)
                            }
                        }
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTUEL")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    Text(units.format(obj.current))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(obj.achieved ? .green : .orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("OBJECTIF")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(.gray)
                    Text(units.format(obj.goal))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "191926"))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(obj.achieved ? Color.green : Color.orange)
                        .frame(width: geo.size.width * pct, height: 8)
                        .animation(.easeOut(duration: 0.5), value: pct)
                }
            }
            .frame(height: 8)

            Text("\(Int(pct * 100))% complété")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            }
            .padding(16)
            .glassCardAccent(obj.achieved ? .green : .orange)
            .cornerRadius(16)
            .scaleEffect(celebrate ? 1.03 : 1.0)

            // Sparkles overlay on achievement
            if celebrate {
                ForEach(0..<6, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: CGFloat([10, 14, 8, 12, 10, 8][i])))
                        .foregroundColor(.green.opacity(0.7))
                        .offset(
                            x: CGFloat([-40, 40, -60, 60, 0, -20][i]),
                            y: CGFloat([-20, -15, 5, 10, -30, 20][i])
                        )
                        .opacity(celebrate ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(Double(i) * 0.05), value: celebrate)
                }
            }
        }
        .onAppear {
            if obj.achieved {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                    celebrate = true
                }
            }
        }
    }
}

struct AddGoalSheet: View {
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared

    @State private var exercise = ""
    @State private var goalWeight = ""
    @State private var deadline = Date()
    @State private var apiError: String? = nil

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                Form {
                    Section {
                        TextField("Nom de l'exercice", text: $exercise)
                            .foregroundColor(.white)
                        TextField("Poids objectif (\(units.label))", text: $goalWeight)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.white)
                        DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                            .foregroundColor(.white)
                            .tint(.orange)
                    }
                    .listRowBackground(Color(hex: "11111c"))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Nouvel objectif")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") {
                        guard !exercise.isEmpty, let gw = Double(goalWeight).map({ units.toStorage($0) }) else { return }
                        let deadlineStr = Self.isoFormatter.string(from: deadline)
                        Task {
                            do {
                                try await APIService.shared.setGoal(exercise: exercise, goalWeight: gw, deadline: deadlineStr)
                                scheduleGoalDeadlineNotifications(exercise: exercise, deadlineStr: deadlineStr)
                                await onSaved()
                                dismiss()
                            } catch {
                                apiError = "Erreur réseau — réessaie"
                            }
                        }
                    }
                    .foregroundColor(.orange)
                    .fontWeight(.semibold)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
        }
        .presentationDetents([.medium])
    }
}

struct EditGoalSheet: View {
    let obj: ObjectifEntry
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared

    @State private var goalWeight: String
    @State private var deadline: Date
    @State private var apiError: String? = nil

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    init(obj: ObjectifEntry, onSaved: @escaping () async -> Void) {
        self.obj = obj
        self.onSaved = onSaved
        _goalWeight = State(initialValue: UnitSettings.shared.inputStr(obj.goal))
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        _deadline = State(initialValue: f.date(from: obj.deadline) ?? Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 20) {
                    Text(obj.exercise)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("POIDS OBJECTIF (\(units.label.uppercased()))")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            TextField("0.0", text: $goalWeight)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("DEADLINE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            DatePicker("", selection: $deadline, displayedComponents: .date)
                                .labelsHidden()
                                .tint(.orange)
                                .padding(12)
                                .background(Color(hex: "191926"))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)

                    Button(action: save) {
                        Text("Sauvegarder")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundColor(.orange)
                }
            }
            .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(apiError ?? "") }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let gw = Double(goalWeight).map({ units.toStorage($0) }) else { return }
        let deadlineStr = Self.isoFormatter.string(from: deadline)
        Task {
            do {
                try await APIService.shared.setGoal(exercise: obj.exercise, goalWeight: gw, deadline: deadlineStr)
                scheduleGoalDeadlineNotifications(exercise: obj.exercise, deadlineStr: deadlineStr)
                await onSaved()
                dismiss()
            } catch {
                apiError = "Erreur réseau — réessaie"
            }
        }
    }
}

// MARK: - Goal deadline notifications helper

/// Schedules J-7 and J-1 notifications for a goal deadline.
/// Re-scheduling replaces any existing notification for the same goal.
private func scheduleGoalDeadlineNotifications(exercise: String, deadlineStr: String) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        guard granted else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let deadline = f.date(from: deadlineStr) else { return }
        let now = Date()

        let alerts: [(daysOffset: Int, title: String, body: String)] = [
            (-7, "Objectif — 7 jours restants 🎯",  "Il te reste 7 jours pour atteindre ton objectif de \(exercise)."),
            (-1, "Objectif — demain dernier jour !",  "Dernière chance pour \(exercise) 🎯 Go !"),
        ]

        for (offset, title, body) in alerts {
            let fireDate = Calendar.current.date(byAdding: .day, value: offset, to: deadline)!
            guard fireDate > now else { continue }

            let content       = UNMutableNotificationContent()
            content.title     = title
            content.body      = body
            content.sound     = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            var triggerComps  = comps
            triggerComps.hour   = 9
            triggerComps.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
            let id      = "goal_\(offset < -1 ? "7d" : "1d")_\(exercise.lowercased().replacingOccurrences(of: " ", with: "_"))"
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
