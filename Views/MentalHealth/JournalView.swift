import SwiftUI

struct JournalView: View {
    @State private var entries: [JournalEntry] = []
    @State private var todayPrompt: String = ""
    @State private var showEntrySheet = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var nextOffset: Int? = nil
    @State private var searchText = ""

    private var filtered: [JournalEntry] {
        guard !searchText.isEmpty else { return entries }
        let q = searchText.lowercased()
        return entries.filter {
            $0.content.lowercased().contains(q) || $0.prompt.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                // Prompt du jour
                if !todayPrompt.isEmpty {
                    Section {
                        Button { showEntrySheet = true } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Prompt du jour", systemImage: "lightbulb.fill")
                                    .font(.caption.bold())
                                    .foregroundColor(.yellow)
                                Text(todayPrompt)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                Text("Appuie pour écrire →")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Historique
                if !filtered.isEmpty {
                    Section("Entrées récentes") {
                        ForEach(filtered) { entry in
                            JournalEntryRow(entry: entry)
                        }
                        if hasMore && searchText.isEmpty {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoadingMore {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Text("Charger plus…")
                                            .font(.subheadline)
                                            .foregroundColor(.indigo)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if !isLoading {
                    Section {
                        Text("Aucune entrée trouvée.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Rechercher dans le journal")
            .overlay {
                if isLoading { ProgressView() }
            }

            // FAB
            Button { showEntrySheet = true } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(18)
                    .background(Color.indigo)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(24)
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEntrySheet, onDismiss: { Task { await loadData() } }) {
            JournalEntrySheet(prompt: todayPrompt)
        }
        .task { await loadData() }
    }

    private func loadData() async {
        async let prompt = try? APIService.shared.fetchJournalPrompt()
        async let page   = try? APIService.shared.fetchJournalEntries()
        let (p, pg) = await (prompt, page)
        await MainActor.run {
            todayPrompt = p ?? ""
            if let pg {
                entries    = pg.items
                hasMore    = pg.hasMore
                nextOffset = pg.nextOffset
            }
            isLoading = false
        }
    }

    private func loadMore() async {
        guard let offset = nextOffset, !isLoadingMore else { return }
        isLoadingMore = true
        if let pg = try? await APIService.shared.fetchJournalEntries(offset: offset) {
            entries.append(contentsOf: pg.items)
            hasMore    = pg.hasMore
            nextOffset = pg.nextOffset
        }
        isLoadingMore = false
    }
}

private struct JournalEntryRow: View {
    let entry: JournalEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(entry.prompt)
                .font(.caption.italic())
                .foregroundColor(.secondary)
                .lineLimit(expanded ? nil : 1)
            Text(entry.content)
                .font(.subheadline)
                .lineLimit(expanded ? nil : 2)
        }
        .padding(.vertical, 4)
        .onTapGesture { withAnimation { expanded.toggle() } }
    }
}

// MARK: - Entry Sheet

struct JournalEntrySheet: View {
    let prompt: String

    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var moodEnabled = false
    @State private var moodValue: Double = 5
    @State private var isSubmitting = false
    @State private var errorMsg: String?

    private var moodInt: Int { Int(moodValue.rounded()) }

    private var moodColor: Color {
        switch moodInt {
        case 1...3: return .red
        case 4...6: return .orange
        case 7...8: return .yellow
        default:    return .green
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    Text(prompt.isEmpty ? "Écris librement…" : prompt)
                        .font(.subheadline.italic())
                        .foregroundColor(.secondary)
                }
                Section("Ton entrée") {
                    TextField("Commence à écrire…", text: $content, axis: .vertical)
                        .lineLimit(6...20)
                }
                Section {
                    Toggle(isOn: $moodEnabled.animation(.easeInOut(duration: 0.2))) {
                        Label("Humeur du moment", systemImage: "face.smiling")
                            .foregroundColor(.indigo)
                    }
                    .tint(.indigo)

                    if moodEnabled {
                        VStack(spacing: 12) {
                            Text("\(moodInt)")
                                .font(.system(size: 42, weight: .black))
                                .foregroundColor(moodColor)
                                .frame(maxWidth: .infinity)

                            Slider(value: $moodValue, in: 1...10, step: 1)
                                .tint(moodColor)

                            HStack {
                                Text("😞 Très bas")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Excellent 😄")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Humeur (optionnel)")
                }
                if let err = errorMsg {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Nouvelle entrée")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardOkButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { submit() }
                        .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            do {
                _ = try await APIService.shared.submitJournalEntry(
                    prompt: prompt,
                    content: content,
                    moodScore: moodEnabled ? moodInt : nil
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}
