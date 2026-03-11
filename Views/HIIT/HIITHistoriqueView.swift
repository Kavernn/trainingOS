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
                    ProgressView().tint(.orange)
                } else if hiitLog.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "figure.run").font(.system(size: 48)).foregroundColor(.gray)
                        Text("Aucune session HIIT").foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Stats
                            HStack(spacing: 12) {
                                KPICard(value: "\(totalSessions)", label: "Sessions", color: .red)
                                KPICard(value: avgRPE > 0 ? String(format: "%.1f", avgRPE) : "—", label: "RPE moy.", color: .orange)
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
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(entry.date ?? "—")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                Spacer()
                if let rpe = entry.rpe {
                    Text("RPE \(rpe, specifier: "%.1f")")
                        .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                if let w = entry.workTime {
                    Label("\(w)s work", systemImage: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
                if let r = entry.restTime {
                    Label("\(r)s rest", systemImage: "zzz")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
            }

            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12))
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
