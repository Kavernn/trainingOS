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

    var todayColor: Color {
        let low = dash.today.lowercased()
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") { return .green }
        if low.contains("pull")  { return .cyan }
        if low.contains("push") || low.contains("upper") { return .orange }
        if low.contains("legs") || low.contains("lower") { return .yellow }
        if low.contains("yoga")  { return .purple }
        return .blue
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
                        .foregroundColor(isLoggedToday ? .green : todayColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(dash.today)
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(isLoggedToday ? .green : todayColor)
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
                            PulsingDot(color: .green)
                            Text("Complété")
                                .font(.appCaption.weight(.semibold)).foregroundColor(.green)
                        }
                    }
                } else if !exercises.isEmpty {
                    Text("\(exercises.count) exos")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)

            if isLoggedToday {
                // ── Récap séance loggée ───────────────────────────────────
                // isLoggedToday peut être vrai via alreadyLoggedToday même sans session dans le dict
                if let session = todaySession {
                    TodaySessionRecap(session: session, color: todayColor, totalWorkoutMin: dash.totalWorkoutMinToday)
                }
                NavigationLink(destination: BonusSeanceView()) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Faire une séance bonus")
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
                                    .font(.appLabel).foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.1)
                                    .font(.appCaption).foregroundColor(.gray)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            if idx < exercises.prefix(5).count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.04))
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
                    NavigationLink(destination: BonusSeanceView()) {
                        HStack(spacing: 8) {
                            Image(systemName: hasPartialLogs ? "play.fill" : "plus.circle.fill")
                            Text(hasPartialLogs ? "Continuer la séance" : "Faire une séance")
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
        .glassCardAccent(isLoggedToday ? .green : todayColor)
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
                    RecapMetric(value: "\(Int(total)) min", label: total > (session.durationMin ?? 0) + 1 ? "Total séances" : "Durée", color: .blue)
                } else if let dur = session.durationMin {
                    RecapMetric(value: String(format: "%.0f min", dur), label: "Durée", color: .blue)
                }
                if let energy = session.energyPre {
                    RecapMetric(
                        value: String(repeating: "⚡", count: energy),
                        label: "Énergie",
                        color: .yellow
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

// MARK: - Stats Row
struct StatsRowView: View {
    let dash: DashboardData
    @ObservedObject private var units = UnitSettings.shared

    var totalSessions: Int { dash.sessions.count }
    var avgRPE: Double {
        let rpes = dash.sessions.values.compactMap(\.rpe)
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }
    var weekSessions: Int {
        let fmt = DateFormatter.isoDate
        let todayStr = fmt.string(from: Date())
        guard let todayMidnight = fmt.date(from: todayStr) else { return 0 }
        let base = todayMidnight.timeIntervalSince1970
        let epochDays = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 86400
        let weekday = ((epochDays + 4) % 7) + 1
        let daysSinceMonday = (weekday + 5) % 7
        var count = 0
        for i in 0...daysSinceMonday {
            let d = Date(timeIntervalSince1970: base - Double(i) * 86400.0)
            if dash.sessions[fmt.string(from: d)] != nil { count += 1 }
        }
        return count
    }
    var totalVolume: String {
        let vol = dash.sessions.values.compactMap(\.sessionVolume).reduce(0, +)
        return vol > 0 ? _formatK(units.display(vol)) + " \(units.label)" : "—"
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatPill(value: "\(totalSessions)", label: "SÉANCES", color: Color.forge)
            StatPill(value: avgRPE > 0 ? String(format: "%.1f", avgRPE) : "—", label: "RPE MOY", color: .purple)
            StatPill(value: "\(weekSessions)", label: "CETTE SEMAINE", color: .cyan)
            StatPill(value: totalVolume, label: "VOLUME TOTAL", color: .green)
        }
    }
}

// MARK: - Heatmap
struct HeatmapView: View {
    let sessions: [String: SessionEntry]

    private var last30Days: [(String, Bool)] {
        let base = Date().timeIntervalSince1970
        return (0..<30).reversed().map { offset in
            let date = Date(timeIntervalSince1970: base - Double(offset) * 86400.0)
            let key = DateFormatter.isoDate.string(from: date)
            return (key, sessions[key] != nil)
        }
    }

    var activeDays: Int { last30Days.filter(\.1).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(title: "ASSIDUITÉ")
                    Text("Jours d'entraînement complétés")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(activeDays)")
                        .font(.appTitle.weight(.black))
                        .foregroundColor(Color.forge)
                    Text("sur 30 jours")
                        .font(.appCaption)
                        .foregroundColor(.gray)
                }
            }

            // Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                ForEach(Array(last30Days.enumerated()), id: \.0) { idx, day in
                    let isToday = idx == last30Days.count - 1
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.1 ? Color.forge : Color.white.opacity(0.04))
                        if isToday {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                        } else if day.1 {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.forge.opacity(0.3), lineWidth: 0.5)
                        }
                    }
                    .frame(height: 22)
                }
            }

            // Barre d'assiduité
            let pct = Double(activeDays) / 30.0
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Assiduité")
                        .font(.appCaption).foregroundColor(.gray)
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.appCaption.weight(.bold)).foregroundColor(Color.forge)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07)).frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(colors: [Color.forge, .yellow], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * pct), height: 4)
                    }
                }
                .frame(height: 4)
            }

            // Légende
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.forge)
                        .frame(width: 12, height: 12)
                    Text("Entraînement")
                        .font(.appCaption).foregroundColor(.gray)
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    Text("Aujourd'hui")
                        .font(.appCaption).foregroundColor(.gray)
                }
                Spacer()
                Text("← passé   présent →")
                    .font(.appMicro).foregroundColor(.gray.opacity(0.5))
            }
        }
        .padding(16)
        .glassCard()
        .cornerRadius(16)
    }
}

// MARK: - Week Grid
struct WeekGridView: View {
    let schedule: [String: String]
    let sessions: [String: SessionEntry]

    private let days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    private func dateForDay(_ index: Int) -> String {
        let epochDays = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 86400
        let weekday = ((epochDays + 4) % 7) + 1
        let daysSinceMonday = (weekday + 5) % 7
        let base = Date().timeIntervalSince1970
        let monday = Date(timeIntervalSince1970: base - Double(daysSinceMonday) * 86400.0)
        let day = Date(timeIntervalSince1970: monday.timeIntervalSince1970 + Double(index) * 86400.0)
        return DateFormatter.isoDate.string(from: day)
    }

    private func isToday(_ index: Int) -> Bool {
        let epochDays = (Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 86400
        let weekday = ((epochDays + 4) % 7) + 1
        return index == (weekday + 5) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "CETTE SEMAINE")

            let scheduleKeys = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    let seance = schedule[scheduleKeys[i]] ?? "Repos"
                    let dateStr = dateForDay(i)
                    let done = sessions[dateStr] != nil
                    let today = isToday(i)

                    VStack(spacing: 5) {
                        Text(days[i])
                            .font(.appCaption.weight(today ? .bold : .medium))
                            .foregroundColor(today ? .white : .gray)

                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(done ? seanceColor(seance) : seanceColor(seance).opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(today ? seanceColor(seance).opacity(0.6) : seanceColor(seance).opacity(0.15), lineWidth: today ? 1.5 : 0.5)
                                )

                            if done {
                                Image(systemName: "checkmark")
                                    .font(.appMicro.weight(.bold))
                                    .foregroundColor(.white)
                            } else {
                                Text(seanceShort(seance))
                                    .font(.appCaption.weight(.bold))
                                    .foregroundColor(seanceColor(seance))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .padding(.horizontal, 2)
                            }
                        }
                        .frame(height: 32)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .glassCard()
        .cornerRadius(16)
    }

    private func seanceShort(_ s: String) -> String {
        let low = s.lowercased()
        if low.contains("upper")   { return s.replacingOccurrences(of: "Upper", with: "UPP") }
        if low.contains("lower")   { return s.replacingOccurrences(of: "Lower", with: "LOW") }
        if low.contains("push")    { return s.replacingOccurrences(of: "Push", with: "PSH") }
        if low.contains("pull")    { return s.replacingOccurrences(of: "Pull", with: "PLL") }
        if low.contains("legs")    { return s.replacingOccurrences(of: "Legs", with: "LEGS") }
        if low.contains("yoga")    { return "YOGA" }
        if low.contains("recovery") || low == "rec" { return "REC" }
        if low.contains("full body") { return "FB" }
        // Generic fallback: up to 6 chars
        return String(s.prefix(6)).uppercased()
    }

    private func seanceColor(_ s: String) -> Color {
        let low = s.lowercased()
        if low.contains("upper")    { return .orange }
        if low.contains("lower")    { return .yellow }
        if low.contains("push")     { return .orange }
        if low.contains("pull")     { return .cyan }
        if low.contains("legs")     { return .yellow }
        if low.contains("yoga")     { return .purple }
        if low.contains("recovery") { return .green }
        if low.contains("full body"){ return .mint }
        return .gray
    }
}

// MARK: - SoirCardView

struct SoirCardView: View {
    let data: SeanceSoirData

    private var sessionName: String { data.todaySoir ?? "Séance du soir" }

    private var sessionColor: Color {
        switch sessionName {
        case "Push A", "Push B":             return .orange
        case "Pull A", "Pull B + Full Body": return .cyan
        case "Legs":                         return .yellow
        case "Yoga / Tai Chi":               return .purple
        case "Recovery":                     return .green
        default:                             return .blue
        }
    }

    private var sessionIcon: String {
        switch sessionName {
        case "Push A", "Push B", "Pull A", "Pull B + Full Body", "Legs": return "dumbbell.fill"
        case "Yoga / Tai Chi": return "figure.mind.and.body"
        case "Recovery":       return "heart.fill"
        default:               return "moon.stars.fill"
        }
    }

    private var exercises: [(String, String)] {
        guard let program = data.fullProgram[sessionName] else { return [] }
        return program.map { ($0.key, $0.value.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(sessionColor.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: data.alreadyLogged ? "checkmark" : sessionIcon)
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(data.alreadyLogged ? .green : sessionColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("CE SOIR")
                        .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                    Text(sessionName)
                        .font(.appBody.weight(.bold))
                        .foregroundColor(data.alreadyLogged ? .green : sessionColor)
                }
                Spacer()
                if data.alreadyLogged {
                    HStack(spacing: 5) {
                        PulsingDot(color: .green)
                        Text("Complété")
                            .font(.appCaption.weight(.semibold)).foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)

            if !exercises.isEmpty && !data.alreadyLogged {
                VStack(spacing: 0) {
                    ForEach(exercises.prefix(5), id: \.0) { ex, sets in
                        HStack {
                            Circle().fill(sessionColor.opacity(0.25)).frame(width: 5, height: 5)
                            Text(ex)
                                .font(.appLabel).foregroundColor(.white)
                            Spacer()
                            Text(sets)
                                .font(.appCaption).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 7)
                    }
                    if exercises.count > 5 {
                        Text("+ \(exercises.count - 5) exercices")
                            .font(.appCaption).foregroundColor(.gray)
                            .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                }
            }

            if !data.alreadyLogged {
                NavigationLink(destination: SeanceSoirView()) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill")
                        Text("Commencer la séance du soir")
                            .font(.appBody.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [sessionColor, sessionColor.opacity(0.75)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: sessionColor.opacity(0.4), radius: 10, y: 4)
                }
                .buttonStyle(SpringButtonStyle())
                .padding([.horizontal, .bottom], 16)
                .padding(.top, 12)
            }
        }
        .glassCardAccent(data.alreadyLogged ? .green : sessionColor)
        .cornerRadius(16)
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
                .foregroundColor(.red)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(signal.message)
                    .font(.appLabel)
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onAction) {
                    Text(signal.actionLabel)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(Color.red.opacity(0.85))
                        .underline()
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Image(systemName: "chevron.left")
                .font(.appCaption.weight(.medium))
                .foregroundColor(.red.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.red.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.28), lineWidth: 1))
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
