
import SwiftUI

// Accent du jour (Color.sessionTypeColor) — intensités de rayonnement sur le chrome.
// Réversibles : réduire d'un cran si trop présent sur device.
enum DashboardAccentRadiance {
    // Point 1 — Bande/halo en haut, sous la StatusBar iOS
    static let topBandPeak:   Double  = 0.22
    static let topBandHeight: CGFloat = 120

    // Point 2 — Wash StatusBar + liseré bas
    static let statusBarFill: Double = 0.06
    static let statusBarRule: Double = 0.20
}

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @ObservedObject private var appTheme = AppTheme.shared
    @ObservedObject var api = APIService.shared
    @ObservedObject private var loadingState = APILoadingState.shared
    @ObservedObject private var alertService = AlertService.shared
    @State private var showMoodSheet = false
    @State private var lastRefresh: Date = .distantPast
    @State private var actionErrorMessage: String? = nil
    @State private var showNutritionAddSheet = false
    @State private var showQuickTrigger = false
    @State private var showQuickBattle = false
    @Environment(\.accessibilityReduceMotion) private var reduceWarRoomMotion
    @State private var warRoomToastMessage: String? = nil
    @State private var educationalCapsules: [EducationalCapsule] = []
    @State private var educationalLoadedDate: String? = nil
    @State private var lessonOfDay: EducationalCapsule? = nil
    @State private var lessonSheetCapsule: EducationalCapsule? = nil
    @State private var lessonBypassAttemptedDate: String? = nil
    @State private var lessonRefreshFailed: Bool = false
    // Mode Jour de Paie — sheet pré-remplie + célébration après log.
    @State private var budgetPrefill: PlannedTransfer? = nil
    @State private var pendingBudgetCelebration: BudgetCelebrationData? = nil
    @State private var budgetCelebrationData: BudgetCelebrationData? = nil
    @Environment(\.scenePhase) private var scenePhase
    var onOpenSession: (() -> Void)? = nil
    var onOpenHealth: (() -> Void)? = nil

    private var todayStr: String {
        DateFormatter.isoDate.string(from: Date())
    }
    private func dashboardHeading(_ title: String) -> some View {
        Text(title)
            .font(.appCaption.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(Color.appTextSecondary)
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)
    }

    func dashboardContent(_ dash: DashboardData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            dashboardHeading("MAINTENANT")

            // 4 — Séance du jour
            if let plan = api.dashboardPlan {
                TodayCardView(
                    dash: dash,
                    plan: plan,
                    plannedDate: DateFormatter.isoDate.date(from: dash.todayDate) ?? Date(),
                    showGreatDayBadge: vm.morningBrief?.recommendation == "go" && (vm.deload?.fatigueLevel ?? 0) == 0 && dash.sessions[todayStr] != nil,
                    onOpenSession: onOpenSession,
                    readiness: vm.readinessData,
                    effortCap: DashboardVerdictArbiter.cap(signal: vm.criticalSignal(dash: dash))
                )

                .padding(.vertical, 8)
            }

            dashboardHeading("MA JOURNÉE")
            let hour = Calendar.current.component(.hour, from: Date())
            let isMorningMoodPrompt = hour >= 6 && hour < 14 && vm.moodDue?.isDue == true

            // 2 — Grille domaines (Entraînement · Nutrition · Récupération · Finances)
            DashboardDomainGrid(
                dash: dash,
                hrvAnalysis: vm.hasCurrentDayContext ? vm.hrvAnalysis : nil,
                budgetStatus: vm.budgetStatus,
                onOpenSession: onOpenSession,
                onOpenHealth:  onOpenHealth,
                onOpenNutrition: { showNutritionAddSheet = true }
            )

            NavigationLink { ProgrammeView() } label: {
                Label("Programme · Réorganiser ma journée", systemImage: "calendar")
                    .font(.appLabel)
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)

            // 10 — Actions du jour
            DayActionsRow(
                sessionLogged: dash.alreadyLoggedToday,
                moodDone: vm.moodDue?.isDue == false,
                nutritionLogged: (dash.nutritionTotals.calories ?? 0) >= 1,
                hideMoodChip: false,
                onSessionTap: { onOpenSession?() },
                onMoodTap: { showMoodSheet = true },
                onNutritionTap: { showNutritionAddSheet = true }
            )
            .padding(.top, 14)

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    // 11 — War Room strip
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
                        .frame(maxWidth: .infinity)

                    }

                    // 9 — Leçon du jour (registre calme)
                    if let lesson = lessonOfDay {
                        LessonOfDayCard(
                            capsule: lesson,
                            exhausted: false,
                            refreshFailed: false,
                            onTap: { lessonSheetCapsule = lesson },
                            onRetry: { }
                        )
                        .frame(maxWidth: .infinity)

                    } else if lessonRefreshFailedToday {
                        LessonOfDayCard(
                            capsule: nil,
                            exhausted: false,
                            refreshFailed: true,
                            onTap: { },
                            onRetry: {
                                lessonBypassAttemptedDate = nil
                                lessonRefreshFailed = false
                                Task { await refreshEducationalLive() }
                            }
                        )
                        .frame(maxWidth: .infinity)

                    } else if lessonExhausted {
                        LessonOfDayCard(
                            capsule: nil,
                            exhausted: true,
                            refreshFailed: false,
                            onTap: { },
                            onRetry: { }
                        )
                        .frame(maxWidth: .infinity)

                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    // 11 — Cardio du jour
                    if let cardio = vm.cardioToday {
                        DashboardCardioCard(entry: cardio)
                            .frame(maxWidth: .infinity)

                    }

                    // 13 — Pensée du jour (fermeture calme du scroll)
                    QuoteCard()
                        .frame(maxWidth: .infinity)

                }
            }
            .padding(.top, 8)

            dashboardHeading("MES TENDANCES")
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

            }

            // 3 — Alerte critique
            if let signal = vm.criticalSignal(dash: dash) {
                CriticalAlertCard(signal: signal) {
                    handleAlertAction(signal: signal, dash: dash)
                }

            }

            // 7 — Coach + alerte proactive (priorité : alerte > coach)
            if vm.morningBrief != nil || alertService.visibleAlert != nil {
                CoachInsightCard(
                    brief: vm.morningBrief,
                    sessionCompletedToday: dash.alreadyLoggedToday,
                    alert: alertService.visibleAlert,
                    onDismissAlert: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            if let a = alertService.visibleAlert { alertService.dismiss(a) }
                        }
                    }
                )

            } else if vm.morningBriefFailed {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.appCaption)
                        .foregroundColor(Color.appTextMuted.opacity(0.45))
                    Text("Coaching non disponible")
                        .font(.appCaption)
                        .foregroundColor(Color.appTextMuted.opacity(0.55))
                    Spacer()
                    Button {
                        Task { await vm.refreshMorningBrief() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.appCaption)
                            .foregroundColor(Color.appTextMuted.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)

            }

            if isMorningMoodPrompt {
                MorningMoodPromptCard(action: { showMoodSheet = true })

            }
            if hour >= 20 || hour < 3 {
                EveningSleepCard()

            }

            // ── FOLD NATUREL ──────────────────────────────

            // 12 — Budget & finances
            if let bs = vm.budgetStatus {
                if bs.isPaydayToday == true {
                    VStack(alignment: .leading, spacing: 6) {
                        BudgetCard(status: bs, onTransferTap: { pt in
                            budgetPrefill = pt
                        })
                        NavigationLink { BudgetView() } label: {
                            HStack {
                                Spacer()
                                Text("Voir tout →")
                                    .font(.appCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                }
            }

        }
        .id(appTheme.selectedTheme)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    var appearanceBanner: some View {
            // 6 — Hero State (salutation, ring readiness, HRV, sommeil, streak, synthèse) — tap → onglet Santé
            Button { onOpenHealth?() } label: {
                DashboardHeroState(
                    readiness:   vm.hasCurrentDayContext ? vm.readinessData : nil,
                    hrvAnalysis: vm.hasCurrentDayContext ? vm.hrvAnalysis : nil,
                    recovery:    vm.hasCurrentDayContext ? vm.todayRecovery : nil,
                    streak:      vm.hasCurrentDayContext ? (vm.streakData?.currentStreak ?? 0) : 0,
                    userName:    api.dashboard?.profile.name
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

    }

    var pageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                DashboardBrandingBar(profile: api.dashboard?.profile)
                DashboardStatusBar(
                    dash: api.dashboard,
                    plannedSession: api.dashboardPlan?.morning(on: Date()) ?? "Planning indisponible"
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            appearanceBanner
            .padding(.horizontal, 16)
            if loadingState.isLoading && api.dashboard == nil && api.dashboardPlan == nil {
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
            } else if let dash = api.dashboard, dash.todayDate == todayStr {
                dashboardContent(dash)
            } else if let plan = api.dashboardPlan {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MAINTENANT").font(.appHeadline)
                    Text(plan.morning(on: Date())).font(.appTitle)
                    if let evening = plan.evening(on: Date()) {
                        Text("Soir · \(evening)").font(.appBody)
                    }
                    Text(api.dashboardPlanIsCurrent(on: Date())
                    ? (loadingState.isLoading || loadingState.isRefreshing ? "Planning vérifié. Chargement du suivi…" : "Planning vérifié. Suivi indisponible.")
                    : "Planning enregistré · vérification nécessaire")
                    .font(.appCaption).foregroundColor(.appTextSecondary)
                    if plan.morning(on: Date()) != "Repos" {
                        if let onOpenSession {
                            Button("Ouvrir ma séance", action: onOpenSession)
                            .buttonStyle(.borderedProminent).tint(.forge).frame(minHeight: 44)
                            .disabled(!api.dashboardPlanIsCurrent(on: Date()))
                        } else {
                            NavigationLink("Ouvrir ma séance") { SeanceView() }
                            .frame(minHeight: 44)
                            .disabled(!api.dashboardPlanIsCurrent(on: Date()))
                        }
                    }
                    Button("Réessayer") { Task { await vm.loadAll() } }
                    .frame(minHeight: 44)
                }
                .foregroundColor(.appTextPrimary).padding()
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
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: dailyAccent)
                    .id(appTheme.selectedTheme)

                // Point 1 — Bande/halo accent en haut, ancre le type de jour dès l'ouverture.
                // Réversible via DashboardAccentRadiance.topBandPeak.
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [dailyAccent.opacity(DashboardAccentRadiance.topBandPeak), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: DashboardAccentRadiance.topBandHeight)
                    .ignoresSafeArea(edges: .top)
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    pageContent
                }
                .refreshable {
                    await vm.loadAll(mode: .refresh)
                    guard !Task.isCancelled else { return }
                    await loadEducationalIfNeeded()
                    lastRefresh = Date()
                    checkAndShowMorningReveal()
                }

            }
            .navigationBarHidden(true)
        }
        .task {
            await vm.loadIfNeeded()
            await loadEducationalIfNeeded()
            lastRefresh = Date()
            checkAndShowMorningReveal()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                BehaviorTracker.shared.record(.appOpen)
                if !loadingState.isLoading, api.dashboard?.todayDate != todayStr || Date().timeIntervalSince(lastRefresh) > 300 {
                    Task { await vm.loadAll(); lastRefresh = Date(); checkAndShowMorningReveal() }
                }
            }
        }
        .onChange(of: api.dashboardPlan?.programme.active_program_id) { old, new in
            if old != nil, new == nil {
                Task { await vm.loadAll() }
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
            QuickBattleSheet { feedback in
                if let feedback { warRoomToastMessage = feedback }
            }
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
                    .transition(reduceWarRoomMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation(reduceWarRoomMotion ? nil : .easeOut(duration: 0.3)) { warRoomToastMessage = nil }
                        }
                    }
                    .animation(reduceWarRoomMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: warRoomToastMessage)
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
        .sheet(isPresented: $showNutritionAddSheet) {
            AddNutritionSheet {
                Task { await vm.reloadAfterMutation() }
            }
        }
        .sheet(item: $lessonSheetCapsule) { capsule in
            EducationalCapsuleDetailSheet(capsule: capsule) {
                lessonSheetCapsule = nil
            }
        }
        // Mode Jour de Paie : tap sur un transfert planifié → sheet pré-remplie
        // → sur log, calcul du delta et présentation de la célébration en fullScreenCover
        // (différé 0.3s pour éviter le conflit sheet→cover — même piège qu'en 3B).
        .sheet(item: $budgetPrefill, onDismiss: {
            if let data = pendingBudgetCelebration {
                pendingBudgetCelebration = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    budgetCelebrationData = data
                }
            }
        }) { pt in
            if let bs = vm.budgetStatus {
                BudgetLogSheet(
                    envelopes:  bs.envelopes,
                    debts:      bs.debts,
                    activeDebt: bs.activeDebt,
                    prefill:    pt,
                    onSaved:    { entry, total in
                        let old = vm.budgetStatus
                        do {
                            vm.budgetStatus = try await APIService.shared.fetchBudgetStatus()
                        } catch {
                            // logBudget a réussi côté serveur ; le refetch a échoué.
                            // L'user doit savoir que l'écran affiche du stale, pas
                            // croire que son log n'a rien fait (chip "à faire" trompeur).
                            actionErrorMessage = "Log enregistré, actualisation du budget impossible — tire pour rafraîchir."
                        }
                        if let data = BudgetCelebrationData.build(
                            entry: entry, old: old, new: vm.budgetStatus, totalCents: total
                        ) {
                            pendingBudgetCelebration = data
                        }
                    }
                )
            }
        }
        .fullScreenCover(item: $budgetCelebrationData) { data in
            BudgetCelebrationView(data: data) { budgetCelebrationData = nil }
        }
    }

    private func checkAndShowMorningReveal() {
        let hour = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 3600 % 24
        guard hour < 14,
              UserDefaults.standard.string(forKey: "morningRevealDate") != todayStr,
              let brief = vm.morningBrief else { return }
        AppState.shared.enqueueLaunchPrompt(.morningReveal(brief))
    }

    private var dailyAccent: Color {
        Color.sessionTypeColor(api.dashboardPlan?.morning(on: Date()) ?? "")
    }

    private func handleAlertAction(signal: CriticalSignal, dash: DashboardData) {
        switch signal.destination {
        case .recovery, .hrv:
            AppState.shared.pendingDeepLink = "recovery"
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

    private func loadEducationalIfNeeded() async {
        if educationalLoadedDate != todayStr {
            do {
                educationalCapsules = try await api.fetchEducationalContent()
                educationalLoadedDate = todayStr
            } catch {
                return  // carte absente si fetch initial KO (registre non-critique)
            }
        }
        resolveLessonOfDay()
        // Épuisement présumé : le pool est celui du cache 24h. Avant d'afficher
        // "tu as tout parcouru", on force un aller-retour réseau pour vérifier
        // qu'aucune capsule neuve n'a été ajoutée côté DB.
        if !educationalCapsules.isEmpty
            && lessonOfDay == nil
            && lessonBypassAttemptedDate != todayStr {
            await refreshEducationalLive()
        }
    }

    /// Bypass cache pour vérifier le pool live avant de conclure "épuisé".
    /// Garde : un seul appel par jour astro. `lessonBypassAttemptedDate` est
    /// marqué AVANT l'await pour verrouiller toute réentrance depuis un
    /// re-render pendant que le fetch est en vol.
    /// Erreur : pas de fallback silencieux — `lessonRefreshFailed = true`
    /// bascule l'UI sur l'état "vérification impossible", jamais sur "épuisé".
    private func refreshEducationalLive() async {
        lessonBypassAttemptedDate = todayStr
        do {
            let live = try await api.fetchEducationalContent(bypassCache: true)
            LessonOfDayStore.reconcileSeen(against: Set(live.map(\.id)))
            educationalCapsules = live
            lessonRefreshFailed = false
            resolveLessonOfDay()
        } catch {
            lessonRefreshFailed = true
        }
    }

    private func resolveLessonOfDay() {
        lessonOfDay = LessonOfDayStore.todayLesson(from: educationalCapsules, todayStr: todayStr)
    }

    private var lessonExhausted: Bool {
        !educationalCapsules.isEmpty
            && lessonOfDay == nil
            && lessonBypassAttemptedDate == todayStr
            && !lessonRefreshFailed
    }

    private var lessonRefreshFailedToday: Bool {
        lessonRefreshFailed && lessonBypassAttemptedDate == todayStr
    }
}

#Preview {
    DashboardView()
}
