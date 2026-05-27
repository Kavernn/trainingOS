
import SwiftUI
import Charts
import Combine

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = DashboardViewModel()
    @StateObject private var weatherVM = WeatherViewModel()
    @StateObject private var nhlService = NHLService()
    @ObservedObject private var api = APIService.shared
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
    // D-D4: show MorningReveal again without triggering hideForToday
    @State private var showMorningRevealReview = false
    // D-D8: persist deload applied date to suppress re-appearance on refresh
    @AppStorage("deloadAppliedDate") private var deloadAppliedDate = ""
    // D-B3: deload applying state for timeout tracking
    @State private var showDeloadTimeoutAlert = false
    // D-D6: sleep dismiss confirmation
    @State private var showSleepDismissConfirm = false
    @State private var showNutritionAddSheet = false
    @State private var showQuickTrigger = false
    @State private var showQuickBattle = false
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
                if api.isLoading && api.dashboard == nil {
                    VStack(spacing: 0) {
                        DashboardSkeletonView()
                        // D-B2: show retry button alongside slow-load message
                        if api.isSlow {
                            VStack(spacing: 10) {
                                Text("Connexion lente. Attends ou relance.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                                Button {
                                    api.isLoading = false
                                    Task { await vm.loadAll() }
                                } label: {
                                    Text("Relancer")
                                        .font(.system(size: 13, weight: .semibold))
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
                                // D-D1: partial load warning banner
                                if vm.partialLoadWarning {
                                    HStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 13))
                                        Text("Certaines données n'ont pas pu être chargées")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Button {
                                            Task { await vm.loadAll() }
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 13, weight: .semibold))
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

                                if let alert = alertService.visibleAlert {
                                    ProactiveBannerCard(alert: alert) {
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            alertService.dismiss(alert)
                                        }
                                    }
                                    .appearAnimation(delay: 0)
                                }

                                if let phoenix = vm.phoenixScore {
                                    PhoenixCard(score: phoenix, dayDelta: vm.phoenixDayDelta)
                                        .appearAnimationHot(delay: 0)
                                }

                                if let season = vm.activeSeason {
                                    SeasonBannerView(season: season) { showSeasonClose = true }
                                        .appearAnimation(delay: 0.02)
                                }

                                if let season = vm.activeSeason, (44...46).contains(season.dayNumber) {
                                    SeasonMidpointCard(seasonNumber: season.number)
                                        .appearAnimation(delay: 0.03)
                                }

                                GreetingHeaderView(dash: dash, showChecklist: $showChecklist)
                                    .appearAnimation(delay: 0.04)

                                TodayCardView(
                                    dash: dash,
                                    showGreatDayBadge: vm.morningBrief?.recommendation == "go" && (vm.deload?.fatigueLevel ?? 0) == 0 && dash.sessions[todayStr] != nil,
                                    onOpenSession: onOpenSession,
                                    readiness: vm.readinessData
                                )
                                .appearAnimation(delay: 0.05)

                                DailyMetricsRow(
                                    readinessScore: vm.readinessScore,
                                    recovery: vm.todayRecovery,
                                    nutritionTotals: dash.nutritionTotals,
                                    nutritionSettings: dash.nutritionSettings,
                                    moodDue: vm.moodDue,
                                    readinessIsLocal: vm.readinessIsLocal,
                                    onMoodTap: { showMoodSheet = true },
                                    hrvAnalysis: vm.hrvAnalysis
                                )
                                .appearAnimation(delay: 0.10)

                                HRVMorningNudgeView(analysis: vm.hrvAnalysis)
                                    .appearAnimation(delay: 0.11)

                                WeekProgressStripView(dash: dash)
                                    .appearAnimation(delay: 0.15)

                                if let report = vm.deload, report.fatigueLevel == 2 {
                                    DeloadBannerView(report: report) {
                                        await applyDeload(report: report)
                                    }
                                    .appearAnimation(delay: 0.20)
                                } else if let report = vm.deload, report.fatigueLevel == 1 {
                                    // D-D7: fatigue level 1 — lighter chip, not the full red banner
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.yellow)
                                            .font(.system(size: 12))
                                        Text("Fatigue légère. Réduis le volume — ne joue pas avec le feu.")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.85))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(Color.yellow.opacity(0.08))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
                                    .cornerRadius(10)
                                    .appearAnimation(delay: 0.20)
                                }

                                BodyBudgetCard(budget: vm.bodyBudget)
                                    .appearAnimation(delay: 0.25)

                                DailyStreakCard(sessions: dash.sessions)
                                    .appearAnimation(delay: 0.28)

                                if let goal = dash.profile.goal, !goal.isEmpty {
                                    GoalReminderView(goal: goal)
                                        .appearAnimation(delay: 0.30)
                                }

                                if let tip = vm.coachTip {
                                    CoachTipCard(tip: tip)
                                        .appearAnimation(delay: 0.33)
                                }

                                if let pattern = vm.dailyPattern {
                                    PatternDailyChip(pattern: pattern) {
                                        // Navigate to Intelligence tab
                                        NotificationCenter.default.post(name: .navigateToIntelligence, object: nil)
                                    }
                                    .appearAnimation(delay: 0.35)
                                }

                                // Morning ritual entrypoint — visible before 14h when morning not done
                                if let ritual = vm.ritualToday,
                                   !ritual.morningDone,
                                   Calendar.current.component(.hour, from: Date()) < 14 {
                                    MorningRitualEntryCard(ritual: ritual) {
                                        Task { await vm.refreshRitual() }
                                    }
                                    .appearAnimation(delay: 0.37)
                                }

                                // Evening ritual entrypoint — visible after 18h when evening not done
                                if let ritual = vm.ritualToday,
                                   !ritual.eveningDone,
                                   Calendar.current.component(.hour, from: Date()) >= 18 {
                                    EveningRitualEntryCard(ritual: ritual) {
                                        Task { await vm.refreshRitual() }
                                    }
                                    .appearAnimation(delay: 0.38)
                                }

                                // E5: Demon haunting banner — visible when a demon >= 3 days old
                                if let ritual = vm.ritualToday,
                                   let topDemon = ritual.demons.filter({ $0.carryCount >= 3 }).max(by: { $0.carryCount < $1.carryCount }) {
                                    DemonDashboardBanner(demon: topDemon) {
                                        Task { await vm.refreshRitual() }
                                    }
                                    .appearAnimation(delay: 0.39)
                                }

                                // Breathwork nudge — visible when latest LSS score is low (stress high)
                                if let lss = vm.lssTrend.last, lss.score < 50 {
                                    BreathworkNudgeCard()
                                        .appearAnimation(delay: 0.40)
                                }

                                XPChipView(sessions: dash.sessions)
                                    .appearAnimation(delay: 0.36)

                                // D-D4: allow user to re-read morning brief without re-triggering hideForToday
                                if let brief = vm.morningBrief {
                                    Button {
                                        showMorningRevealReview = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "sunrise.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.orange)
                                            Text("Relire le briefing")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.gray)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                    .fullScreenCover(isPresented: $showMorningRevealReview) {
                                        MorningRevealView(morningBrief: brief) {
                                            showMorningRevealReview = false
                                        }
                                    }
                                    .appearAnimation(delay: 0.32)
                                } else if vm.morningBriefFailed {
                                    HStack(spacing: 8) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 11))
                                            .foregroundColor(.gray.opacity(0.45))
                                        Text("Coaching non disponible pour l'instant")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray.opacity(0.55))
                                        Spacer()
                                        Button {
                                            Task { await vm.refreshMorningBrief() }
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 11))
                                                .foregroundColor(.gray.opacity(0.45))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                    .appearAnimation(delay: 0.32)
                                }

                                WeatherChipView(vm: weatherVM)
                                    .appearAnimation(delay: 0.35)

                                // D-C3: hide widget entirely during off-season
                                if !nhlService.isOffSeason {
                                    HabsWidget(service: nhlService)
                                        .appearAnimation(delay: 0.40)
                                }

                                QuoteOfDayView()
                                    .appearAnimation(delay: 0.45)
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
                            weatherVM.requestUpdate()
                            await nhlService.fetch()
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
                } else if let err = api.error {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 48)).foregroundColor(.gray)
                        Text("Connexion impossible").foregroundColor(.white).fontWeight(.semibold)
                        Text(err).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                        Button {
                            Task { await api.fetchDashboard() }
                        } label: {
                            Text("Réessayer")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 28).padding(.vertical, 12)
                                .background(Color.orange).cornerRadius(22)
                        }
                        .buttonStyle(SpringButtonStyle())
                    }
                    .padding()
                }

                // War Room floating pills — visible when War Room is active
                if vm.warRoomEnabled {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Spacer()
                            Button { showQuickBattle = true } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "flag.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Résultat")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule()
                                        .fill(Color(hex: "0a1a0a"))
                                        .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
                                )
                                .shadow(color: Color.green.opacity(0.25), radius: 6, y: 3)
                            }
                            .buttonStyle(.plain)
                            Button { showQuickTrigger = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Tentation")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color(hex: "1a0505"))
                                        .overlay(Capsule().stroke(Color(hex: "C0201A").opacity(0.6), lineWidth: 1))
                                )
                                .shadow(color: Color(hex: "C0201A").opacity(0.3), radius: 8, y: 4)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 20)
                        }
                        .padding(.bottom, fabBottomPadding)
                    }
                    .allowsHitTesting(true)
                }
            }
            .navigationBarHidden(true)
        }
        .task { await vm.loadAll(); await nhlService.fetchIfNeeded(); lastRefresh = Date(); checkAndShowMorningReveal(); weatherVM.requestUpdate() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                BehaviorTracker.shared.record(.appOpen)
                if !api.isLoading, Date().timeIntervalSince(lastRefresh) > 300 {
                    Task { await vm.loadAll(); await nhlService.fetchIfNeeded(); lastRefresh = Date(); checkAndShowMorningReveal() }
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
        .sheet(isPresented: $showQuickTrigger) {
            QuickWarRoomTriggerSheet()
        }
        .sheet(isPresented: $showQuickBattle) {
            QuickBattleSheet()
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
