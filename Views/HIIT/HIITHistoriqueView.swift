import SwiftUI

struct HIITHistoriqueView: View {
    @State private var hiitLog: [HIITEntry] = []
    @State private var isLoading = true
    @State private var pendingDeletes: Set<String> = []
    @State private var queuedDeletes:  Set<String> = []
    @State private var deleteError: String?

    var totalSessions: Int { hiitLog.count }
    var avgRPE: Double {
        let rpes = hiitLog.compactMap(\.rpe)
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .statusRed)

                if isLoading {
                    ProgressView().tint(Color.forge)
                } else if hiitLog.isEmpty {
                    EmptyStateView(icon: "figure.run", title: "Aucune session HIIT", compact: true)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Stats
                            HStack(spacing: 12) {
                                KPICard(value: "\(totalSessions)", label: "Sessions", color: .statusRed)
                                KPICard(value: avgRPE > 0 ? String(format: "%.1f", avgRPE) : "—", label: "RPE moy.", color: Color.forge)
                            }
                            .padding(.horizontal, 16)

                            if !queuedDeletes.isEmpty {
                                Text("\(queuedDeletes.count) suppression\(queuedDeletes.count > 1 ? "s" : "") en attente — hors ligne")
                                    .font(.appCaption)
                                    .foregroundColor(.appTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                            }
                            if let msg = deleteError {
                                Text(msg)
                                    .font(.appCaption)
                                    .foregroundColor(.appDanger)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                            }

                            // Log entries
                            ForEach(hiitLog) { entry in
                                HIITEntryCard(
                                    entry: entry,
                                    isDisabled: pendingDeletes.contains(entry.id)
                                             || queuedDeletes.contains(entry.id)
                                ) {
                                    Task { await delete(entry) }
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
        .onReceive(SyncManager.shared.$pendingCount) { count in
            // File vidée (succès OU rejet 4xx) : on recharge pour l'état serveur réel.
            if count == 0 && !queuedDeletes.isEmpty {
                queuedDeletes.removeAll()
                Task { await loadData() }
            }
        }
    }

    private func loadData() async {
        isLoading = true
        hiitLog = (try? await APIService.shared.fetchHIITData()) ?? []
        isLoading = false
    }

    private func delete(_ entry: HIITEntry) async {
        pendingDeletes.insert(entry.id)
        deleteError = nil
        defer { pendingDeletes.remove(entry.id) }

        do {
            try await APIService.shared.deleteHIIT(
                date: entry.date ?? "",
                sessionType: entry.sessionType ?? ""
            )
            // Succès serveur : la ligne disparaît APRÈS confirmation via loadData.
            await loadData()
        } catch APIError.queuedOffline {
            // Bouton désactivé jusqu'au flush SyncManager (observer onReceive).
            queuedDeletes.insert(entry.id)
        } catch APIError.serverError(_, let msg) {
            deleteError = msg.isEmpty ? "Erreur serveur" : msg
        } catch {
            deleteError = "Erreur réseau — réessaie"
        }
    }
}

struct HIITEntryCard: View {
    let entry: HIITEntry
    var isDisabled: Bool = false
    var onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sessionType ?? "HIIT")
                        .font(.appBody.weight(.bold))
                        .foregroundColor(.appTextPrimary)
                    Text(entry.date ?? "—")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
                Spacer()
                if let rpe = entry.rpe {
                    Text("RPE \(rpe, specifier: "%.1f")")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.statusRed)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.statusRed.opacity(0.12))
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
                        .foregroundColor(.statusGreen)
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
        .glassCard()
        .cornerRadius(12)
        .contextMenu {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .disabled(isDisabled)
        }
        .confirmationDialog("Supprimer cette session ?", isPresented: $showDeleteConfirm) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }
}
