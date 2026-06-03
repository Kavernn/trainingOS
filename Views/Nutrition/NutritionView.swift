import SwiftUI
import Combine

struct NutritionView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = NutritionViewModel()
    @State private var showAdd = false
    @State private var showScan = false
    @State private var editTarget: NutritionEntry? = nil
    @State private var showSettings = false
    @State private var toast: ToastMessage? = nil
    @State private var historyPeriod = 7
    @State private var macroGap: MacroGap? = nil
    // N-D1: banner when settings are missing
    @State private var showSettingsBanner = false
    @State private var pendingDelete: NutritionEntry? = nil
    @State private var pendingDeleteIndex: Int? = nil
    @State private var pendingDeleteTimer: Task<Void, Never>? = nil
    @State private var showUndoBanner = false
    private var effectiveSettings: NutritionSettings? { vm.settings }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)
                // N-B1: AppLoadingView only on first load (entries empty); otherwise show content
                if vm.isLoading && vm.entries.isEmpty {
                    AppLoadingView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            if let err = vm.networkError {
                                ErrorBannerView(error: err,
                                    onRetry: { Task { await vm.loadData() } },
                                    onDismiss: { vm.networkError = nil })
                                    .padding(.horizontal, 16)
                            }


                            // N-D1: banner when nutritional settings are not configured
                            if showSettingsBanner {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                    Text("Cibles nutritionnelles non définies — l'app calcule dans le vide.")
                                        .font(.appLabel)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Button("Définir les cibles") { showSettings = true }
                                        .font(.appLabel).fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.yellow.opacity(0.1))
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1))
                                .padding(.horizontal, 16)
                            }

                            // Message actionnable déficit / surplus
                            NutritionActionMessage(
                                totals: vm.totals,
                                settings: effectiveSettings,
                                hasEntries: !vm.entries.isEmpty,
                                onAddMeal: { showAdd = true }
                            )
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.03)

                            if let score = vm.qualityScore, !vm.qualityIsTooEarly, !vm.qualityNoData {
                                NutritionQualityBadge(score: score)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.04)
                            }

                            // Hero calories + macros
                            MacroSummaryCard(totals: vm.totals, settings: effectiveSettings)
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.05)

                            DailyRemainingCard(totals: vm.totals, settings: effectiveSettings)
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.08)

                            if let dayType = vm.todayType {
                                DayTypeBadge(
                                    type: dayType,
                                    session: vm.todaySession,
                                    effectiveCal: vm.settings?.dayTypeTargets?.target(for: dayType)?.calories,
                                    effectiveGluc: vm.settings?.dayTypeTargets?.target(for: dayType)?.glucides
                                )
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.1)
                            }

                            WorkoutTimingCard(todayType: vm.todayType, totals: vm.totals, settings: effectiveSettings)
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.12)

                            // Entrées du jour groupées
                            GroupedEntryList(
                                entries: vm.entries,
                                onEdit: { editTarget = $0 },
                                onDelete: { entry in
                                    // Confirm any previously pending delete before starting a new one
                                    if let prev = pendingDelete {
                                        pendingDeleteTimer?.cancel()
                                        Task { await vm.deleteEntry(prev) }
                                    }
                                    pendingDeleteTimer?.cancel()
                                    pendingDeleteIndex = vm.entries.firstIndex { $0.entryId == entry.entryId }
                                    pendingDelete = entry
                                    vm.entries.removeAll { $0.entryId == entry.entryId }
                                    withAnimation { showUndoBanner = true }
                                    pendingDeleteTimer = Task {
                                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                                        guard !Task.isCancelled else { return }
                                        await vm.deleteEntry(entry)
                                        pendingDelete = nil
                                        await MainActor.run { withAnimation { showUndoBanner = false } }
                                    }
                                }
                            )
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.15)

                            // Historique + period picker
                            if !vm.history.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach([7, 30, 90], id: \.self) { p in
                                        let sel    = historyPeriod == p
                                        let bg: Color     = sel ? Color.orange.opacity(0.18) : .clear
                                        let fg: Color     = sel ? .orange : .gray
                                        let stroke: Color = sel ? Color.orange.opacity(0.4)  : .clear
                                        Button("\(p)j") {
                                            withAnimation { historyPeriod = p }
                                            Task { await vm.loadData(days: p, silent: true) }
                                        }
                                        .font(.appCaption).fontWeight(.semibold)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(bg)
                                        .foregroundColor(fg)
                                        .cornerRadius(7)
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(stroke, lineWidth: 1))
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.18)

                                WeeklyNutritionChart(
                                    history: vm.history,
                                    protTarget: vm.settings?.proteines ?? 180,
                                    calTarget: vm.settings?.calories
                                )
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.2)
                            }

                            if !vm.history.isEmpty {
                                AdherenceScoreCard(history: vm.history, settings: vm.settings)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.22)
                            }

                            if vm.history.count >= 14 {
                                NutritionPatternsCard(history: vm.history, settings: vm.settings)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.25)
                            }

                            NutritionCorrelationsCard(settings: vm.settings)
                                .padding(.horizontal, 16)
                                .appearAnimation(delay: 0.28)

                            if let gap = macroGap, gap.gaps.protein > 10 || gap.gaps.carbs > 20 {
                                MacroGapCard(gap: gap)
                                    .padding(.horizontal, 16)
                                    .appearAnimation(delay: 0.30)
                            }

                            Spacer(minLength: 80)
                        }
                        .padding(.vertical, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable { await vm.loadData() }
                }
            }
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showScan = true } label: {
                            Image(systemName: "camera.viewfinder").foregroundColor(.orange)
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape").foregroundColor(.orange)
                        }
                        // N-D6: show ProgressView while reloading, button otherwise
                        if vm.isLoading && !vm.entries.isEmpty {
                            ProgressView().tint(.orange)
                        } else {
                            Button(action: { Task { await vm.loadData() } }) {
                                Image(systemName: "arrow.clockwise").foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showScan) {
                ScanLabelSheet {
                    await vm.loadData()
                    await AlertService.shared.fetch()
                }
            }
            .sheet(isPresented: $showAdd) {
                AddNutritionSheet(onSaved: {
                    await vm.loadData()
                    await AlertService.shared.fetch()
                    await showMealFeedback()
                }, onLogged: { templateName in
                    toast = ToastMessage(message: "Repas '\(templateName)' ajouté ✓", style: .success)
                })
            }
            .sheet(item: $editTarget) { entry in
                EditNutritionSheet(entry: entry) { await vm.loadData() }
            }
            .sheet(isPresented: $showSettings) {
                NutritionSettingsSheet(settings: vm.settings) { await vm.loadData(silent: true) }
            }
            .overlay(alignment: .bottomTrailing) {
                FAB(icon: "plus") { showAdd = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, fabBottomPadding)
            }
            // N-D4: undo delete banner
            .overlay(alignment: .bottom) {
                if showUndoBanner {
                    HStack(spacing: 12) {
                        Image(systemName: "trash").foregroundColor(.red)
                        Text("Supprimé.")
                            .font(.appLabel)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Restaurer") {
                            pendingDeleteTimer?.cancel()
                            pendingDeleteTimer = nil
                            if let entry = pendingDelete {
                                let idx = min(pendingDeleteIndex ?? vm.entries.count, vm.entries.count)
                                vm.entries.insert(entry, at: idx)
                            }
                            pendingDelete = nil
                            pendingDeleteIndex = nil
                            withAnimation { showUndoBanner = false }
                        }
                        .font(.appLabel).fontWeight(.semibold)
                        .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.appCard)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, fabBottomPadding + 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task {
            await vm.loadData(days: historyPeriod)
            // N-D1: show banner if settings are nil after load
            showSettingsBanner = vm.settings == nil
            if let url = URL(string: "\(APIService.shared.baseURL)/api/macro_gap"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let gap = try? APIService.decoder.decode(MacroGap.self, from: d) {
                macroGap = gap
            }
        }
        .toast($toast)
    }

    @MainActor
    private func showMealFeedback() async {
        let pTarget = effectiveSettings?.proteines ?? 0
        let consumed = vm.totals?.proteines ?? 0
        if pTarget > 0, consumed >= pTarget * 0.95 {
            let goalFb = ActionFeedback.proteinGoalReached
            if goalFb.shouldShow {
                ActionFeedbackManager.shared.show(goalFb)
                return
            }
        }
        let remaining = pTarget > 0 ? max(0, Int(pTarget - consumed)) : nil
        ActionFeedbackManager.shared.show(.mealLogged(proteinRemaining: remaining))
    }
}

#Preview {
    NutritionView()
        .environmentObject(AppState.shared)
}
