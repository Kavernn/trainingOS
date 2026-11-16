import SwiftUI

// MARK: - SelfCareView

struct SelfCareView: View {
    @State private var todayState   = Loadable<SelfCareToday>()
    @State private var streaksState = Loadable<[SelfCareStreak]>()
    @State private var pending: Set<String> = []     // IDs cochés localement (optimiste)
    @State private var showAddSheet = false
    @State private var isSubmitting = false
    @State private var submitError:  String?

    private var today:    SelfCareToday?  { todayState.value }
    private var streaks:  [SelfCareStreak] { streaksState.value ?? [] }
    private var habits:   [SelfCareHabit]  { today?.habits ?? [] }
    private var rate:     Double           { today?.rate ?? 0 }

    private var allStates: [any LoadableStateView] { [todayState, streaksState] }
    private var topFailureAggregator: LoadableAggregator {
        LoadableAggregator(groups: [
            LoadableRetryGroup(states: allStates, retry: { await loadData() })
        ])
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: Color.forge)

            if todayState.isInitialLoad && streaksState.isInitialLoad {
                AppLoadingView()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        ErrorBannerView.fromAggregator(topFailureAggregator)
                            .padding(.horizontal, 16)

                        progressCard
                        habitsSection
                        streaksSection

                        if let err = submitError {
                            Text(err)
                                .font(.appCaption)
                                .foregroundColor(Color.appDanger)
                                .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.vertical, 16)
                }
                .refreshable { await loadData() }
            }
        }
        .navigationTitle("Self-care")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { Task { await loadData() } }) {
            SelfCareAddHabitSheet()
        }
        .task { await loadData() }
    }

    // MARK: Sections

    private var progressCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Aujourd'hui")
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(Color.appOnSurface)
                Spacer()
                Text("\(Int(rate * 100))%")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundColor(rate >= 0.7 ? Color.appSuccess : Color.appWarning)
            }
            ProgressView(value: rate)
                .tint(rate >= 0.7 ? Color.appSuccess : Color.appWarning)
        }
        .padding(14)
        .glassCard()
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HABITUDES")
                .font(.appCaption.weight(.bold))
                .tracking(2).foregroundColor(.gray)
                .padding(.horizontal, 16)

            if habits.isEmpty {
                Text("Ajoute ta première habitude avec le + en haut.")
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(0.6))
                    .padding(.horizontal, 16)
            } else {
                ForEach(habits) { h in
                    habitRow(h).padding(.horizontal, 16)
                }
            }
        }
    }

    private func habitRow(_ h: SelfCareHabit) -> some View {
        Button { toggle(h) } label: {
            HStack(spacing: 12) {
                Image(systemName: pending.contains(h.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(pending.contains(h.id) ? Color.appSuccess : Color.appOnSurface.opacity(0.4))
                Image(systemName: h.icon)
                    .frame(width: 22)
                    .foregroundColor(Color.appOnSurface.opacity(0.7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.name)
                        .font(.appBody.weight(.regular))
                        .strikethrough(pending.contains(h.id), color: Color.appOnSurface.opacity(0.4))
                        .foregroundColor(pending.contains(h.id) ? Color.appOnSurface.opacity(0.5) : Color.appOnSurface)
                    Text(h.category.capitalized)
                        .font(.appMicro)
                        .foregroundColor(Color.appOnSurface.opacity(0.4))
                }
                Spacer()
                if isSubmitting {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
            .glassCard()
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    @ViewBuilder
    private var streaksSection: some View {
        if !streaks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CONSISTANCE")
                    .font(.appCaption.weight(.bold))
                    .tracking(2).foregroundColor(.gray)
                    .padding(.horizontal, 16)
                ForEach(streaks.prefix(5)) { s in
                    HStack {
                        Image(systemName: s.habitIcon).frame(width: 22)
                            .foregroundColor(Color.appOnSurface.opacity(0.7))
                        Text(s.habitName).font(.appBody)
                            .foregroundColor(Color.appOnSurface)
                        Spacer()
                        Text("\(s.currentStreak)j")
                            .font(.appBody.weight(.semibold).monospacedDigit())
                            .foregroundColor(s.currentStreak > 0 ? Color.appSuccess : Color.appOnSurface.opacity(0.4))
                        Text("· record \(s.longestStreak)")
                            .font(.appCaption.monospacedDigit())
                            .foregroundColor(Color.appOnSurface.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Actions

    private func toggle(_ habit: SelfCareHabit) {
        let snapshot = pending
        if pending.contains(habit.id) {
            pending.remove(habit.id)
        } else {
            pending.insert(habit.id)
        }
        Task { await submit(rollback: snapshot) }
    }

    private func submit(rollback: Set<String>) async {
        isSubmitting = true
        submitError  = nil
        defer { isSubmitting = false }
        do {
            let result = try await APIService.shared.submitSelfCareLog(
                date: Self.todayMTLString(),
                habitIds: Array(pending)
            )
            todayState.value = result
            pending = Set(result.completed)
            BehaviorTracker.shared.record(.selfCareCheck)
        } catch APIError.queuedOffline {
            // Mutation acceptée hors-ligne : garde l'optimiste, replay FIFO quand reco.
        } catch {
            pending = rollback
            submitError = "Log non enregistré : \(error.localizedDescription)"
        }
    }

    // MARK: Load

    private func loadData() async {
        let api = APIService.shared
        let tSeed = api.cachedSeed(for: APIService.selfCareTodayCacheKey,   as: SelfCareToday.self)
        let sSeed = api.cachedSeed(for: APIService.selfCareStreaksCacheKey, as: [SelfCareStreak].self)

        async let tLoad: Void = todayState.load(seed: tSeed.0, savedAt: tSeed.1) {
            try await api.fetchSelfCareToday(forceRefresh: true)
        }
        async let sLoad: Void = streaksState.load(seed: sSeed.0, savedAt: sSeed.1) {
            try await api.fetchSelfCareStreaks(forceRefresh: true)
        }
        _ = await tLoad
        _ = await sLoad
        pending = Set(todayState.value?.completed ?? [])
    }

    // MARK: Helpers

    private static func todayMTLString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone   = TimeZone(identifier: "America/Montreal") ?? .current
        return f.string(from: Date())
    }
}

// MARK: - Add habit sheet

private struct SelfCareAddHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name:     String = ""
    @State private var icon:     String = "star.fill"
    @State private var category: String = "mental"
    @State private var isSaving  = false
    @State private var saveError: String?

    private let categories = ["physique", "mental", "sommeil", "social"]
    private let icons = ["star.fill", "figure.walk", "drop.fill", "book.fill",
                         "moon.fill", "heart.fill", "fork.knife", "phone.fill",
                         "brain.head.profile", "figure.flexibility", "moon.zzz.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Habitude") {
                    TextField("Ex. Marcher 20 min", text: $name)
                }
                Section("Icône") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(icons, id: \.self) { ic in
                                Button { icon = ic } label: {
                                    Image(systemName: ic)
                                        .font(.title3)
                                        .padding(10)
                                        .background(icon == ic ? Color.forge.opacity(0.25) : Color.clear)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section("Catégorie") {
                    Picker("Catégorie", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                if let err = saveError {
                    Text(err).font(.appCaption).foregroundColor(Color.appDanger)
                }
            }
            .navigationTitle("Nouvelle habitude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            _ = try await APIService.shared.addSelfCareHabit(
                name: name.trimmingCharacters(in: .whitespaces),
                icon: icon,
                category: category
            )
            dismiss()
        } catch APIError.queuedOffline {
            dismiss()  // sera sync au prochain flush
        } catch {
            saveError = "Impossible d'ajouter : \(error.localizedDescription)"
        }
    }
}
