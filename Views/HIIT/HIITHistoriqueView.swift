import SwiftUI

struct HIITHistoriqueView: View {
    @State private var hiitLog: [HIITEntry] = []
    @State private var isLoading = true

    var totalSessions: Int { hiitLog.count }
    var avgRPE: Double {
        let rpes = hiitLog.compactMap(\.rpe)
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .red)

                if isLoading {
                    ProgressView().tint(Color.forge)
                } else if hiitLog.isEmpty {
                    EmptyStateView(icon: "figure.run", title: "Aucune session HIIT", compact: true)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Stats
                            HStack(spacing: 12) {
                                KPICard(value: "\(totalSessions)", label: "Sessions", color: .red)
                                KPICard(value: avgRPE > 0 ? String(format: "%.1f", avgRPE) : "—", label: "RPE moy.", color: Color.forge)
                            }
                            .padding(.horizontal, 16)

                            // Log entries
                            ForEach(hiitLog) { entry in
                                HIITEntryCard(entry: entry) {
                                    Task {
                                        try? await APIService.shared.deleteHIIT(
                                            date: entry.date ?? "",
                                            sessionType: entry.sessionType ?? ""
                                        )
                                        await loadData()
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("HIIT")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        hiitLog = (try? await APIService.shared.fetchHIITData()) ?? []
        isLoading = false
    }
}

struct HIITEntryCard: View {
    let entry: HIITEntry
    var onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sessionType ?? "HIIT")
                        .font(.appBody.weight(.bold))
                        .foregroundColor(.white)
                    Text(entry.date ?? "—")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
                Spacer()
                if let rpe = entry.rpe {
                    Text("RPE \(rpe, specifier: "%.1f")")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(6)
                }
            }

            HStack(spacing: 16) {
                if let rounds = entry.rounds {
                    Label("\(rounds) rounds", systemImage: "repeat")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
                if let w = entry.workTime {
                    Label("\(w)s work", systemImage: "bolt.fill")
                        .font(.appCaption)
                        .foregroundColor(Color.forge)
                }
                if let r = entry.restTime {
                    Label("\(r)s rest", systemImage: "zzz")
                        .font(.appCaption)
                        .foregroundColor(.green)
                }
            }

            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.appCaption)
                    .foregroundColor(.gray)
                    .italic()
            }
        }
        .padding(14)
        .glassCardAccent(.red)
        .cornerRadius(12)
        .contextMenu {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .confirmationDialog("Supprimer cette session ?", isPresented: $showDeleteConfirm) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }
}
