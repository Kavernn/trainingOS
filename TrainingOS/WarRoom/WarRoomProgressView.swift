import SwiftUI
import Charts

struct WarRoomProgressView: View {
    @ObservedObject var store: WarRoomProgressStore
    @ScaledMetric(relativeTo: .headline) private var headlineSize = 17.0
    @ScaledMetric(relativeTo: .body) private var bodySize = 15.0
    @ScaledMetric(relativeTo: .caption) private var captionSize = 11.0
    @ScaledMetric(relativeTo: .caption2) private var microSize = 9.0
    @ScaledMetric(relativeTo: .body) private var cellSize = 44.0
    private var headlineFont: Font { .system(size: headlineSize, weight: .semibold) }
    private var bodyFont: Font { .system(size: bodySize) }
    private var captionFont: Font { .system(size: captionSize) }
    private var microFont: Font { .system(size: microSize) }
    @State private var selectedDay: WarRoomProgress.Day?
    @State private var selectedDate: Date?
    @State private var selectedWeek: Date?
    @State private var showCorrection = false
    @State private var correcting = false
    @State private var correctionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let progress = store.progress {
                    header(progress)
                    if let error = store.error { retry(error) }
                    cumulative(progress).id("warroom.curve")
                    calendar(progress).id("warroom.calendar")
                    rhythm(progress).id("warroom.rhythm")
                    badges(progress).id("warroom.badges")
                } else if store.isLoading {
                    ProgressView("Chargement des victoires…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    retry(store.error ?? "Tes victoires apparaîtront ici.")
                }
            }
            .padding(20)
            .padding(.bottom, 64)
        }
        .background(Color.appBg)
        .refreshable { await store.refresh(force: true) }
        .sheet(item: $selectedDay, onDismiss: { selectedDate = nil; correctionError = nil }) { day in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(day.label, systemImage: symbol(day.state))
                            .font(headlineFont).foregroundStyle(day.state == .victory ? Color.forge : Color.appTextSecondary)
                        if let notes = day.battle?.notes, !notes.isEmpty {
                            Text(notes).font(bodyFont)
                        }
                        if day.isToday { Text("Aujourd’hui · journée en cours").font(captionFont) }
                        if day.battle == nil {
                            Text("Aucun résultat enregistré pour cette date. Une journée non renseignée n’est pas un échec.")
                                .font(bodyFont).foregroundStyle(Color.appTextSecondary)
                        }
                        if day.isToday, let battle = day.battle, battle.status != .active {
                            Button("Corriger le résultat existant") { showCorrection = true }
                                .frame(minHeight: 44).disabled(correcting)
                                .confirmationDialog("Corriger le résultat de cette journée ?", isPresented: $showCorrection) {
                                    Button(battle.status == .victory ? "Renseigné sans victoire" : "Victoire") {
                                        Task {
                                            correcting = true
                                            do {
                                                _ = try await APIService.shared.upsertBattle(date: day.key, status: battle.status == .victory ? .lost : .victory, notes: battle.notes, force: true)
                                                await store.refresh(force: true)
                                                selectedDay = nil
                                            } catch { correctionError = error.localizedDescription }
                                            correcting = false
                                        }
                                    }
                                }
                        }
                        if let correctionError { Text(correctionError).font(captionFont) }
                        Text("Les résultats s’enregistrent depuis le Dashboard.")
                            .font(captionFont).foregroundStyle(Color.appTextMuted)
                    }.padding(24)
                }
                .background(Color.appBg)
                .navigationTitle(day.date.formatted(date: .abbreviated, time: .omitted))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { selectedDay = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func header(_ p: WarRoomProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(p.level.map { "Niveau \($0) · \(p.levelTitle)" } ?? p.levelTitle)
                .font(headlineFont).foregroundStyle(Color.forge)
            Text(p.totalLabel)
                .font(.largeTitle.bold()).foregroundStyle(Color.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if p.victories == 0 {
                Text("Chaque journée compte. Ta première victoire enregistrée depuis le Dashboard apparaîtra ici.")
                    .font(bodyFont).foregroundStyle(Color.appTextSecondary)
            }
            if let next = p.nextThreshold {
                ProgressView(value: p.progressFraction).tint(Color.forge)
                    .accessibilityLabel("Progression vers \(next) journées de victoire")
                Text("\(next - p.victories) \(next - p.victories == 1 ? "victoire" : "victoires") avant le prochain palier")
                    .font(bodyFont)
            } else if p.complete && p.victories >= 100 {
                Text("100 victoires et plus. Tout ce que tu construis continue de compter.")
                    .font(bodyFont)
            }
            Text(p.coverage).font(captionFont).foregroundStyle(Color.appTextMuted)
        }
    }

    private func cumulative(_ p: WarRoomProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Ce que tu as construit", subtitle: p.complete ? "+\(p.victories30) victoires sur les 30 derniers jours" : "Victoires de la période reçue · cumul complet indisponible")
            Chart(p.curve) { day in
                LineMark(x: .value("Date", day.date), y: .value("Victoires cumulées", day.cumulative))
                    .interpolationMethod(.stepEnd).foregroundStyle(Color.forge)
                if day.state == .victory {
                    PointMark(x: .value("Date", day.date), y: .value("Victoires cumulées", day.cumulative))
                        .foregroundStyle(Color.forge).symbol(.circle)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), collisionResolution: .greedy)
                }
            }
            .environment(\.calendar, p.calendar)
            .environment(\.timeZone, p.calendar.timeZone)
            .chartYScale(domain: 0...max(1, p.victories))
            .chartXSelection(value: $selectedDate)
            .frame(height: 190)
            .onChange(of: selectedDate) { _, date in
                guard let date else { return }
                selectedDay = p.curve.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            }
            Text("Touche une date pour consulter son résultat. Une interruption ne retire aucune victoire.")
                .font(captionFont).foregroundStyle(Color.appTextMuted)
        }
    }

    private func calendar(_ p: WarRoomProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Ton calendrier de victoires", subtitle: "12 semaines · fais défiler pour explorer")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(Array(p.calendarWeeks.enumerated()), id: \.offset) { index, week in
                            VStack(spacing: 4) {
                                Text(week[0].date, format: .dateTime.day().month(.twoDigits))
                                    .font(microFont).foregroundStyle(Color.appTextMuted)
                                ForEach(week) { day in
                                    Button { selectedDay = day } label: {
                                        VStack(spacing: 2) {
                                            Image(systemName: symbol(day.state)).font(captionFont.weight(.semibold))
                                            Text(day.date, format: .dateTime.weekday(.narrow)).font(microFont)
                                        }
                                        .foregroundStyle(day.state == .victory ? Color.forge : Color.appTextMuted)
                                        .frame(width: cellSize, height: cellSize)
                                        .background(day.state == .victory ? Color.forge.opacity(0.14) : Color.appSurfaceInset,
                                                    in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(day.isToday ? Color.forge : Color.appSeparatorSubtle,
                                                                                         lineWidth: day.isToday ? 2 : 0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(day.key), \(day.label)\(day.isToday ? ", aujourd’hui" : "")")
                                }
                            }.id(index)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(11, anchor: .trailing) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Victoire", systemImage: "checkmark")
                Label("Renseigné sans victoire", systemImage: "minus")
                Label("Non renseigné", systemImage: "circle")
                Label("En cours · contour pour aujourd’hui", systemImage: "clock")
                Label("Hors suivi connu ou date future", systemImage: "ellipsis")
            }.font(captionFont).foregroundStyle(Color.appTextSecondary)
        }
    }

    private func rhythm(_ p: WarRoomProgress) -> some View {
        let week = selectedWeek.flatMap { date in
            p.weeks.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        } ?? p.weeks.last
        return VStack(alignment: .leading, spacing: 12) {
            title("Ton rythme", subtitle: "8 semaines · la semaine en cours est partielle")
            Chart(p.weeks) { week in
                BarMark(x: .value("Semaine", week.date, unit: .weekOfYear), y: .value("Victoires", week.victories))
                    .foregroundStyle(Color.forge.opacity(week.partial ? 0.55 : 1))
                    .annotation(position: .top) { Text("\(week.victories)\(week.partial ? "*" : "")").font(microFont) }
                    .accessibilityLabel("Semaine du \(week.date.formatted(date: .abbreviated, time: .omitted))")
                    .accessibilityValue("\(week.victories) victoires, \(week.recorded) jours renseignés\(week.partial ? ", partielle" : "")")
            }
            .environment(\.calendar, p.calendar)
            .environment(\.timeZone, p.calendar.timeZone)
            .chartYScale(domain: 0...7)
            .chartXSelection(value: $selectedWeek)
            .frame(height: 170)
            if let week {
                Text("\(week.victories) victoires · \(week.recorded) jours renseignés\(week.partial ? " · semaine partielle" : "")")
                    .font(bodyFont.weight(.semibold))
            }
            Text("* Période partielle : aucune comparaison avec une semaine complète.")
                .font(captionFont).foregroundStyle(Color.appTextMuted)
        }
    }

    private func badges(_ p: WarRoomProgress) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Tes badges", subtitle: "Des étapes réelles, sans points supplémentaires")
            if let last = p.lastBadge {
                Label("Dernier obtenu · \(last.title)", systemImage: "seal.fill")
                    .font(headlineFont).foregroundStyle(Color.forge)
            }
            if let next = p.nextBadge {
                Text("À venir · \(next.title)\n\(next.requirement)").font(bodyFont)
            }
            if !p.complete {
                Text("Badges et paliers en attente d’un historique complet.").font(captionFont)
            }
            ForEach(p.badges) { badge in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: badge.earned ? "checkmark.seal.fill" : "seal")
                        .foregroundStyle(badge.earned ? Color.forge : Color.appTextMuted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(badge.title).font(bodyFont.weight(.semibold))
                        Text(badge.requirement).font(captionFont).foregroundStyle(Color.appTextSecondary)
                        Text(badge.date.map { "Obtenu le \($0)" } ?? "À construire")
                            .font(captionFont).foregroundStyle(Color.appTextMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func title(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(headlineFont).foregroundStyle(Color.appTextPrimary)
            Text(subtitle).font(captionFont).foregroundStyle(Color.appTextSecondary)
        }
    }

    private func retry(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message).font(bodyFont).foregroundStyle(Color.appTextSecondary)
            Button("Réessayer") { Task { await store.refresh(force: true) } }
                .font(bodyFont.weight(.semibold)).frame(minHeight: 44)
        }
    }

    private func symbol(_ state: WarRoomProgress.DayState) -> String {
        switch state {
        case .victory: return "checkmark"
        case .recorded: return "minus"
        case .unreported: return "circle"
        case .ongoing: return "clock"
        case .outside: return "ellipsis"
        }
    }
}
