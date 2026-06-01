import SwiftUI

// MARK: - Daily Streak Card

struct DailyStreakCard: View {
    let sessions: [String: SessionEntry]
    var streakData: StreakResponse? = nil
    @State private var prevStreak = 0
    @State private var milestoneScale: CGFloat = 1.0

    private static let milestones: Set<Int> = [3, 7, 14, 21, 30, 50, 100]

    private var streaks: (current: Int, best: Int) {
        if let s = streakData { return (s.currentStreak, s.bestStreak) }
        // Fallback: calcul local (données serveur non disponibles)
        let fmt = DateFormatter.isoDate
        let todayStr = fmt.string(from: Date())
        guard let todayMidnight = fmt.date(from: todayStr) else { return (0, 0) }
        let base = todayMidnight.timeIntervalSince1970
        var current = 0
        for i in 0..<365 {
            let key = fmt.string(from: Date(timeIntervalSince1970: base - Double(i) * 86400.0))
            if sessions[key] != nil { current += 1 }
            else if i == 0 { continue }
            else { break }
        }
        let sortedEpochs = sessions.keys
            .compactMap { fmt.date(from: $0)?.timeIntervalSince1970 }
            .sorted()
        var best = current; var run = 1
        for i in 1..<sortedEpochs.count {
            if (sortedEpochs[i] - sortedEpochs[i - 1]) / 86400.0 < 1.5 { run += 1; best = max(best, run) }
            else { run = 1 }
        }
        if !sortedEpochs.isEmpty { best = max(best, run) }
        return (current, best)
    }

    var body: some View {
        let (cur, best) = streaks
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(cur > 0 ? "🔥" : "💪")
                        .font(.system(size: 20))
                        .scaleEffect(milestoneScale)
                    Text("\(cur)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(cur > 0 ? .forge : .white)
                        .contentTransition(.numericText())
                    Text("jour\(cur != 1 ? "s" : "")")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(.bottom, 3)
                }
                if cur == 0 {
                    Text("Jour 0. La machine est à l'arrêt.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                } else if cur >= best && best > 0 {
                    Text("Record actif — \(cur) jour\(cur != 1 ? "s" : ""). Tu réécris l'histoire.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.forge)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    let gap = best - cur
                    if gap <= 5 {
                        Text("\(gap) jour\(gap != 1 ? "s" : "") du record. Écrase-le.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.forge.opacity(0.75))
                    } else {
                        Text("jours sans faiblir")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(best)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(cur >= best && best > 0 ? .forge.opacity(0.6) : .white.opacity(0.35))
                    .contentTransition(.numericText())
                Text(cur >= best && best > 0 ? "pulvérisé" : "à détruire")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cur > 0 ? Color.forge.opacity(0.07) : Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(cur > 0 ? Color.forge.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .onAppear { prevStreak = cur }
        .onChange(of: cur) { newVal in
            if DailyStreakCard.milestones.contains(newVal) && newVal > prevStreak {
                // Milestone haptic + bounce animation
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                triggerNotificationFeedback(.success)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                    milestoneScale = 1.4
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.15)) {
                    milestoneScale = 1.0
                }
            }
            prevStreak = newVal
        }
    }
}

// MARK: - CH Monogram

struct CHMonogram: View {
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.686, green: 0.118, blue: 0.176))
                .frame(width: size, height: size)
            Text("CH")
                .font(.system(size: size * 0.36, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Habs Widget

struct HabsWidget: View {
    @ObservedObject var service: NHLService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CHMonogram(size: 22)
                Text("Canadiens de Montréal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                if service.isLoading {
                    ProgressView().scaleEffect(0.55).tint(.gray)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            habsContent
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    @ViewBuilder
    private var habsContent: some View {
        if let live = service.liveGame {
            liveRow(live)
        } else if let last = service.lastGame {
            HStack(spacing: 0) {
                lastGameRow(last)
                if let next = service.nextGame {
                    Spacer()
                    nextGameBadge(next)
                }
            }
        } else if let next = service.nextGame {
            nextGameFull(next)
        } else if service.failed {
            // D-D11: show retry button instead of dead-end text
            HStack(spacing: 8) {
                Text("Données indisponibles")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.6))
                Spacer()
                Button {
                    Task { await service.fetch() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        } else if service.isOffSeason {
            // D-C3: hide widget content entirely during off-season (widget hidden at call site)
            EmptyView()
        } else if !service.isLoading {
            EmptyView()
        }
    }

    private func liveRow(_ game: HabsGame) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                CHMonogram(size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    scoreLabel(game)
                    if case .live(let period, let time) = game.status {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                            Text([period, time].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.9))
                        }
                    }
                }
                Spacer()
                Text(game.opponent)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
            }
            if let stats = game.stats {
                statsRow(stats)
            }
        }
    }

    private func lastGameRow(_ game: HabsGame) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                CHMonogram(size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    scoreLabel(game)
                    if let won = game.habsWon {
                        HStack(spacing: 3) {
                            Image(systemName: won ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 9))
                            Text(won ? "Victoire · \(game.opponent)" : "Défaite · \(game.opponent)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(won ? .green : Color(red: 0.85, green: 0.3, blue: 0.3))
                    }
                }
            }
            if let stats = game.stats {
                statsRow(stats)
            }
        }
    }

    private func statsRow(_ stats: HabsGameStats) -> some View {
        HStack(spacing: 0) {
            statCol(label: "Tirs",    value: "\(stats.habsShots) – \(stats.oppShots)")
            Spacer()
            statCol(label: "Coups",   value: "\(stats.habsHits) – \(stats.oppHits)")
            Spacer()
            statCol(label: "Bloqués", value: "\(stats.habsBlocked) – \(stats.oppBlocked)")
        }
        .padding(.top, 2)
        .padding(.horizontal, 2)
    }

    private func statCol(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func nextGameBadge(_ game: HabsGame) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Prochain")
                .font(.system(size: 9))
                .foregroundColor(.gray.opacity(0.55))
            Text("vs \(game.opponent)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
            if case .upcoming(let label) = game.status {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
    }

    private func nextGameFull(_ game: HabsGame) -> some View {
        HStack(spacing: 12) {
            CHMonogram(size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("Prochain match")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Text("vs \(game.opponent)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                if case .upcoming(let label) = game.status {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            Spacer()
        }
    }

    private func scoreLabel(_ game: HabsGame) -> some View {
        HStack(spacing: 6) {
            Text("\(game.habsScore ?? 0)")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text("–")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.gray)
            Text("\(game.oppScore ?? 0)")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Quote of the Day

struct QuoteOfDayView: View {
    private var quote: DailyQuote { QuoteData.today() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("❝")
                    .font(.system(size: 20))
                    .foregroundColor(.orange.opacity(0.55))
                Spacer()
                Text("SIGNAL DU JOUR")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.gray.opacity(0.45))
            }
            Text(quote.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("— \(quote.author)  ·  \(quote.context)")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.18), Color.clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Goal Reminder

// D-C2: GoalReminderView is now a NavigationLink to ObjectifsView
struct GoalReminderView: View {
    let goal: String

    var body: some View {
        NavigationLink(destination: ObjectifsView()) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "target")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cible")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                    Text(goal)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCard)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.14), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Daily Metrics Row

struct DailyMetricsRow: View {
    let readinessScore: Int?
    let recovery: RecoveryEntry?
    let nutritionTotals: NutritionTotals
    let nutritionSettings: NutritionSettings?
    let moodDue: MoodDueStatus?
    // D-D14: show asterisk when score is computed locally (HRV/server data unavailable)
    var readinessIsLocal: Bool = false
    var onMoodTap: (() -> Void)? = nil
    var hrvAnalysis: HRVAnalysis? = nil

    private var calorieGoal: Double? {
        nutritionSettings?.calories
    }
    private var caloriePct: Int? {
        guard let eaten = nutritionTotals.calories, let goal = calorieGoal, goal > 0 else { return nil }
        return min(150, Int((eaten / goal) * 100))
    }
    private var readinessColor: Color {
        guard let s = readinessScore else { return .gray }
        if s >= 80 { return .green }
        if s >= 60 { return .yellow }
        if s >= 40 { return .orange }
        return .red
    }

    private var readinessAttention: Bool {
        guard let s = readinessScore else { return false }
        return s >= 40 && s < 60
    }

    private var hrvAttention: Bool {
        guard let hrv = hrvAnalysis,
              let rmssd = hrv.todayRmssd,
              let baseline = hrv.hrv30dAvg,
              baseline > 0 else { return false }
        let ratio = rmssd / baseline
        return ratio >= 0.80 && ratio < 0.90
    }

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(destination: RecoveryView()) {
                MetricChip(
                    icon: "heart.fill",
                    value: readinessScore.map { "\($0)" } ?? "–",
                    unit: readinessScore != nil ? "/100" : "",
                    label: readinessIsLocal ? "Préparation ↗" : "Préparation",
                    color: readinessColor,
                    isAttention: readinessAttention
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: NutritionView()) {
                MetricChip(
                    icon: "flame.fill",
                    value: nutritionTotals.calories.map { "\(Int($0))" } ?? "–",
                    unit: "kcal",
                    label: caloriePct.map { "\($0)% de la cible" } ?? "Nutrition",
                    color: .orange
                )
            }
            .buttonStyle(.plain)

            Group {
                let chip = MetricChip(
                    icon: "brain.head.profile",
                    value: moodDue.map { $0.isDue ? "!" : "✓" } ?? "–",
                    unit: "",
                    label: moodDue.map { $0.isDue ? "Non évalué" : "Évalué" } ?? "Mental",
                    color: moodDue.map { $0.isDue ? Color.yellow : Color.green } ?? .gray
                )
                if let onMoodTap {
                    Button(action: onMoodTap) { chip }.buttonStyle(.plain)
                } else {
                    chip
                }
            }

            // HRV compact — visible seulement si baseline disponible ou valeur du jour
            if let hrv = hrvAnalysis, hrv.todayRmssd != nil || hrv.baselineAvailable {
                NavigationLink(destination: RecoveryView()) {
                    MetricChip(
                        icon: "waveform.path.ecg",
                        value: hrv.todayRmssd.map { "\(Int($0))\(hrv.trendArrow)" } ?? "–",
                        unit: hrv.todayRmssd != nil ? "ms" : "",
                        label: hrv.hrvZone != nil ? (hrv.hrvZone == "green" ? "HRV optimal" : hrv.hrvZone == "orange" ? "HRV normal" : "HRV faible") : "HRV",
                        color: hrv.zoneColor,
                        isAttention: hrvAttention
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MetricChip: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let color: Color
    var isAttention: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                if isAttention {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appCard)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                    isAttention ? Color.orange.opacity(0.25) : Color.white.opacity(0.06),
                    lineWidth: 1
                ))
        )
    }
}

// MARK: - XP Chip

struct XPChipView: View {
    let sessions: [String: SessionEntry]

    private var xp: Int { sessions.count * 100 }
    private var level: Int { max(1, xp / 1500 + 1) }
    private var xpInLevel: Int { xp % 1500 }
    private var progress: CGFloat { CGFloat(xpInLevel) / 1500.0 }

    private var levelTitle: String {
        switch level {
        case 1: return "Recrue"
        case 2: return "Combattant"
        case 3: return "Warrior"
        case 4: return "Élite"
        case 5: return "Prédateur"
        default: return "Légende"
        }
    }

    var body: some View {
        NavigationLink(destination: XPView()) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.yellow.opacity(0.18)).frame(width: 36, height: 36)
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.yellow)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Niveau \(level) · \(levelTitle)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(xpInLevel) / 1500 XP")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.yellow.opacity(0.12)).frame(height: 5)
                            RoundedRectangle(cornerRadius: 3).fill(Color.yellow)
                                .frame(width: geo.size.width * min(progress, 1.0), height: 5)
                        }
                    }
                    .frame(height: 5)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.yellow.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.yellow.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.15), lineWidth: 1))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quotes Data

struct DailyQuote {
    let text: String
    let author: String
    let context: String
}

enum QuoteData {
    static func today() -> DailyQuote {
        let tz = TimeZone.current.secondsFromGMT()
        let dayIndex = (Int(Date().timeIntervalSince1970) + tz) / 86400
        return allQuotes[((dayIndex % allQuotes.count) + allQuotes.count) % allQuotes.count]
    }

    static let allQuotes: [DailyQuote] = [
        // Marc Aurèle
        .init(text: "You have power over your mind, not outside events. Realize this, and you will find strength.",
              author: "Marc Aurèle", context: "Méditations, ~170 AD"),
        .init(text: "Waste no more time arguing about what a good man should be. Be one.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "The impediment to action advances action. What stands in the way becomes the way.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "If it is not right, do not do it; if it is not true, do not say it.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "Confine yourself to the present.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "Never esteem anything as of advantage if it will make you break your word or lose your self-respect.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "The first rule is to keep an untroubled spirit. The second is to look things in the face and know them for what they are.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "You could leave life right now. Let that determine what you do and say and think.",
              author: "Marc Aurèle", context: "Méditations"),
        // Sénèque
        .init(text: "Begin at once to live, and count each separate day as a separate life.",
              author: "Sénèque", context: "Lettres à Lucilius, 65 AD"),
        .init(text: "Luck is what happens when preparation meets opportunity.",
              author: "Sénèque", context: "Lettres à Lucilius"),
        .init(text: "It is not that things are difficult that we do not dare, it is because we do not dare that they are difficult.",
              author: "Sénèque", context: "Lettres à Lucilius"),
        .init(text: "Omnia aliena sunt, tempus tantum nostrum est.",
              author: "Sénèque", context: "«Tout est étranger ; seul le temps est nôtre.» — Lettres à Lucilius"),
        // Épictète
        .init(text: "No man is free who is not master of himself.",
              author: "Épictète", context: "Discours"),
        .init(text: "Make the best use of what is in your power, and take the rest as it happens.",
              author: "Épictète", context: "Enchiridion"),
        .init(text: "First say to yourself what you would be, then do what you have to do.",
              author: "Épictète", context: "Discours III.23"),
        // Kobe Bryant
        .init(text: "The most important thing is to try and inspire people so that they can be great in whatever they want to do.",
              author: "Kobe Bryant", context: "Interview, 2018"),
        .init(text: "Everything negative — pressure, challenges — is all an opportunity for me to rise.",
              author: "Kobe Bryant", context: "The Mamba Mentality"),
        .init(text: "If you're afraid to fail, then you're probably going to fail.",
              author: "Kobe Bryant", context: "The Mamba Mentality"),
        .init(text: "The best competition I have is against myself, to become better.",
              author: "Kobe Bryant", context: "The Mamba Mentality"),
        .init(text: "I have self-doubt. I have insecurity. I have fear of failure. But I don't let it stop me.",
              author: "Kobe Bryant", context: "The Mamba Mentality"),
        // Michael Jordan
        .init(text: "I've failed over and over and over again in my life. And that is why I succeed.",
              author: "Michael Jordan", context: "Nike, 1997"),
        .init(text: "I can accept failure. Everyone fails at something. But I can't accept not trying.",
              author: "Michael Jordan", context: "I Can't Accept Not Trying, 1994"),
        .init(text: "Talent wins games, but teamwork and intelligence win championships.",
              author: "Michael Jordan", context: "I Can't Accept Not Trying"),
        .init(text: "You have to expect things of yourself before you can do them.",
              author: "Michael Jordan", context: "Attribué"),
        // Muhammad Ali
        .init(text: "I hated every minute of training, but I said: don't quit. Suffer now and live the rest of your life as a champion.",
              author: "Muhammad Ali", context: "Biographie"),
        .init(text: "Champions aren't made in gyms. Champions are made from something they have deep inside them — a desire, a dream, a vision.",
              author: "Muhammad Ali", context: "Interview"),
        .init(text: "Float like a butterfly, sting like a bee. His hands can't hit what his eyes can't see.",
              author: "Muhammad Ali", context: "Avant le combat Liston, 1964"),
        .init(text: "Impossible is just a big word thrown around by small men who find it easier to live in the world they've been given than to explore the power they have to change it.",
              author: "Muhammad Ali", context: "Adidas, 2004"),
        // David Goggins
        .init(text: "You are in danger of living a life so comfortable and so soft that you will die without ever realizing your true potential.",
              author: "David Goggins", context: "Can't Hurt Me, 2018"),
        .init(text: "The most important conversations you'll ever have are the ones you'll have with yourself.",
              author: "David Goggins", context: "Can't Hurt Me"),
        .init(text: "When you think that you are done, you're only 40% done.",
              author: "David Goggins", context: "La règle des 40%"),
        .init(text: "Don't stop when you're tired. Stop when you're done.",
              author: "David Goggins", context: "Attribué"),
        // Jocko Willink
        .init(text: "Discipline equals freedom.",
              author: "Jocko Willink", context: "Discipline Equals Freedom, 2017"),
        .init(text: "Don't count on motivation. Count on discipline.",
              author: "Jocko Willink", context: "Discipline Equals Freedom"),
        .init(text: "It's not what you preach, it's what you tolerate.",
              author: "Jocko Willink", context: "Extreme Ownership, 2015"),
        .init(text: "Extreme ownership: leaders must own everything in their world.",
              author: "Jocko Willink", context: "Extreme Ownership"),
        // Naval Ravikant
        .init(text: "Play long-term games with long-term people.",
              author: "Naval Ravikant", context: "How to Get Rich, 2019"),
        .init(text: "Seek wealth, not money or status. Wealth is having assets that earn while you sleep.",
              author: "Naval Ravikant", context: "How to Get Rich"),
        .init(text: "The more you desire specific things, the more you suffer when you don't get them.",
              author: "Naval Ravikant", context: "Almanack of Naval Ravikant"),
        // Steve Jobs
        .init(text: "The only way to do great work is to love what you do.",
              author: "Steve Jobs", context: "Stanford, 2005"),
        .init(text: "Stay hungry. Stay foolish.",
              author: "Steve Jobs", context: "Stanford, 2005"),
        .init(text: "Your time is limited, so don't waste it living someone else's life.",
              author: "Steve Jobs", context: "Stanford, 2005"),
        .init(text: "Innovation is saying no to 1,000 things.",
              author: "Steve Jobs", context: "WWDC, 1997"),
        // Bruce Lee
        .init(text: "To hell with circumstances; I create opportunities.",
              author: "Bruce Lee", context: "Tao of Jeet Kune Do, 1975"),
        .init(text: "Absorb what is useful, discard what is not, add what is uniquely your own.",
              author: "Bruce Lee", context: "Tao of Jeet Kune Do"),
        .init(text: "Do not pray for an easy life, pray for the strength to endure a difficult one.",
              author: "Bruce Lee", context: "Tao of Jeet Kune Do"),
        .init(text: "A goal is not always meant to be reached; it often serves simply as something to aim at.",
              author: "Bruce Lee", context: "Tao of Jeet Kune Do"),
        // Athlètes & militaires
        .init(text: "We don't rise to the level of our expectations; we fall to the level of our training.",
              author: "Archilochus", context: "Poème grec, ~650 BC"),
        .init(text: "It's not the mountain we conquer, but ourselves.",
              author: "Sir Edmund Hillary", context: "1953"),
        .init(text: "Success is not final, failure is not fatal: it is the courage to continue that counts.",
              author: "Winston Churchill", context: "Attribué"),
        .init(text: "If you're going through hell, keep going.",
              author: "Winston Churchill", context: "Attribué"),
        .init(text: "You miss 100% of the shots you don't take.",
              author: "Wayne Gretzky", context: "Interview"),
        .init(text: "Strength does not come from physical capacity. It comes from an indomitable will.",
              author: "Mahatma Gandhi", context: "Young India, 1919"),
        .init(text: "Whether you think you can, or you think you can't — you're right.",
              author: "Henry Ford", context: "Attribué"),
        .init(text: "The man who moves a mountain begins by carrying away small stones.",
              author: "Confucius", context: "Analectes"),
        .init(text: "Our greatest glory is not in never falling, but in rising every time we fall.",
              author: "Confucius", context: "Analectes"),
        .init(text: "Great things are not done by impulse, but by a series of small things brought together.",
              author: "Vincent van Gogh", context: "Lettre à Théo, 1882"),
        .init(text: "Man cannot discover new oceans unless he has the courage to lose sight of the shore.",
              author: "André Gide", context: "Les Nourritures terrestres, 1897"),
        .init(text: "It always seems impossible until it's done.",
              author: "Nelson Mandela", context: "Attribué"),
        .init(text: "Do not go where the path may lead; go instead where there is no path and leave a trail.",
              author: "Ralph Waldo Emerson", context: "Essays, 1841"),
        .init(text: "The secret of getting ahead is getting started.",
              author: "Mark Twain", context: "Attribué"),
        .init(text: "Hard work beats talent when talent fails to work hard.",
              author: "Kevin Durant", context: "Attribué"),
        .init(text: "Pain is temporary. Quitting lasts forever.",
              author: "Lance Armstrong", context: "It's Not About the Bike, 2000"),
        .init(text: "Champions keep playing until they get it right.",
              author: "Billie Jean King", context: "Attribué"),
        .init(text: "You are never really playing an opponent. You are playing yourself, your own highest standards.",
              author: "Arthur Ashe", context: "Attribué"),
        .init(text: "The more I practice, the luckier I get.",
              author: "Gary Player", context: "Attribué"),
        .init(text: "You can't put a limit on anything. The more you dream, the farther you get.",
              author: "Michael Phelps", context: "No Limits, 2008"),
        .init(text: "Gold medals aren't really made of gold. They're made of sweat, determination, and a hard-to-find alloy called guts.",
              author: "Dan Gable", context: "JO 1972"),
    ]
}
