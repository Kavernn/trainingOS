import SwiftUI

struct NotesView: View {
    @StateObject private var api = APIService.shared
    @State private var showOnlyWithNotes = false

    private var allSessions: [HistoriqueSession] {
        guard let dash = api.dashboard else { return [] }
        return dash.sessions
            .map { key, entry in HistoriqueSession(id: key, date: key, entry: entry) }
            .sorted { $0.date > $1.date }
    }

    private var displayedSessions: [HistoriqueSession] {
        showOnlyWithNotes
            ? allSessions.filter { !($0.entry.comment ?? "").isEmpty }
            : allSessions
    }

    var avgRPE: Double {
        let rpes = api.dashboard?.sessions.values.compactMap(\.rpe) ?? []
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }

    var sessionsWithNotes: Int {
        api.dashboard?.sessions.values.filter { !($0.comment ?? "").isEmpty }.count ?? 0
    }

    // RPE over time (last 20)
    var rpeHistory: [(String, Double)] {
        (api.dashboard?.sessions ?? [:])
            .compactMap { date, entry -> (String, Double)? in
                guard let rpe = entry.rpe else { return nil }
                return (date, rpe)
            }
            .sorted { $0.0 < $1.0 }
            .suffix(20)
            .map { ($0.0, $0.1) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                if api.isLoading {
                    ProgressView().tint(.orange)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // KPIs
                            HStack(spacing: 12) {
                                KPICard(value: "\(allSessions.count)", label: "Séances", color: .orange)
                                KPICard(value: avgRPE > 0 ? String(format: "%.1f", avgRPE) : "—", label: "RPE moy.", color: .purple)
                                KPICard(value: "\(sessionsWithNotes)", label: "Notes", color: .blue)
                            }
                            .padding(.horizontal, 16)

                            // RPE chart
                            if rpeHistory.count >= 3 {
                                RPEChartView(data: rpeHistory)
                                    .padding(.horizontal, 16)
                            }

                            // Filter toggle
                            HStack {
                                Toggle("Avec notes seulement", isOn: $showOnlyWithNotes)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.gray)
                                    .tint(.orange)
                            }
                            .padding(.horizontal, 16)

                            if displayedSessions.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray)
                                    Text("Aucune séance")
                                        .foregroundColor(.gray)
                                }
                                .padding(.top, 40)
                            } else {
                                ForEach(displayedSessions) { session in
                                    NoteCard(session: session)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { if api.dashboard == nil { await api.fetchDashboard() } }
    }
}

struct NoteCard: View {
    let session: HistoriqueSession

    var formattedDate: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_CA"); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: session.date) { f.dateFormat = "EEEE d MMM"; return f.string(from: d).capitalized }
        return session.date
    }

    var rpeColor: Color {
        guard let rpe = session.entry.rpe else { return .orange }
        if rpe >= 8 { return .red }
        if rpe >= 6 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(formattedDate)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let rpe = session.entry.rpe {
                    Text("RPE \(rpe, specifier: "%.1f")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(rpeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(rpeColor.opacity(0.12))
                        .cornerRadius(6)
                }
            }

            if let comment = session.entry.comment, !comment.isEmpty {
                Text(comment)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .italic()
            }

            if let exos = session.entry.exos, !exos.isEmpty {
                Text(exos.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundColor(.gray.opacity(0.6))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Color(hex: "11111c"))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(session.entry.comment?.isEmpty == false ? Color.blue.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}
