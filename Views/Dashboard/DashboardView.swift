
import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @ObservedObject private var api = APIService.shared
    @ObservedObject private var loadingState = APILoadingState.shared
    @ObservedObject private var alertService = AlertService.shared
    @State private var showMoodSheet = false
    @State private var lastRefresh: Date = .distantPast
    @State private var actionErrorMessage: String? = nil
    @State private var showMorningReveal = false
    @State private var showNutritionAddSheet = false
    @State private var showQuickTrigger = false
    @State private var showQuickBattle = false
    @State private var warRoomToastMessage: String? = nil
    @Environment(\.scenePhase) private var scenePhase
    var onOpenSession: (() -> Void)? = nil

    private var todayStr: String {
        DateFormatter.isoDate.string(from: Date())
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
                                        .foregroundColor(Color.onAccent)
                                        .padding(.horizontal, 20).padding(.vertical, 9)
                                        .background(Color.forge)
                                        .cornerRadius(18)
                                }
                                .buttonStyle(SpringButtonStyle())
                            }
                            .padding(.top, 8)
                        }
                    }
                } else if let dash = api.dashboard {
                    ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                // SYSTÈME — avertissement chargement partiel
                                if vm.partialLoadWarning {
                                    HStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(Color.forge)
                                            .font(.appLabel)
                                        Text("Certaines données n'ont pas pu être chargées")
                                            .font(.appCaption)
                                            .foregroundColor(Color.appOnBackground.opacity(0.8))
                                        Spacer()
                                        Button {
                                            Task { await vm.loadAll() }
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.appLabel).fontWeight(.semibold)
                                                .foregroundColor(Color.forge)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(Color.forge.opacity(0.10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.forge.opacity(0.25), lineWidth: 1))
                                    .cornerRadius(10)
                                    .appearAnimation(delay: 0)
                                }

                                // 1 — Status bar
                                DashboardStatusBar(dash: dash, streakData: vm.streakData)
                                    .appearAnimation(delay: 0.03)

                                // 1b — Routine de soir (visible dès 20h, et jusqu'à 3h pour couchers tardifs)
                                let eveningHour = Calendar.current.component(.hour, from: Date())
                                if (eveningHour >= 20 || eveningHour < 3),
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

                                // 6 — Actions du jour
                                DayActionsRow(
                                    sessionLogged: dash.alreadyLoggedToday,
                                    moodDone: vm.moodDue?.isDue == false,
                                    nutritionLogged: (dash.nutritionTotals.calories ?? 0) >= 1,
                                    onSessionTap: { onOpenSession?() },
                                    onMoodTap: { showMoodSheet = true },
                                    onNutritionTap: { showNutritionAddSheet = true }
                                )
                                .appearAnimation(delay: 0.10)

                                // 7 — Momentum strip (semaine + streak)
                                MomentumStripView(dash: dash, streakData: vm.streakData, weeklyTonnage: vm.weeklyTonnage)
                                    .appearAnimation(delay: 0.12)


                                // 8e — War Room strip
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



                                // 11 — Cardio du jour
                                if let cardio = vm.cardioToday {
                                    DashboardCardioCard(entry: cardio)
                                        .appearAnimation(delay: 0.22)
                                }













                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        }
                        .refreshable {
                            await vm.loadAll()
                            lastRefresh = Date()
                            checkAndShowMorningReveal()
                        }
                } else if let err = loadingState.error {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 48)).foregroundColor(.gray)
                        Text("Connexion impossible").foregroundColor(.appOnBackground).fontWeight(.semibold)
                        Text(err).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                        Button {
                            Task { await api.fetchDashboard() }
                        } label: {
                            Text("Réessayer")
                                .font(.appBody).fontWeight(.semibold)
                                .foregroundColor(Color.onAccent)
                                .padding(.horizontal, 28).padding(.vertical, 12)
                                .background(Color.forge).cornerRadius(22)
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
                    .foregroundColor(.appOnSurface)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color.appCard.opacity(0.96))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appSeparator, lineWidth: 0.5))
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
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") { return .statusGreen  }
        if low.contains("pull")  { return .statusCyan   }
        if low.contains("push") || low.contains("upper") { return .statusOrange }
        if low.contains("legs") || low.contains("lower") { return .statusYellow }
        if low.contains("yoga")  { return .statusPurple }
        return .statusBlue
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
}
