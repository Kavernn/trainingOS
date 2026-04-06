import SwiftUI

// MARK: - Models
struct EditableExo {
    let exercise: String
    var weightStr: String
    var reps: String
}

struct HistoriqueMuscu: Identifiable {
    var id: String { "\(date)-\(sessionType)" }
    let date: String
    let sessionType: String   // "morning" | "evening" | "bonus"
    let rpe: Double?
    let comment: String
    let exos: [HistoriqueExo]
}

struct HistoriqueExo: Identifiable {
    var id: String { exercise + "\(weight)" }
    let exercise: String
    let weight: Double
    let reps: String
}

// MARK: - Main View
struct HistoriqueView: View {
    @State private var muscuSessions: [HistoriqueMuscu] = []
    @State private var hiitSessions: [HIITEntry] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var currentOffset = 0
    private let pageSize = 20
    @State private var selectedTab = 0
    @State private var expandedIDs: Set<String> = []
    @State private var editTarget: HistoriqueMuscu? = nil
    @State private var editHIITTarget: HIITEntry? = nil
    @State private var apiError: String? = nil
    @State private var toast: ToastMessage? = nil
    @State private var monthFilter: String? = nil   // "YYYY-MM"
    @State private var showMonthPicker = false
    @State private var pickerDate = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)

                if isLoading {
                    AppLoadingView()
                } else {
                    VStack(spacing: 0) {
                        // Tabs
                        HStack(spacing: 8) {
                            TabChip(title: "🏋️ Muscu (\(muscuSessions.count))", selected: selectedTab == 0) { selectedTab = 0 }
                            TabChip(title: "⚡ HIIT (\(hiitSessions.count))", selected: selectedTab == 1) { selectedTab = 1 }
                            TabChip(title: "📅 Timeline", selected: selectedTab == 2) { selectedTab = 2 }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        // Month filter bar
                        HStack(spacing: 8) {
                            Button {
                                showMonthPicker = true
                            } label: {
                                Label(monthFilter ?? "Tous les mois", systemImage: "calendar")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(monthFilter != nil ? .orange : .gray)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color(hex: "1c1c2e")).cornerRadius(8)
                            }
                            if monthFilter != nil {
                                Button {
                                    monthFilter = nil
                                    Task { await loadData() }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)

                        ScrollView {
                            LazyVStack(spacing: 10) {
                                if selectedTab == 0 {
                                    if muscuSessions.isEmpty {
                                        EmptyHistoriqueView(label: "Aucune séance loggée")
                                    } else {
                                        ForEach(muscuSessions) { session in
                                            MuscuSessionCard(
                                                session: session,
                                                isExpanded: expandedIDs.contains(session.id),
                                                onToggle: { toggle(session.id) },
                                                onDelete: { Task { await deleteMuscu(session) } },
                                                onEdit: { editTarget = session }
                                            )
                                            .padding(.horizontal, 16)
                                        }
                                        if hasMore {
                                            Button {
                                                Task { await loadMore() }
                                            } label: {
                                                Group {
                                                    if isLoadingMore {
                                                        ProgressView().tint(.orange).scaleEffect(0.8)
                                                    } else {
                                                        Text("Charger plus")
                                                            .font(.system(size: 13, weight: .semibold))
                                                            .foregroundColor(.orange)
                                                    }
                                                }
                                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                                .background(Color.orange.opacity(0.08))
                                                .cornerRadius(12)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.horizontal, 16)
                                            .disabled(isLoadingMore)
                                        }
                                    }
                                } else if selectedTab == 1 {
                                    if hiitSessions.isEmpty {
                                        EmptyHistoriqueView(label: "Aucune séance HIIT")
                                    } else {
                                        ForEach(hiitSessions) { session in
                                            HIITSessionCard(
                                                session: session,
                                                onDelete: { Task { await deleteHIIT(session) } },
                                                onEdit: { editHIITTarget = session }
                                            )
                                            .padding(.horizontal, 16)
                                        }
                                    }
                                } else {
                                    // Timeline: merge muscu + hiit sorted by date desc
                                    let timelineItems = buildTimeline()
                                    if timelineItems.isEmpty {
                                        EmptyHistoriqueView(label: "Aucune activité")
                                    } else {
                                        ForEach(timelineItems, id: \.date) { item in
                                            TimelineRow(item: item)
                                                .padding(.horizontal, 16)
                                        }
                                    }
                                }
                                Spacer(minLength: 24)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await loadData() }
        .sheet(item: $editTarget) { session in
            EditSessionSheet(session: session) { date, rpe, comment, exos in
                Task { await saveEdit(date: date, rpe: rpe, comment: comment, sessionType: session.sessionType, exos: exos) }
            }
        }
        .sheet(item: $editHIITTarget) { session in
            EditHIITSheet(session: session) { rpe, rounds, notes in
                Task { await saveHIITEdit(session: session, rpe: rpe, rounds: rounds, notes: notes) }
            }
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(selected: $monthFilter, pickerDate: $pickerDate) {
                showMonthPicker = false
                Task { await loadData() }
            }
        }
        .alert("Erreur", isPresented: Binding(get: { apiError != nil }, set: { if !$0 { apiError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(apiError ?? "") }
        .toast($toast)
    }

    private func toggle(_ id: String) {
        if expandedIDs.contains(id) { expandedIDs.remove(id) }
        else { expandedIDs.insert(id) }
    }

    private func loadData() async {
        currentOffset = 0
        // Only use unfiltered cache when no month filter active
        if monthFilter == nil,
           let cached = CacheService.shared.load(for: "historique_data"),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            applyJSON(json, append: false)
        }

        isLoading = true
        var urlStr = "https://training-os-rho.vercel.app/api/historique_data?limit=\(pageSize)&offset=0"
        if let m = monthFilter { urlStr += "&month=\(m)" }
        var req = URLRequest(url: URL(string: urlStr)!)
        req.timeoutInterval = 15
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if monthFilter == nil { CacheService.shared.save(data, for: "historique_data") }
            applyJSON(json, append: false)
            hasMore = json["has_more"] as? Bool ?? false
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let newOffset = currentOffset + pageSize
        let urlStr = "https://training-os-rho.vercel.app/api/historique_data?limit=\(pageSize)&offset=\(newOffset)"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.timeoutInterval = 15
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            applyJSON(json, append: true)
            hasMore = json["has_more"] as? Bool ?? false
            currentOffset = newOffset
        }
        isLoadingMore = false
    }

    private func applyJSON(_ json: [String: Any], append: Bool) {
        if let list = json["session_list"] as? [[String: Any]] {
            let parsed = list.compactMap { d -> HistoriqueMuscu? in
                guard let date = d["date"] as? String else { return nil }
                let exos = (d["exos"] as? [[String: Any]] ?? []).map {
                    HistoriqueExo(
                        exercise: $0["exercise"] as? String ?? "",
                        weight: $0["weight"] as? Double ?? 0,
                        reps: $0["reps"] as? String ?? ""
                    )
                }
                return HistoriqueMuscu(
                    date: date,
                    sessionType: d["session_type"] as? String ?? "morning",
                    rpe: d["rpe"] as? Double,
                    comment: d["comment"] as? String ?? "",
                    exos: exos
                )
            }
            if append {
                muscuSessions.append(contentsOf: parsed)
            } else {
                muscuSessions = parsed
            }
        }
        if let list = json["hiit_list"] as? [[String: Any]] {
            let parsed = list.compactMap { d in
                HIITEntry(
                    date: d["date"] as? String,
                    sessionType: d["session_type"] as? String,
                    rounds: d["rounds_completes"] as? Int ?? d["rounds"] as? Int,
                    workTime: d["work_time"] as? Int,
                    restTime: d["rest_time"] as? Int,
                    rpe: d["rpe"] as? Double,
                    notes: d["comment"] as? String ?? d["notes"] as? String
                )
            }
            if append {
                hiitSessions.append(contentsOf: parsed)
            } else {
                hiitSessions = parsed
            }
        }
    }

    private func deleteMuscu(_ session: HistoriqueMuscu) async {
        do {
            try await APIService.shared.deleteSession(date: session.date, sessionType: session.sessionType)
            muscuSessions.removeAll { $0.id == session.id }
            toast = ToastMessage(message: "Séance supprimée", style: .success)
        } catch {
            apiError = "Erreur réseau — réessaie"
        }
    }

    private func saveEdit(date: String, rpe: Double?, comment: String, sessionType: String = "morning", exos: [EditableExo]) async {
        let exoPayload: [[String: Any]] = exos.compactMap { e in
            guard let w = Double(e.weightStr.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return ["exercise": e.exercise, "weight": UnitSettings.shared.toStorage(w), "reps": e.reps]
        }
        do {
            try await APIService.shared.editSession(
                date: date, rpe: rpe, comment: comment, sessionType: sessionType,
                exercises: exoPayload.isEmpty ? nil : exoPayload
            )
            if let idx = muscuSessions.firstIndex(where: { $0.date == date && $0.sessionType == sessionType }) {
                let updatedExos: [HistoriqueExo] = exos.compactMap { e in
                    guard let w = Double(e.weightStr.replacingOccurrences(of: ",", with: ".")) else { return nil }
                    return HistoriqueExo(exercise: e.exercise, weight: UnitSettings.shared.toStorage(w), reps: e.reps)
                }
                muscuSessions[idx] = HistoriqueMuscu(
                    date: date, sessionType: sessionType, rpe: rpe, comment: comment,
                    exos: updatedExos.isEmpty ? muscuSessions[idx].exos : updatedExos
                )
            }
            editTarget = nil
        } catch {
            apiError = "Erreur réseau — réessaie"
        }
    }

    private func deleteHIIT(_ session: HIITEntry) async {
        if let date = session.date, let type = session.sessionType {
            do {
                try await APIService.shared.deleteHIIT(date: date, sessionType: type)
                hiitSessions.removeAll { $0.id == session.id }
                CacheService.shared.clear(for: "historique_data")
                toast = ToastMessage(message: "Séance HIIT supprimée", style: .success)
            } catch {
                apiError = "Erreur réseau — réessaie"
            }
        }
    }

    private func saveHIITEdit(session: HIITEntry, rpe: Double, rounds: Int, notes: String) async {
        guard let date = session.date, let type = session.sessionType else { return }
        do {
            let body: [String: Any] = ["date": date, "session_type": type,
                                       "rpe": rpe, "rounds": rounds, "notes": notes]
            _ = try await APIService.shared.hiitEdit(body: body)
            if let idx = hiitSessions.firstIndex(where: { $0.id == session.id }) {
                hiitSessions[idx] = HIITEntry(
                    date: date, sessionType: type,
                    rounds: rounds, workTime: session.workTime, restTime: session.restTime,
                    rpe: rpe, notes: notes.isEmpty ? nil : notes
                )
            }
            editHIITTarget = nil
            CacheService.shared.clear(for: "historique_data")
        } catch {
            apiError = "Erreur réseau — réessaie"
        }
    }

    struct TimelineDay: Identifiable {
        var id: String { date }
        let date: String
        let muscuCount: Int
        let hiitCount: Int
        let exercises: [String]
        let rpe: Double?
    }

    private func buildTimeline() -> [TimelineDay] {
        var days: [String: TimelineDay] = [:]
        for s in muscuSessions {
            let existing = days[s.date]
            days[s.date] = TimelineDay(
                date: s.date,
                muscuCount: (existing?.muscuCount ?? 0) + 1,
                hiitCount:  existing?.hiitCount ?? 0,
                exercises:  (existing?.exercises ?? []) + s.exos.prefix(3).map(\.exercise),
                rpe:        s.rpe ?? existing?.rpe
            )
        }
        for h in hiitSessions {
            guard let date = h.date else { continue }
            let existing = days[date]
            days[date] = TimelineDay(
                date: date,
                muscuCount: existing?.muscuCount ?? 0,
                hiitCount:  (existing?.hiitCount ?? 0) + 1,
                exercises:  existing?.exercises ?? [],
                rpe:        existing?.rpe ?? h.rpe
            )
        }
        return days.values.sorted { $0.date > $1.date }
    }
}

// MARK: - Timeline Row
struct TimelineRow: View {
    let item: HistoriqueView.TimelineDay
    var body: some View {
        HStack(spacing: 12) {
            // Date column
            VStack(spacing: 2) {
                Text(String(item.date.suffix(5)))
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.orange)
                if let rpe = item.rpe {
                    Text("RPE \(String(format: "%.1f", rpe))")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
            }
            .frame(width: 52)

            // Divider dot
            Circle().fill(Color.orange.opacity(0.6)).frame(width: 8, height: 8)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if item.muscuCount > 0 {
                        Label("\(item.muscuCount) muscu", systemImage: "dumbbell.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                    }
                    if item.hiitCount > 0 {
                        Label("\(item.hiitCount) HIIT", systemImage: "bolt.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.red)
                    }
                }
                if !item.exercises.isEmpty {
                    Text(item.exercises.prefix(3).joined(separator: ", "))
                        .font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(hex: "11111c")).cornerRadius(12)
    }
}

// MARK: - Month Picker Sheet
struct MonthPickerSheet: View {
    @Binding var selected: String?
    @Binding var pickerDate: Date
    var onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                VStack(spacing: 20) {
                    DatePicker("Mois", selection: $pickerDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .tint(.orange)
                        .colorScheme(.dark)
                    Button("Appliquer") {
                        selected = Self.formatter.string(from: pickerDate)
                        onApply()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.orange).foregroundColor(.white).cornerRadius(14)
                    .padding(.horizontal, 20)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Filtrer par mois").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Muscu Card
struct MuscuSessionCard: View {
    let session: HistoriqueMuscu
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    @State private var confirmDelete = false

    var rpeColor: Color {
        guard let rpe = session.rpe else { return .gray }
        if rpe >= 8 { return .red }
        if rpe >= 6 { return .orange }
        return .green
    }

    var formattedDate: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_CA"); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: session.date) { f.dateFormat = "EEEE d MMM"; return f.string(from: d).capitalized }
        return session.date
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(formattedDate)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            if session.sessionType == "bonus" {
                                Text("BONUS")
                                    .font(.system(size: 9, weight: .black))
                                    .tracking(1)
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        if !session.exos.isEmpty {
                            Text("\(session.exos.count) exercice\(session.exos.count > 1 ? "s" : "")")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    if let rpe = session.rpe {
                        Text("RPE \(rpe, specifier: "%.1f")")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(rpeColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(rpeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(.leading, 8)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Expanded body
            if isExpanded {
                VStack(spacing: 0) {
                    Divider().background(Color.white.opacity(0.07))

                    if !session.exos.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(session.exos) { exo in
                                HStack {
                                    Text(exo.exercise)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(exo.reps)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    Text(UnitSettings.shared.format(exo.weight))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.orange)
                                        .frame(width: 70, alignment: .trailing)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                Divider().background(Color.white.opacity(0.04)).padding(.leading, 14)
                            }
                        }
                    }

                    if !session.comment.isEmpty {
                        HStack {
                            Image(systemName: "quote.bubble").font(.system(size: 12)).foregroundColor(.blue)
                            Text(session.comment).font(.system(size: 13)).foregroundColor(.gray).italic()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }

                    HStack {
                        Button { onEdit() } label: {
                            Label("Modifier", systemImage: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        Spacer()
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Supprimer", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color(hex: "11111c"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .confirmationDialog("Supprimer cette séance ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }
}

// MARK: - HIIT Card
struct HIITSessionCard: View {
    let session: HIITEntry
    let onDelete: () -> Void
    var onEdit: (() -> Void)? = nil
    @State private var isExpanded = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.sessionType ?? "HIIT")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.orange)
                        if let date = session.date {
                            Text(date)
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    if let rounds = session.rounds {
                        Text("\(rounds) rounds")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(.leading, 8)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(Color.white.opacity(0.07))
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        if let wt = session.workTime {
                            LabelValue(label: "WORK", value: "\(wt)s", color: .orange)
                        }
                        if let rt = session.restTime {
                            LabelValue(label: "REST", value: "\(rt)s", color: .green)
                        }
                        if let rpe = session.rpe {
                            LabelValue(label: "RPE", value: String(format: "%.1f", rpe), color: .purple)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    if let notes = session.notes, !notes.isEmpty {
                        HStack {
                            Image(systemName: "quote.bubble").font(.system(size: 12)).foregroundColor(.blue)
                            Text(notes).font(.system(size: 13)).foregroundColor(.gray).italic()
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                    }

                    HStack {
                        if let onEdit = onEdit {
                            Button(action: onEdit) {
                                Label("Modifier", systemImage: "pencil")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Supprimer", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
        .background(Color(hex: "11111c"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.12), lineWidth: 1))
        .confirmationDialog("Supprimer cette séance HIIT ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }
}

struct LabelValue: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .black)).foregroundColor(color)
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TabChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Color.orange.opacity(0.2) : Color(hex: "191926"))
                .foregroundColor(selected ? .orange : .gray)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1))
        }
    }
}

struct EmptyHistoriqueView: View {
    let label: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 40)).foregroundColor(.gray)
            Text(label).foregroundColor(.gray)
        }
        .padding(.top, 40)
    }
}

// MARK: - Edit Session Sheet
struct EditSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared
    let session: HistoriqueMuscu
    let onSave: (String, Double?, String, [EditableExo]) -> Void

    @State private var rpe: Double
    @State private var comment: String
    @State private var exos: [EditableExo]
    @State private var isSaving = false

    init(session: HistoriqueMuscu, onSave: @escaping (String, Double?, String, [EditableExo]) -> Void) {
        self.session = session
        self.onSave = onSave
        _rpe = State(initialValue: session.rpe ?? 7.0)
        _comment = State(initialValue: session.comment)
        _exos = State(initialValue: session.exos.map {
            EditableExo(exercise: $0.exercise,
                        weightStr: UnitSettings.shared.inputStr($0.weight),
                        reps: $0.reps)
        })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // RPE
                        VStack(spacing: 8) {
                            HStack {
                                Text("RPE SÉANCE")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.1f / 10", rpe))
                                    .font(.system(size: 24, weight: .black))
                                    .foregroundColor(.orange)
                            }
                            Slider(value: $rpe, in: 1...10, step: 0.5)
                                .tint(.orange)
                        }
                        .padding(16)
                        .background(Color(hex: "11111c"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        // Exercises
                        if !exos.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("EXERCICES")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.gray)
                                ForEach(exos.indices, id: \.self) { i in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(exos[i].exercise)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                        HStack(spacing: 10) {
                                            HStack {
                                                TextField("Poids", text: $exos[i].weightStr)
                                                    .keyboardType(.decimalPad)
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.white)
                                                Text(units.label)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.gray)
                                            }
                                            .padding(10)
                                            .background(Color(hex: "191926"))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                            TextField("Reps (ex: 5,5,5)", text: $exos[i].reps)
                                                .font(.system(size: 14))
                                                .foregroundColor(.white)
                                                .padding(10)
                                                .background(Color(hex: "191926"))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color(hex: "11111c"))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        // Comment
                        VStack(alignment: .leading, spacing: 8) {
                            Text("COMMENTAIRE")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                            TextField("Note, ressenti…", text: $comment, axis: .vertical)
                                .lineLimit(3...6)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color(hex: "11111c"))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            isSaving = true
                            onSave(session.date, rpe, comment, exos)
                        } label: {
                            HStack {
                                if isSaving { ProgressView().tint(.black).scaleEffect(0.8) }
                                Text("Enregistrer")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.orange)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isSaving)
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Modifier la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Edit HIIT Sheet
struct EditHIITSheet: View {
    let session: HIITEntry
    let onSave: (Double, Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Double
    @State private var rounds: Int
    @State private var notes: String
    @State private var isSaving = false

    init(session: HIITEntry, onSave: @escaping (Double, Int, String) -> Void) {
        self.session = session
        self.onSave = onSave
        _rpe = State(initialValue: session.rpe ?? 7)
        _rounds = State(initialValue: session.rounds ?? 4)
        _notes = State(initialValue: session.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ROUNDS").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                            Stepper("\(rounds) rounds", value: $rounds, in: 1...20)
                                .foregroundColor(.white)
                                .padding(12).background(Color(hex: "11111c")).clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("RPE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.1f", rpe)).font(.system(size: 15, weight: .black)).foregroundColor(.orange)
                            }
                            Slider(value: $rpe, in: 6...10, step: 0.5).tint(.orange)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.gray)
                            TextField("Notes…", text: $notes, axis: .vertical)
                                .lineLimit(3...5).font(.system(size: 14)).foregroundColor(.white)
                                .padding(12).background(Color(hex: "11111c")).clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            isSaving = true
                            onSave(rpe, rounds, notes)
                        } label: {
                            HStack {
                                if isSaving { ProgressView().tint(.black).scaleEffect(0.8) }
                                Text("Sauvegarder").font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.black).frame(maxWidth: .infinity).padding(14)
                            .background(Color.orange).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Modifier le HIIT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }
}
