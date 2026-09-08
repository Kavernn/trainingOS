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

    /// Données d'affichage uniquement — ne participe jamais au choix de branche AM/PM.
    private var eveningPreview: [(String, String)] {
        if let name = dash.eveningSessionName,
           let program = dash.fullProgram[name] {
            return program.map { ($0.key, $0.value.value) }.sorted { $0.0 < $1.0 }
        }
        return exercises.filter { dash.pushedToEvening.contains($0.0) }
    }

    /// Projection visuelle de la branche existante — ne pilote aucun CTA ni navigation.
    private var recapPresentation: TodaySessionRecap.Presentation {
        if (dash.hasEveningSession || hasLocalPushedExercises) && !dash.secondSessionCompleted {
            return .morningCompleted
        }
        return .dayCompleted
    }

    private func muscleMapping(for exerciseNames: [String]) -> MuscleMappingResult {
        MuscleMapper.aggregate(
            exerciseNames.compactMap { dash.exerciseMuscleMetadata[$0] }
        )
    }

    @ViewBuilder
    private func muscleMap(for exerciseNames: [String]) -> some View {
        let result = muscleMapping(for: exerciseNames)
        if !result.zones.isEmpty {
            MuscleMapView(
                zones: result.zones,
                tint: Color.domainAccent(.training),
                displayMode: .both
            )
            .frame(maxWidth: .infinity)
            .frame(height: 104)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isLoggedToday ? Color.appSuccess.opacity(0.14) : Color.appSurfaceInset)
                        .frame(width: 42, height: 42)
                    Image(systemName: isLoggedToday ? "checkmark" : todayIcon)
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(isLoggedToday ? Color.appSuccess : todayColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(dash.today.isEmpty ? "Repos" : dash.today)
                        .font(.appTitle.weight(.bold))
                        .foregroundColor(Color.appOnSurface)
                        .lineLimit(1)
                    if let pm = dash.eveningSessionName, !pm.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.stars.fill")
                                .font(.appCaption)
                                .foregroundColor(Color.appTextSecondary)
                            Text(pm)
                                .font(.appCaption)
                                .foregroundColor(Color.appTextSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
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
                            PulsingDot(color: Color.appSuccess)
                            Text("Complété")
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(Color.appSuccess)
                        }
                    }
                } else if !exercises.isEmpty {
                    Text("\(exercises.count) exos")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(Color.appTextSecondary)
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
                    TodaySessionRecap(
                        session: session,
                        sessionName: dash.today,
                        color: todayColor,
                        totalWorkoutMin: dash.totalWorkoutMinToday,
                        presentation: recapPresentation
                    )
                    if recapPresentation == .dayCompleted, dash.today != "Repos" {
                        muscleMap(for: todaySession?.exos ?? [])
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
                // Séance 2 non complétée ET (planifiée backend OU exos poussés localement)
                // → CTA vers SeanceSoirView (flow evening, is_second=true).
                if (dash.hasEveningSession || hasLocalPushedExercises) && !dash.secondSessionCompleted {
                    VStack(alignment: .leading, spacing: 10) {
                        TodayPriorityHeader(
                            title: "À FAIRE MAINTENANT",
                            subtitle: dash.eveningSessionName ?? "Séance 2",
                            icon: "moon.stars.fill"
                        )
                        if !eveningPreview.isEmpty {
                            TodayExercisePreview(exercises: eveningPreview, accent: Color.forge)
                        }
                        muscleMap(for: eveningPreview.map(\.0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Sheet obligatoire (Volet G) — voir SeanceSoirView.swift head.
                    Button { showSeance2Sheet = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text(seance2Label)
                                .font(.appBody.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.shared.accentGradient(startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(Color.onAccent)
                        .cornerRadius(14)
                        .shadow(color: Color.forge.opacity(0.30), radius: 12, y: 5)
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
                    VStack(alignment: .leading, spacing: 10) {
                        TodayPriorityHeader(
                            title: "À FAIRE MAINTENANT",
                            subtitle: dash.today,
                            icon: todayIcon
                        )
                        TodayExercisePreview(exercises: exercises, accent: todayColor)
                        muscleMap(for: exercises.map(\.0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
                                .padding(.vertical, 16)
                                .background(AppTheme.shared.accentGradient(startPoint: .leading, endPoint: .trailing))
                                .foregroundColor(Color.onAccent)
                                .cornerRadius(14)
                                .shadow(color: Color.forge.opacity(0.30), radius: 12, y: 5)
                            }
                        } else {
                            NavigationLink(destination: SeanceView()) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text(hasPartialLogs ? "Continuer la séance" : "Commencer la séance")
                                        .font(.appBody.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppTheme.shared.accentGradient(startPoint: .leading, endPoint: .trailing))
                                .foregroundColor(Color.onAccent)
                                .cornerRadius(14)
                                .shadow(color: Color.forge.opacity(0.30), radius: 12, y: 5)
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

private struct TodayPriorityHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.appMicro.weight(.black))
            .tracking(1.8)
            .foregroundColor(Color.forge)

            Text(subtitle)
                .font(.appHeadline.weight(.bold))
                .foregroundColor(Color.appOnSurface)
                .lineLimit(1)
        }
    }
}

private struct TodayExercisePreview: View {
    let exercises: [(String, String)]
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(exercises.prefix(5).enumerated()), id: \.offset) { index, exercise in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.appCaption.weight(.black))
                        .foregroundColor(accent)
                        .frame(width: 18)
                    Text(exercise.0)
                        .font(.appLabel.weight(.medium))
                        .foregroundColor(Color.appTextPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(exercise.1)
                        .font(.appCaption)
                        .foregroundColor(Color.appTextSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                if index < exercises.prefix(5).count - 1 {
                    Divider().background(Color.appSeparatorSubtle)
                }
            }
            if exercises.count > 5 {
                Text("+ \(exercises.count - 5) exercices")
                    .font(.appCaption.weight(.medium))
                    .foregroundColor(Color.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .background(Color.appSurfaceInset)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appSeparatorSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Today Session Recap
struct TodaySessionRecap: View {
    enum Presentation: Equatable {
        case morningCompleted
        case dayCompleted
    }

    let session: SessionEntry
    let sessionName: String
    let color: Color
    var totalWorkoutMin: Double? = nil
    let presentation: Presentation
    @ObservedObject private var units = UnitSettings.shared

    private var morningSlot: SessionSlot? {
        session.slots?.first { $0.type == "morning" }
    }

    private var morningRPE: Double? {
        morningSlot?.rpe ?? session.rpe
    }

    private var morningDuration: Double? {
        morningSlot?.durationMin ?? session.durationMin
    }

    private var dayDuration: Double? {
        if let totalWorkoutMin, totalWorkoutMin > 0 { return totalWorkoutMin }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.appHeadline)
                    .foregroundColor(Color.appSuccess)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation == .morningCompleted ? "AM TERMINÉE" : "JOURNÉE COMPLÉTÉE")
                        .font(.appMicro.weight(.black))
                        .tracking(1.6)
                        .foregroundColor(Color.appSuccess)
                    Text(sessionName)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(Color.appOnSurface)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                if presentation == .morningCompleted {
                    if let duration = morningDuration, duration > 0 {
                        RecapMetric(value: "\(Int(duration)) min", label: "Durée", color: Color.appInfo)
                    }
                    if let rpe = morningRPE {
                        RecapMetric(value: String(format: "%.1f", rpe), label: "RPE", color: rpeColor(rpe))
                    }
                } else {
                    if let duration = dayDuration, duration > 0 {
                        RecapMetric(value: "\(Int(duration)) min", label: "Durée totale", color: Color.appInfo)
                    }
                    if let volume = session.sessionVolume, volume > 0 {
                        RecapMetric(value: units.format(volume, decimals: 0), label: "Volume total", color: Color.forge)
                    }
                }
                Spacer()
            }

            if presentation == .dayCompleted,
               let slots = session.slots,
               slots.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                        if let rpe = slot.rpe {
                            RecapMetric(
                                value: String(format: "%.1f", rpe),
                                label: "RPE \(slot.label)",
                                color: rpeColor(rpe),
                                compact: true
                            )
                        }
                    }
                    Spacer()
                }
            }

            // Exercices réalisés
            if let exos = session.exos, !exos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXERCICES")
                        .font(.appMicro.weight(.bold))
                        .tracking(2)
                        .foregroundColor(Color.appTextSecondary)
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
                            .font(.appCaption)
                            .foregroundColor(Color.appTextSecondary)
                    }
                }
            }

            // Commentaire
            if let comment = session.comment, !comment.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.appCaption)
                        .foregroundColor(Color.appTextSecondary)
                    Text(comment)
                        .font(.appCaption)
                        .foregroundColor(Color.appTextSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .background(Color.appSurfaceInset.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appSeparatorSubtle, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func rpeColor(_ rpe: Double) -> Color { RPEHelper.color(for: rpe) }
}

// MARK: - Recap Metric Pill
struct RecapMetric: View {
    let value: String
    let label: String
    let color: Color
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(compact ? .appLabel.weight(.bold) : .appHeadline.weight(.black))
                .foregroundColor(color)
            Text(label)
                .font(.appMicro.weight(.medium))
                .foregroundColor(Color.appTextSecondary)
        }
        .frame(minWidth: compact ? 54 : 82, alignment: .leading)
        .padding(.horizontal, compact ? 9 : 11)
        .padding(.vertical, compact ? 7 : 9)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.appSeparatorSubtle, lineWidth: 1)
        )
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
struct TomorrowPreviewStrip: View {
    let dash: DashboardData
    @State private var isExpanded = false

    private var tomorrowName: String {
        TrainingDoctrine.tomorrowSessionName(from: dash.schedule)
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
