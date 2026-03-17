import SwiftUI

struct SelfCareView: View {
    @State private var today: SelfCareToday?
    @State private var streaks: [SelfCareStreak] = []
    @State private var pending: Set<String> = []   // IDs cochés localement
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var isSaving = false

    private var completedIds: Set<String> {
        Set(today?.completed ?? [])
    }

    var body: some View {
        List {
            // Progression du jour
            if let today {
                Section {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Aujourd'hui")
                                .font(.headline)
                            Spacer()
                            Text("\(Int((today.rate) * 100))%")
                                .font(.title3.bold())
                                .foregroundColor(today.rate >= 0.7 ? .green : .orange)
                        }
                        ProgressView(value: today.rate)
                            .tint(today.rate >= 0.7 ? .green : .orange)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Habitudes du jour
            Section("Habitudes") {
                if isLoading {
                    ProgressView()
                } else {
                    ForEach(today?.habits ?? []) { habit in
                        HabitRow(
                            habit: habit,
                            isDone: completedIds.contains(habit.id) || pending.contains(habit.id),
                            onToggle: { toggle(habit.id) }
                        )
                    }
                }
            }

            // Streaks
            if !streaks.isEmpty {
                Section("Streaks") {
                    ForEach(streaks.prefix(5)) { streak in
                        StreakRow(streak: streak)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Self-Care")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { Task { await loadData() } }) {
            AddHabitSheet()
        }
        .task { await loadData() }
    }

    private func loadData() async {
        async let t = try? APIService.shared.fetchSelfCareToday()
        async let s = try? APIService.shared.fetchSelfCareStreaks()
        let (tod, str) = await (t, s)
        await MainActor.run {
            today     = tod
            streaks   = str ?? []
            pending   = Set(tod?.completed ?? [])
            isLoading = false
        }
    }

    private func toggle(_ id: String) {
        if pending.contains(id) {
            pending.remove(id)
        } else {
            pending.insert(id)
        }
        saveLog()
    }

    private func saveLog() {
        isSaving = true
        Task {
            let result = try? await APIService.shared.submitSelfCareLog(habitIds: Array(pending))
            await MainActor.run {
                if let result { today = result }
                isSaving = false
            }
        }
    }
}

private struct HabitRow: View {
    let habit: SelfCareHabit
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDone ? .green : .secondary)
                    .font(.title3)
                Image(systemName: habit.icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.subheadline)
                        .strikethrough(isDone, color: .secondary)
                        .foregroundColor(isDone ? .secondary : .primary)
                    Text(habit.category.capitalized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

private struct StreakRow: View {
    let streak: SelfCareStreak

    var body: some View {
        HStack {
            Image(systemName: streak.habitIcon)
                .foregroundColor(.orange)
                .frame(width: 20)
            Text(streak.habitName)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("\(streak.currentStreak) j")
                    .font(.caption.bold())
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Add Habit Sheet

private struct AddHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "star.fill"
    @State private var category = "mental"
    @State private var isSubmitting = false

    private let categories = ["mental", "physique", "social", "sommeil"]
    private let icons = ["star.fill", "heart.fill", "book.fill", "drop.fill",
                         "figure.walk", "moon.fill", "phone.fill", "fork.knife"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom de l'habitude") {
                    TextField("Ex: Prendre l'air 10 min", text: $name)
                }
                Section("Catégorie") {
                    Picker("Catégorie", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Icône") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(icons, id: \.self) { ic in
                            Button {
                                icon = ic
                            } label: {
                                Image(systemName: ic)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(icon == ic ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Nouvelle habitude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { submit() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            _ = try? await APIService.shared.addSelfCareHabit(
                name:     name.trimmingCharacters(in: .whitespaces),
                icon:     icon,
                category: category
            )
            await MainActor.run { dismiss() }
        }
    }
}
