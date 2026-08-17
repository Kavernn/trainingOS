import SwiftUI

// MARK: - Today Card
struct TodayCardView: View {
    let dash: DashboardData
    var showGreatDayBadge: Bool = false
    var onOpenSession: (() -> Void)? = nil
    var readiness: ReadinessResponse? = nil
    var effortCap: EffortCap = .none
    @State private var showReadinessSheet = false
    // Volet G : SeanceSoirView en .sheet obligatoirement (voir commentaire au head
    // de SeanceSoirView.swift). NavigationLink push cassait les .alert internes.
    @State private var showSeance2Sheet = false
    // Ancré ici (parent stable) et pas dans Seance3BonusStrip : le body du strip
    // bascule sur EmptyView quand bonusCompleted flippe post-log → démonterait le
    // sheet host avant le récap. Même chaîne que le bug soir (fix b9ae7c0).
    @State private var showBonusSheet = false
    @ObservedObject private var api = APIService.shared

    /// Source de vérité : flag serveur OU session dans le dict OU flag optimiste local.
    private var isLoggedToday: Bool {
        dash.alreadyLoggedToday || dash.sessions[dash.todayDate] != nil || api.sessionLoggedToday
    }

    private var todaySession: SessionEntry? {
        dash.sessions[dash.todayDate]
    }

    private var hasPartialLogs: Bool {
        dash.hasPartialLogs || SessionDraftStore.hasAnyDraft(date: dash.todayDate)
    }

    var todayColor: Color { Color.sessionTypeColor(dash.today) }

    /// Étape 3b — source unique backend (dash.pushedToEvening dérivée du payload).
    /// Remplace SeanceSplitStore.load(date:) — même sémantique, même type.
    private var hasLocalPushedExercises: Bool {
        !dash.pushedToEvening.isEmpty
    }
    private var pushedCount: Int {
        dash.pushedToEvening.count
    }
    private var seance2Label: String {
        if let name = dash.eveningSessionName { return "Commencer la séance 2 · \(name)" }
        if pushedCount > 0 { return "Commencer la séance 2 · \(pushedCount) exo\(pushedCount > 1 ? "s" : "")" }
        return "Commencer la séance 2"
    }

    var todayIcon: String {
        let low = dash.today.lowercased()
        if low.contains("yoga")  { return "figure.mind.and.body" }
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") { return "moon.fill" }
        if low.contains("upper") || low.contains("lower") ||
           low.contains("push") || low.contains("pull") ||
           low.contains("legs") || low.contains("full body") { return "dumbbell.fill" }
        return "dumbbell.fill"
    }

    var exercises: [(String, String)] {
        guard let program = dash.fullProgram[dash.today] else { return [] }
        // On convertit la valeur en String ici pour respecter la promesse [(String, String)]
        return program.map { ($0.key, $0.value.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(todayColor.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: isLoggedToday ? "checkmark" : todayIcon)
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(isLoggedToday ? Color.statusGreen : todayColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(dash.today.isEmpty ? "Repos" : dash.today)
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(isLoggedToday ? Color.statusGreen : todayColor)
                        .lineLimit(1)
                }
                Spacer()
                if isLoggedToday {
                    HStack(spacing: 5) {
                        if showGreatDayBadge {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.appMicro)
                                    .foregroundColor(Color.forge)
                                Text("Parfait")
                                    .font(.appCaption.weight(.bold))
                                    .foregroundColor(Color.forge)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.forge.opacity(0.12))
                            .clipShape(Capsule())
                        } else {
                            PulsingDot(color: Color.statusGreen)
                            Text("Complété")
                                .font(.appCaption.weight(.semibold)).foregroundColor(Color.statusGreen)
                        }
                    }
                } else if !exercises.isEmpty {
                    Text("\(exercises.count) exos")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.appSurfaceInset)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.appSeparator).padding(.horizontal, 16)

            if isLoggedToday {
                // ── Récap séance loggée ───────────────────────────────────
                // isLoggedToday peut être vrai via alreadyLoggedToday même sans session dans le dict
                if let session = todaySession {
                    TodaySessionRecap(session: session, color: todayColor, totalWorkoutMin: dash.totalWorkoutMinToday)
                }
                // Séance 2 non complétée ET (planifiée backend OU exos poussés localement)
                // → CTA vers SeanceSoirView (flow evening, is_second=true).
                if (dash.hasEveningSession || hasLocalPushedExercises) && !dash.secondSessionCompleted {
                    // Sheet obligatoire (Volet G) — voir SeanceSoirView.swift head.
                    Button { showSeance2Sheet = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text(seance2Label)
                                .font(.appBody.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [todayColor, todayColor.opacity(0.75)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: todayColor.opacity(0.4), radius: 10, y: 4)
                    }
                    .buttonStyle(SpringButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                // Loggé sans séance 2 planifiée → Seance3BonusStrip (fin de VStack) fournit l'accès bonus.
            } else {
                // ── Programme prévu (pas encore loggé) ───────────────────
                if !exercises.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(exercises.prefix(5).enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 10) {
                                Text("\(idx + 1)")
                                    .font(.appCaption.weight(.black))
                                    .foregroundColor(todayColor.opacity(0.5))
                                    .frame(width: 16)
                                Text(item.0)
                                    .font(.appLabel).foregroundColor(.appTextPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.1)
                                    .font(.appCaption).foregroundColor(.gray)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            if idx < exercises.prefix(5).count - 1 {
                                Divider()
                                    .background(Color.appSurfaceInset)
                                    .padding(.horizontal, 16)
                            }
                        }
                        if exercises.count > 5 {
                            Text("+ \(exercises.count - 5) exercices")
                                .font(.appCaption).foregroundColor(.gray)
                                .padding(.horizontal, 16).padding(.bottom, 8)
                        }
                    }
                }

                // ── Readiness badge ──────────────────────────────────
                if readiness != nil {
                    ReadinessBadge(readiness: readiness, cap: effortCap)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                // Jour de repos → pas de CTA principal ici, Seance3BonusStrip (fin VStack) suffit.
                if dash.today != "Repos" {
                    Group {
                        if let onOpenSession {
                            Button(action: {
                                if readiness != nil { showReadinessSheet = true }
                                else { onOpenSession() }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text(hasPartialLogs ? "Continuer la séance" : "Commencer la séance")
                                        .font(.appBody.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [todayColor, todayColor.opacity(0.75)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: todayColor.opacity(0.4), radius: 10, y: 4)
                            }
                        } else {
                            NavigationLink(destination: SeanceView()) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text(hasPartialLogs ? "Continuer la séance" : "Commencer la séance")
                                        .font(.appBody.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [todayColor, todayColor.opacity(0.75)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: todayColor.opacity(0.4), radius: 10, y: 4)
                            }
                        }
                    }
                    .buttonStyle(SpringButtonStyle())
                    .padding([.horizontal, .bottom], 16)
                    .padding(.top, 12)
                }
            }
            // Point d'accès unique bonus — 3 états gérés dans le composant.
            Seance3BonusStrip(
                hasBonus: dash.hasBonusSession,
                bonusCompleted: dash.bonusSessionCompleted,
                pushedCount: dash.pushedToBonus.count,
                showSheet: $showBonusSheet
            )

            TomorrowPreviewStrip(dash: dash)
        }
        // Fond neutre : brutalist (cardAccentFillOpacity 1.0) + electric (0.80)
        // rendaient la carte hero illisible (fond plein saturé sur textes .gray).
        // L'accent reste porté par l'icône, le titre, les numéros et le CTA gradient.
        .glassCard()
        .sheet(isPresented: $showReadinessSheet) {
            if let r = readiness {
                ReadinessSheet(readiness: r) { onOpenSession?() }
            }
        }
        // Ancre stable (hors du if secondSessionCompleted L119) : sinon fetchDashboard
        // post-log soir démonte le sheet host avant que le récap ne se présente.
        .sheet(isPresented: $showSeance2Sheet) { SeanceSoirView() }
        // Ancre stable symétrique au soir : Seance3BonusStrip.body prend EmptyView
        // quand bonusCompleted flippe post-log → démonterait le sheet + son @State
        // s'ils vivaient dans le strip. Le showBonusSheet est ici, passé en binding.
        .sheet(isPresented: $showBonusSheet) { BonusSeanceView() }
    }
}

// MARK: - Today Session Recap
struct TodaySessionRecap: View {
    let session: SessionEntry
    let color: Color
    var totalWorkoutMin: Double? = nil
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Métriques clés
            HStack(spacing: 0) {
                // Multi-slot (AM + PM + bonus) : une pill RPE par slot, remplace le scalaire.
                // Source de vérité : session.slots (backend). Mono-slot ou payload legacy
                // sans `slots` → fallback pill RPE unique (session.rpe scalaire).
                if let slots = session.slots, slots.count > 1 {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                        RecapMetric(
                            value: slot.rpe.map { String(format: "%.1f", $0) } ?? "—",
                            label: slot.label,
                            color: slot.rpe.map(rpeColor) ?? Color.gray
                        )
                    }
                } else if let rpe = session.rpe {
                    RecapMetric(value: String(format: "%.1f", rpe), label: "RPE", color: rpeColor(rpe))
                }
                if let total = totalWorkoutMin, total > 0 {
                    RecapMetric(value: "\(Int(total)) min", label: total > (session.durationMin ?? 0) + 1 ? "Total séances" : "Durée", color: Color.statusBlue)
                } else if let dur = session.durationMin {
                    RecapMetric(value: String(format: "%.0f min", dur), label: "Durée", color: Color.statusBlue)
                }
                if let energy = session.energyPre {
                    RecapMetric(
                        value: String(repeating: "⚡", count: energy),
                        label: "Énergie",
                        color: Color.statusYellow
                    )
                }
                Spacer()
            }

            // Exercices réalisés
            if let exos = session.exos, !exos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXERCICES")
                        .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                    FlowRow(items: exos.prefix(6).map { $0 }) { ex in
                        Text(ex)
                            .font(.appCaption.weight(.medium))
                            .foregroundColor(color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(color.opacity(0.1))
                            .cornerRadius(5)
                    }
                    if exos.count > 6 {
                        Text("+ \(exos.count - 6) autres")
                            .font(.appCaption).foregroundColor(.gray)
                    }
                }
            }

            // Commentaire
            if let comment = session.comment, !comment.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.appCaption).foregroundColor(.gray)
                    Text(comment)
                        .font(.appCaption).foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func rpeColor(_ rpe: Double) -> Color { RPEHelper.color(for: rpe) }
}

// MARK: - Recap Metric Pill
struct RecapMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.appHeadline.weight(.black))
                .foregroundColor(color)
            Text(label)
                .font(.appMicro.weight(.medium))
                .foregroundColor(.gray)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 4)
    }
}

// MARK: - Flow Row (wrap des tags)
struct FlowRow<Item: StringProtocol, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        // Wrap manuel : HStack en lignes de max 3 items
        let rows = stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0..<min($0 + 3, items.count)])
        }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.0) { _, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.0) { _, item in
                        content(item)
                    }
                }
            }
        }
    }
}

// MARK: - Critical Alert Card

struct CriticalAlertCard: View {
    let signal: CriticalSignal
    let onAction: () -> Void

    @AppStorage("criticalAlertDismissedDate") private var dismissedDate = ""
    @State private var dragOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1

    private var todayStr: String { DateFormatter.isoDate.string(from: Date()) }
    private var isDismissed: Bool { dismissedDate == todayStr }

    var body: some View {
        if !isDismissed {
            cardContent
        }
    }

    private var cardContent: some View {
        HStack(spacing: 12) {
            Image(systemName: signal.icon)
                .font(.appBody.weight(.semibold))
                .foregroundColor(Color.appDanger)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(signal.message)
                    .font(.appLabel)
                    .foregroundColor(Color.appOnSurface.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onAction) {
                    Text(signal.actionLabel)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(Color.appDanger.opacity(0.85))
                        .underline()
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Image(systemName: "chevron.left")
                .font(.appCaption.weight(.medium))
                .foregroundColor(Color.appDanger.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appDanger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appDanger.opacity(0.28), lineWidth: 1))
        .cornerRadius(12)
        .offset(x: dragOffset)
        .opacity(cardOpacity)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.width < 0 {
                        dragOffset = value.translation.width
                        cardOpacity = max(0, 1 + value.translation.width / 160)
                    }
                }
                .onEnded { value in
                    if value.translation.width < -80 {
                        withAnimation(.easeOut(duration: 0.22)) {
                            dragOffset = -UIScreen.main.bounds.width
                            cardOpacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            dismissedDate = todayStr
                        }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            dragOffset = 0
                            cardOpacity = 1
                        }
                    }
                }
        )
    }
}

// MARK: - Seance3BonusStrip (étape 2b)
// CTA bonus autonome, 3 états :
//   - !hasBonus                        → « ＋ Séance bonus » (crée via POST + sheet)
//   - hasBonus && !bonusCompleted      → « → Reprendre la bonus » (sheet direct)
//   - hasBonus && bonusCompleted       → rien (déjà terminée, visible dans historique)
//
// POST direct + throw (doctrine STRUCTURE) via APIService.createBonusSession —
// idempotent côté backend (UNIQUE(date, session_type='bonus')). Bouton désactivé
// pendant l'appel réseau (spinner) pour éviter le double-tap.
struct Seance3BonusStrip: View {
    let hasBonus: Bool
    let bonusCompleted: Bool
    /// Étape 4b-iii — count des exos poussés vers bonus (dash.pushedToBonus.count).
    /// Défaut 0 pour n'imposer aucun call-site à passer le param s'il ne le veut pas.
    var pushedCount: Int = 0
    /// Ancré au parent stable (TodayCardView) — voir commentaire du @State là-bas.
    /// Sinon le sheet host est démonté avec ce body au flip bonusCompleted post-log.
    @Binding var showSheet: Bool
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var buttonLabel: String {
        if hasBonus { return "Reprendre la bonus" }
        if pushedCount > 0 {
            return "Bonus · \(pushedCount) exo\(pushedCount > 1 ? "s" : "") poussé\(pushedCount > 1 ? "s" : "")"
        }
        return "＋ Séance bonus"
    }

    var body: some View {
        if hasBonus && bonusCompleted {
            EmptyView()
        } else {
            Button {
                if hasBonus {
                    showSheet = true
                } else {
                    Task { await createAndOpen() }
                }
            } label: {
                HStack(spacing: 6) {
                    if isCreating {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: hasBonus ? "arrow.right.circle" : "plus.circle")
                    }
                    Text(buttonLabel)
                        .font(.appLabel.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.12))
                .foregroundColor(.gray)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
            .disabled(isCreating)
            .buttonStyle(SpringButtonStyle())
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .alert("Erreur", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
        }
    }

    private func createAndOpen() async {
        isCreating = true
        defer { isCreating = false }
        do {
            _ = try await APIService.shared.createBonusSession()
            CacheInvalidation.sessionMutated.invalidate()
            await APIService.shared.fetchDashboard()
            showSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tomorrow Preview Strip
// Ligne discrète en bas de la carte : « Demain : <nom> · N exos » (repli/dépli).
// Weekday MTL — pattern SeanceView:98-104 (Date().weekday brut décale au fuseau).
struct TomorrowPreviewStrip: View {
    let dash: DashboardData
    @State private var isExpanded = false

    private var tomorrowName: String {
        let localSecs = Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()
        let weekday = ((localSecs / 86400 + 4) % 7) + 1  // Jan 1 1970 = Thu = weekday 5
        let todayIdx = (weekday + 5) % 7                 // 0=Lun … 6=Dim
        let tomorrowIdx = (todayIdx + 1) % 7
        return dash.schedule[TrainingDoctrine.dayNames[tomorrowIdx]] ?? "Repos"
    }

    private var tomorrowExos: [(String, String)] {
        guard let program = dash.fullProgram[tomorrowName] else { return [] }
        return program.map { ($0.key, $0.value.value) }.sorted { $0.0 < $1.0 }
    }

    private var isRest: Bool {
        tomorrowName == "Repos" || tomorrowExos.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().background(Color.appSeparator).padding(.horizontal, 16)

            Button {
                if !isRest {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("DEMAIN")
                        .font(.appMicro.weight(.bold)).tracking(1.5)
                        .foregroundColor(.gray)
                    Text(isRest ? "Repos" : "\(tomorrowName) · \(tomorrowExos.count) exo\(tomorrowExos.count > 1 ? "s" : "")")
                        .font(.appCaption)
                        .foregroundColor(Color.appOnSurface.opacity(0.75))
                        .lineLimit(1)
                    Spacer()
                    if !isRest {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.appMicro.weight(.semibold))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRest)

            if isExpanded && !isRest {
                VStack(spacing: 0) {
                    ForEach(Array(tomorrowExos.prefix(5).enumerated()), id: \.offset) { idx, item in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.appCaption.weight(.black))
                                .foregroundColor(.gray.opacity(0.5))
                                .frame(width: 16)
                            Text(item.0)
                                .font(.appLabel).foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(item.1)
                                .font(.appCaption).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        if idx < tomorrowExos.prefix(5).count - 1 {
                            Divider()
                                .background(Color.appSurfaceInset)
                                .padding(.horizontal, 16)
                        }
                    }
                    if tomorrowExos.count > 5 {
                        Text("+ \(tomorrowExos.count - 5) exercices")
                            .font(.appCaption).foregroundColor(.gray)
                            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 4)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}
