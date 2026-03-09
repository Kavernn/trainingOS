import SwiftUI

struct HistoriqueView: View {
    @StateObject private var api = APIService.shared

    private var sessions: [HistoriqueSession] {
        guard let dash = api.dashboard else { return [] }
        return dash.sessions
            .map { HistoriqueSession(id: $0.key, date: $0.key, entry: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                List {
                    ForEach(sessions) { session in
                        SessionRowView(session: session)
                            .listRowBackground(Color(hex: "11111c"))
                            .listRowSeparatorTint(Color.white.opacity(0.07))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { if api.dashboard == nil { await api.fetchDashboard() } }
    }
}

struct SessionRowView: View {
    let session: HistoriqueSession

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: session.date) {
            formatter.dateFormat = "EEEE d MMM"
            return formatter.string(from: date).capitalized
        }
        return session.date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formattedDate)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let rpe = session.entry.rpe {
                    Text("RPE \(rpe, specifier: "%.1f")")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(6)
                }
            }
            if let exos = session.entry.exos, !exos.isEmpty {
                Text(exos.prefix(4).joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            if let comment = session.entry.comment, !comment.isEmpty {
                Text(comment)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .italic()
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}
