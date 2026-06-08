
import SwiftUI
import Charts
import Combine

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = DashboardViewModel()
    @ObservedObject private var api = APIService.shared
    @ObservedObject private var loadingState = APILoadingState.shared
    @ObservedObject private var alertService = AlertService.shared
    @State private var showMoodSheet = false
    @State private var showChecklist = false
    @State private var showSleepSheet = false
    @State private var showSeasonClose = false
    @State private var sleepPromptDismissedThisSession = false
    @State private var lastRefresh: Date = .distantPast
    // D-D5: single source of truth — date ISO "2026-05-15" stored in AppStorage
    @AppStorage("sleepPromptDismissedDate") private var sleepPromptDismissedDate = ""
    @State private var actionErrorMessage: String? = nil
    @State private var showMorningReveal = false
    // D-D6: sleep dismiss confirmation
    @State private var showSleepDismissConfirm = false
    @State private var showNutritionAddSheet = false
    @State private var showQuickTrigger = false
    @State private var showQuickBattle = false
    @State private var warRoomToastMessage: String? = nil
    @Environment(\.scenePhase) private var scenePhase
    var onOpenSession: (() -> Void)? = nil

    private var todayStr: String {
        DateFormatter.isoDate.string(from: Date())
    }
    private var shouldShowSleepPrompt: Bool {
        // D-D5: single AppStorage flag — compare stored date to today
        !vm.todaySleepLogged &&
        sleepPromptDismissedDate != todayStr
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: todayAccentColor)
                if loadingState.isLoading && api.dashboard == nil {
                    VStack(spacing: 0) {
                        DashboardSkeletonView()
                        // D-B2: show retry button alongside slow-load message
                        if loadingState.isSlow {
                            VStack(spacing: 10) {
                                Text("Connexion lente. Attends ou relance.")
                                    .font(.appLabel).fontWeight(.regular)
                                    .foregroundColor(.gray)
                                Button {
                                    APILoadingState.shared.isLoading = false
                                    Task { await vm.loadAll() }
                                } label: {
                                    Text("Relancer")
                                        .font(.appLabel).fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20).padding(.vertical, 9)
                                        .background(Color.orange)
                                        .cornerRadius(18)
                                }
                                .buttonStyle(SpringButtonStyle())
                            }
                            .padding(.top, 8)
                        }
                    }
                } else if let dash = api.dashboard {
                    VStack(spacing: 0) {
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                // SYSTÈME — avertissement chargement partiel
                                if vm.partialLoadWarning {
                                    HStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.appLabel)
                                        Text("Certaines données n'ont pas pu être chargées")
                                            .font(.appCaption)
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Button {
                                            Task { await vm.loadAll() }
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.appLabel).fontWeight(.semibold)
                                                .foregroundColor(.orange)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(Color.orange.opacity(0.10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
                                    .cornerRadius(10)
                                    .appearAnimation(delay: 0)
                                }

                                // 1 — Status bar
                                DashboardStatusBar(dash: dash, streakData: vm.streakData, showChecklist: $showChecklist)
                                    .appearAnimation(delay: 0.03)

                                // 1b — Routine de soir (visible dès 20h)
                                if Calendar.current.component(.hour, from: Date()) >= 20,
                                   let ritual = vm.ritualToday {
                                    EveningRoutineCard(ritual: ritual) {
                                        Task { await vm.refreshRitual() }
                                    }
                                    .appearAnimation(delay: 0.035)
                                }

                                // 2 — Alerte critique
                                if let signal = vm.criticalSignal(dash: dash) {
                                    CriticalAlertCard(signal: signal) {
                                        handleAlertAction(signal: signal, dash: dash)
                                    }
                                    .appearAnimation(delay: 0.04)
                                }

                                // 3 — Séance du jour
                                TodayCardView(
                                    dash: dash,
                                    showGreatDayBadge: vm.morningBrief?.recommendation == "go" && (vm.deload?.fatigueLevel ?? 0) == 0 && dash.sessions[todayStr] != nil,
                                    onOpenSession: onOpenSession,
                                    readiness: vm.readinessData
                                )
                                .appearAnimation(delay: 0.05)

                                // 4 — Recovery trio (Readiness + HRV + Sommeil)
                                if vm.morningBrief != nil || vm.todayRecovery != nil {
                                    RecoveryTrioCard(brief: vm.morningBrief, recovery: vm.todayRecovery, hrvAnalysis: vm.hrvAnalysis)
                                        .appearAnimation(delay: 0.06)
                                }

                                // 5 — Coach + alerte proactive (priorité : alerte > coach)
                                if vm.morningBrief != nil || alertService.visibleAlert != nil {
                                    CoachInsightCard(
                                        brief: vm.morningBrief,
                                        sessionCompletedToday: dash.alreadyLoggedToday,
                                        tip: vm.coachTip,
                                        alert: alertService.visibleAlert,
                                        onDismissAlert: {
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                if let a = alertService.visibleAlert { alertService.dismiss(a) }
                                            }
                                        }
                                    )
                                    .appearAnimation(delay: 0.08)
                                } else if vm.morningBriefFailed {
                                    HStack(spacing: 8) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.appCaption)
                                            .foregroundColor(.gray.opacity(0.45))
                                        Text("Coaching non disponible")
                                            .font(.appCaption)
                                            .foregroundColor(.gray.opacity(0.55))
                                        Spacer()
                                        Button {
                                            Task { await vm.refreshMorningBrief() }
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.appCaption)
                                                .foregroundColor(.gray.opacity(0.45))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                    .appearAnimation(delay: 0.08)
                                }

                                // 6 — Métriques du jour
                                DailyMetricsRow(
                                    readinessScore: vm.readinessScore,
                                    recovery: vm.todayRecovery,
                                    nutritionTotals: dash.nutritionTotals,
                                    nutritionSettings: dash.nutritionSettings,
                                    moodDue: vm.moodDue,
                                    readinessIsLocal: vm.readinessIsLocal,
                                    onMoodTap: { showMoodSheet = true }
                                )
                                .appearAnimation(delay: 0.10)

                                // 7 — Momentum strip (semaine + streak)
                                MomentumStripView(dash: dash, streakData: vm.streakData)
                                    .appearAnimation(delay: 0.12)

                                // 8 — Phoenix compact
                                if let phoenix = vm.phoenixScore {
                                    PhoenixCard(score: phoenix, dayDelta: vm.phoenixDayDelta, budget: vm.bodyBudget)
                                        .appearAnimationHot(delay: 0.14)
                                }

                                // 8b — War Room strip
                                if vm.warRoomEnabled {
                                    WarRoomStripView(
                                        hasResult:      vm.warRoomHasResult,
                                        hasTemptation:  vm.warRoomHasTemptation,
                                        onResultTap: {
                                            if vm.warRoomHasResult {
                                                warRoomToastMessage = "Résultat déjà loggué aujourd'hui"
                                            } else {
                                                showQuickBattle = true
                                            }
                                        },
                                        onTemptationTap: {
                                            if vm.warRoomHasTemptation {
                                                warRoomToastMessage = "Tentation déjà loggée aujourd'hui"
                                            } else {
                                                showQuickTrigger = true
                                            }
                                        }
                                    )
                                    .appearAnimation(delay: 0.16)
                                }

                                // ── FOLD NATUREL ──────────────────────────────

                                // 9 — Rituel (demon > soir > matin)
                                if let ritual = vm.ritualToday {
                                    RitualDemonCard(ritual: ritual) {
                                        Task { await vm.refreshRitual() }
                                    }
                                    .appearAnimation(delay: 0.18)
                                }

                                // 10 — Macros (pattern C, actionnable avant séance)
                                if let pattern = vm.dailyPattern,
                                   pattern.family == "C",
                                   pattern.macroThreshold != nil,
                                   !dash.today.lowercased().contains("repos"),
                                   !dash.today.lowercased().contains("rest"),
                                   !dash.today.lowercased().contains("recovery"),
                                   !dash.today.isEmpty,
                                   let yesterday = vm.yesterdayNutrition {
                                    MacroInsightCard(pattern: pattern, yesterday: yesterday) {
                                        NotificationCenter.default.post(name: .navigateToIntelligence, object: nil)
                                    }
                                    .appearAnimation(delay: 0.20)
                                }

                                // 11 — Cardio du jour
                                if let cardio = vm.cardioToday {
                                    DashboardCardioCard(entry: cardio)
                                        .appearAnimation(delay: 0.22)
                                }

                                // 12 — HRV nudge
                                HRVMorningNudgeView(analysis: vm.hrvAnalysis)
                                    .appearAnimation(delay: 0.24)

                                // 13 — Breathwork (stress élevé, groupé avec HRV)
                                if let lss = vm.lssTrend.last, lss.score < 50 {
                                    BreathworkNudgeCard()
                                        .appearAnimation(delay: 0.26)
                                }

                                // 14 — LSS micro-widget
                                LSSMiniCard(trend: vm.lssTrend)
                                    .appearAnimation(delay: 0.28)

                                // ── DISCOVERY ─────────────────────────────────

                                // 15 — Pattern du jour
                                if let pattern = vm.dailyPattern {
                                    PatternDailyChip(pattern: pattern) {
                                        NotificationCenter.default.post(name: .navigateToIntelligence, object: nil)
                                    }
                                    .appearAnimation(delay: 0.30)
                                }

                                // 16 — Saison (strip 28pt, transparent)
                                if let season = vm.activeSeason {
                                    SeasonStripView(season: season) { showSeasonClose = true }
                                        .appearAnimation(delay: 0.32)
                                }

                                // ── SCROLL PROFOND ────────────────────────────

                                // 17 — Citation
                                QuoteOfDayView()
                                    .appearAnimation(delay: 0.34)

                                // 18 — XP
                                XPChipView(sessions: dash.sessions)
                                    .appearAnimation(delay: 0.38)

                                // 19 — Objectif
                                if let goal = dash.profile.goal, !goal.isEmpty {
                                    GoalReminderView(goal: goal)
                                        .appearAnimation(delay: 0.40)
                                }

                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        }
                        .refreshable {
                            await api.fetchDashboard()
                            vm.deload         = try? await APIService.shared.fetchDeloadData()
                            vm.moodDue        = try? await APIService.shared.checkMoodDue()
                            await vm.refreshMorningBrief()
                            vm.eveningSession = try? await APIService.shared.fetchSeanceSoirData()
                            vm.bodyBudget     = try? await APIService.shared.fetchBodyBudget()
                            vm.readinessData  = try? await APIService.shared.fetchReadiness()
                        }

                        QuickLogBar(
                            alreadyLogged:  dash.alreadyLoggedToday,
                            sleepLogged:    vm.todaySleepLogged,
                            moodDone:       vm.moodDue?.isDue == false,
                            onSleepTap:     { showSleepSheet = true },
                            onMoodTap:      { showMoodSheet  = true },
                            onSessionTap:   { onOpenSession?() },
                            onNutritionTap: { showNutritionAddSheet = true }
                        )
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
                        }
                        .background(Color.appBg.opacity(0.96).ignoresSafeArea(edges: .bottom))
                    }
                } else if let err = loadingState.error {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 48)).foregroundColor(.gray)
                        Text("Connexion impossible").foregroundColor(.white).fontWeight(.semibold)
                        Text(err).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                        Button {
                            Task { await api.fetchDashboard() }
                        } label: {
                            Text("Réessayer")
                                .font(.appBody).fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 28).padding(.vertical, 12)
                                .background(Color.orange).cornerRadius(22)
                        }
                        .buttonStyle(SpringButtonStyle())
                    }
                    .padding()
                }

            }
            .navigationBarHidden(true)
        }
        .task { await vm.loadAll(); lastRefresh = Date(); checkAndShowMorningReveal() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                BehaviorTracker.shared.record(.appOpen)
                if !loadingState.isLoading, Date().timeIntervalSince(lastRefresh) > 300 {
                    Task { await vm.loadAll(); lastRefresh = Date(); checkAndShowMorningReveal() }
                }
            }
        }
        .fullScreenCover(isPresented: $showSeasonClose, onDismiss: {
            Task { await vm.loadAll() }
        }) {
            if let season = vm.activeSeason {
                SeasonCloseView(season: season) {
                    showSeasonClose = false
                    Task { await vm.loadAll() }
                }
            }
        }
        .sheet(isPresented: $showMoodSheet, onDismiss: {
            Task { await vm.refreshMoodDue() }
        }) {
            MoodLogSheet()
        }
        .sheet(isPresented: $showQuickTrigger, onDismiss: {
            Task { await vm.refreshWarRoomTodayStatus() }
        }) {
            QuickWarRoomTriggerSheet()
        }
        .sheet(isPresented: $showQuickBattle, onDismiss: {
            Task { await vm.refreshWarRoomTodayStatus() }
        }) {
            QuickBattleSheet()
        }
        .overlay(alignment: .top) {
            if let msg = warRoomToastMessage {
                Text(msg)
                    .font(.appCaption).fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color.appCard.opacity(0.96))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation(.easeOut(duration: 0.3)) { warRoomToastMessage = nil }
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: warRoomToastMessage)
            }
        }
        .sheet(isPresented: $showSleepSheet) {
            NavigationStack {
                VStack(spacing: 0) {
                    SleepPromptCard(
                        onDone: {
                            UserDefaults.standard.set(todayStr, forKey: "sleepPromptDate")
                            withAnimation(.easeOut(duration: 0.25)) { sleepPromptDismissedThisSession = true }
                            showSleepSheet = false
                        },
                        onError: { msg in actionErrorMessage = msg }
                    )
                    .padding(16)
                    Spacer()
                }
                .background(Color.appBg.ignoresSafeArea())
                .navigationTitle("Sommeil")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { showSleepSheet = false }
                            .foregroundColor(.white)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showChecklist) {
            NavigationStack {
                ScrollView {
                    ChecklistCardView()
                        .padding(16)
                }
                .navigationTitle("Avant de partir")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { showChecklist = false }
                    }
                }
                .background(Color.appBg.ignoresSafeArea())
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Erreur", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { actionErrorMessage = nil }
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .fullScreenCover(isPresented: $showMorningReveal) {
            if let brief = vm.morningBrief {
                MorningRevealView(morningBrief: brief) {
                    UserDefaults.standard.set(todayStr, forKey: "morningRevealDate")
                    showMorningReveal = false
                }
            }
        }
        .sheet(isPresented: $showNutritionAddSheet) {
            AddNutritionSheet {
                Task { await vm.loadAll() }
            }
        }
    }

    private func checkAndShowMorningReveal() {
        let hour = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
        guard hour < 14,
              UserDefaults.standard.string(forKey: "morningRevealDate") != todayStr,
              vm.morningBrief != nil else { return }
        showMorningReveal = true
    }

    var todayAccentColor: Color {
        let low = (api.dashboard?.today ?? "").lowercased()
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") { return .green }
        if low.contains("pull")  { return .cyan }
        if low.contains("push") || low.contains("upper") { return .orange }
        if low.contains("legs") || low.contains("lower") { return .yellow }
        if low.contains("yoga")  { return .purple }
        return .blue
    }

    private func handleAlertAction(signal: CriticalSignal, dash: DashboardData) {
        switch signal.destination {
        case .recovery, .hrv:
            NotificationCenter.default.post(name: .navigateToRecovery, object: nil)
        case .workout:
            onOpenSession?()
        case .deload:
            guard let report = vm.deload else { return }
            Task { await applyDeload(report: report) }
        }
    }

    private func applyDeload(report: DeloadReport) async -> Bool {
        do {
            try await api.applyDeload(poidsDeload: report.poidsDeload)
        } catch {
            actionErrorMessage = "Erreur lors du déload — réessaie."
            return false
        }
        await api.fetchDashboard()
        vm.deload = nil
        return true
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
}
