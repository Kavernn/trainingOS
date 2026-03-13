import SwiftUI

// MARK: - Models
struct HistoriqueMuscu: Identifiable {
    var id: String { date }
    let date: String
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
    @State private var selectedTab = 0
    @State private var expandedDates: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)

                if isLoading {
                    ProgressView().tint(.orange).scaleEffect(1.3)
                } else {
                    VStack(spacing: 0) {
                        // Tabs
                        HStack(spacing: 8) {
                            TabChip(title: "🏋️ Muscu (\(muscuSessions.count))", selected: selectedTab == 0) { selectedTab = 0 }
                            TabChip(title: "⚡ HIIT (\(hiitSessions.count))", selected: selectedTab == 1) { selectedTab = 1 }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        ScrollView {
                            VStack(spacing: 10) {
                                if selectedTab == 0 {
                                    if muscuSessions.isEmpty {
                                        EmptyHistoriqueView(label: "Aucune séance loggée")
                                    } else {
                                        ForEach(muscuSessions) { session in
                                            MuscuSessionCard(
                                                session: session,
                                                isExpanded: expandedDates.contains(session.date),
                                                onToggle: { toggle(session.date) },
                                                onDelete: { Task { await deleteMuscu(session.date) } }
                                            )
                                            .padding(.horizontal, 16)
                                        }
                                    }
                                } else {
                                    if hiitSessions.isEmpty {
                                        EmptyHistoriqueView(label: "Aucune séance HIIT")
                                    } else {
                                        ForEach(hiitSessions) { session in
                                            HIITSessionCard(
                                                session: session,
                                                onDelete: { Task { await deleteHIIT(session) } }
                                            )
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
    }

    private func toggle(_ date: String) {
        if expandedDates.contains(date) { expandedDates.remove(date) }
        else { expandedDates.insert(date) }
    }

    private func loadData() async {
        // Show cached data first
        if let cached = CacheService.shared.load(for: "historique_data"),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            applyJSON(json)
        }

        isLoading = true
        var req = URLRequest(url: URL(string: "https://training-os-rho.vercel.app/api/historique_data")!)
        req.timeoutInterval = 15
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            CacheService.shared.save(data, for: "historique_data")
            applyJSON(json)
        }
        isLoading = false
    }

    private func applyJSON(_ json: [String: Any]) {
        if let list = json["session_list"] as? [[String: Any]] {
            muscuSessions = list.compactMap { d in
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
                    rpe: d["rpe"] as? Double,
                    comment: d["comment"] as? String ?? "",
                    exos: exos
                )
            }
        }
        if let list = json["hiit_list"] as? [[String: Any]] {
            hiitSessions = list.compactMap { d in
                HIITEntry(
                    date: d["date"] as? String,
                    sessionType: d["session_type"] as? String,
                    rounds: d["rounds"] as? Int,
                    workTime: d["work_time"] as? Int,
                    restTime: d["rest_time"] as? Int,
                    rpe: d["rpe"] as? Double,
                    notes: d["notes"] as? String
                )
            }
        }
    }

    private func deleteMuscu(_ date: String) async {
        try? await APIService.shared.deleteSession(date: date)
        muscuSessions.removeAll { $0.date == date }
    }

    private func deleteHIIT(_ session: HIITEntry) async {
        if let date = session.date, let type = session.sessionType {
            try? await APIService.shared.deleteHIIT(date: date, sessionType: type)
            hiitSessions.removeAll { $0.id == session.id }
        }
    }
}

// MARK: - Muscu Card
struct MuscuSessionCard: View {
    let session: HistoriqueMuscu
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
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
                        Text(formattedDate)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
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
