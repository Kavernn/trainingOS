import SwiftUI

// MARK: - Today Card
struct TodayCardView: View {
    let dash: DashboardData
    var showGreatDayBadge: Bool = false
    var onOpenSession: (() -> Void)? = nil
    var readiness: ReadinessResponse? = nil
    @State private var showReadinessSheet = false
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
                    Text(dash.today)
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
                NavigationLink(destination: BonusSeanceView(isRestDay: false)) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Faire une séance 2")
                            .font(.appLabel.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.12))
                    .foregroundColor(.gray)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
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
                    ReadinessBadge(readiness: readiness)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if dash.today == "Repos" {
                    NavigationLink(destination: BonusSeanceView(isRestDay: true)) {
                        HStack(spacing: 8) {
                            Image(systemName: hasPartialLogs ? "play.fill" : "plus.circle.fill")
                            Text(hasPartialLogs ? "Continuer la séance" : "Faire une séance libre")
                                .font(.appBody.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.gray, Color.gray.opacity(0.75)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color.gray.opacity(0.3), radius: 10, y: 4)
                    }
                    .buttonStyle(SpringButtonStyle())
                    .padding([.horizontal, .bottom], 16)
                    .padding(.top, 12)
                } else {
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
        }
        .glassCardAccent(isLoggedToday ? Color.statusGreen : todayColor)
        .cornerRadius(16)
        .sheet(isPresented: $showReadinessSheet) {
            if let r = readiness {
                ReadinessSheet(readiness: r) { onOpenSession?() }
            }
        }
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
                if let rpe = session.rpe {
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

// MARK: - Séance 2 reminder strip (P2.B.4)
// Strip 44px léger, n'apparaît que les jours splittés. Tap → tab Séance.
struct Seance2ReminderStrip: View {
    let programName: String
    let count: Int
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "2.circle.fill")
                        .font(.appCaption).fontWeight(.bold)
                        .foregroundColor(accent.opacity(0.85))
                    Text("\(programName) — Séance 2")
                        .font(.appCaption).fontWeight(.semibold)
                        .foregroundColor(Color.appOnSurface.opacity(0.90))
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("\(count) exo\(count > 1 ? "s" : "") à faire")
                        .font(.appCaption).fontWeight(.medium)
                        .foregroundColor(Color.appOnSurface.opacity(0.75))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10)).fontWeight(.bold)
                        .foregroundColor(accent.opacity(0.7))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.appSurfaceInset)
                        .overlay(Capsule().stroke(accent.opacity(0.4), lineWidth: 0.5))
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(accent.opacity(0.15))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.35), lineWidth: 0.5))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
