import SwiftUI

private struct DefaultHabitSuggestion {
    let name: String
    let icon: String
    let category: String
}

private let selfCareDefaultSuggestions: [DefaultHabitSuggestion] = [
    .init(name: "Prendre l'air 10 min",             icon: "wind",      category: "physique"),
    .init(name: "Écrans off 30 min avant le lit",   icon: "moon.fill", category: "sommeil"),
    .init(name: "Donner des nouvelles à quelqu'un", icon: "phone.fill", category: "social"),
    .init(name: "Lire 15 min",                      icon: "book.fill", category: "mental"),
]

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
                                .foregroundColor(today.rate >= 0.7 ? Color.appSuccess : Color.appWarning)
                        }
                        ProgressView(value: today.rate)
                            .tint(today.rate >= 0.7 ? Color.appSuccess : Color.appWarning)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Habitudes du jour
            Section("Habitudes") {
                if isLoading {
                    ProgressView()
                } else if (today?.habits ?? []).isEmpty {
                    ForEach(selfCareDefaultSuggestions, id: \.name) { suggestion in
                        Button { addDefaultHabit(suggestion) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: suggestion.icon)
                                    .foregroundColor(Color.appSuccess)
                                    .frame(width: 20)
                                Text(suggestion.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundColor(Color.forge)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Ces habitudes sont un point de départ. Ajoute, modifie ou retire ce qui ne te correspond pas.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(today?.habits ?? []) { habit in
                        HabitRow(
                            habit: habit,
                            isDone: completedIds.contains(habit.id) || pending.contains(habit.id),
                            onToggle: { toggle(habit) }
                        )
                    }
                }
            }

            // Consistance
            if !streaks.isEmpty {
                Section {
                    ForEach(streaks.prefix(5)) { streak in
                        StreakRow(streak: streak)
                    }
                    Text("Un jour de pause ne remet pas à zéro ton progrès.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Consistance")
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
        // sequential — async let LIFO crash on iOS 26 beta
        let tod = try? await APIService.shared.fetchSelfCareToday()
        let str = try? await APIService.shared.fetchSelfCareStreaks()
        await MainActor.run {
            today     = tod
            streaks   = str ?? []
            pending   = Set(tod?.completed ?? [])
            isLoading = false
        }
    }

    private func toggle(_ habit: SelfCareHabit) {
        if pending.contains(habit.id) {
            pending.remove(habit.id)
        } else {
            pending.insert(habit.id)
            ActionFeedbackManager.shared.show(.habitCompleted(name: habit.name))
        }
        saveLog()
    }

    private func addDefaultHabit(_ suggestion: DefaultHabitSuggestion) {
        Task {
            _ = try? await APIService.shared.addSelfCareHabit(
                name: suggestion.name, icon: suggestion.icon, category: suggestion.category
            )
            await loadData()
        }
    }

    private func saveLog() {
        isSaving = true
        Task {
            let result = try? await APIService.shared.submitSelfCareLog(habitIds: Array(pending))
            await MainActor.run {
                if let result { today = result }
                isSaving = false
                BehaviorTracker.shared.record(.selfCareCheck)
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
                    .foregroundColor(isDone ? .statusGreen : .secondary)
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
                .foregroundColor(Color.forge)
                .frame(width: 20)
            Text(streak.habitName)
                .font(.subheadline)
            Spacer()
            Text("\(streak.currentStreak) j actifs")
                .font(.caption.bold())
                .foregroundColor(Color.forge)
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Nouvelle habitude")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!name.trimmingCharacters(in: .whitespaces).isEmpty)
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
