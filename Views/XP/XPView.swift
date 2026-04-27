import SwiftUI

// MARK: - Badge Model

struct Badge: Identifiable {
    let id: String
    let icon: String
    let label: String
    let desc: String
    let color: Color
    let unlocked: Bool
    let progress: Double?    // 0.0–1.0, nil if not quantifiable
    let progressLabel: String?
    let category: Category

    enum Category: String, CaseIterable {
        case volume     = "Volume"
        case force      = "Force"
        case regularite = "Régularité"
        case style      = "Style"
        case special    = "Spécial"
    }
}

// MARK: - XP View

struct XPView: View {
    @StateObject private var api = APIService.shared
    @State private var hiitLog:   [HIITEntry]        = []
    @State private var weights:   [String: WeightData] = [:]
    @State private var recovery:  [RecoveryEntry]    = []
    @State private var isLoading = true
    @State private var selectedBadge: Badge? = nil

    // MARK: Computed stats

    private var sessions: [String: SessionEntry] { api.dashboard?.sessions ?? [:] }
    private var totalSessions: Int { sessions.count + hiitLog.count }
    private var totalExercices: Int { weights.filter { $0.value.history?.isEmpty == false }.count }
    private var profileWeight: Double? { api.dashboard?.profile.weight }

    var xp: Int { totalSessions * 100 + totalExercices * 50 + hiitLog.count * 75 }
    var level: Int { max(1, xp / 1500 + 1) }
    var xpInLevel: Int { xp % 1500 }
    var xpToNextLevel: Int { 1500 }

    private var unlockedCount: Int { allBadges.filter { $0.unlocked }.count }

    var levelTitle: String {
        switch level {
        case 1:    return "Débutant"
        case 2:    return "Athlète"
        case 3:    return "Warrior"
        case 4:    return "Élite"
        case 5:    return "Champion"
        case 6...: return "Légende"
        default:   return "Débutant"
        }
    }

    // MARK: - Badge factory

    var allBadges: [Badge] {
        var badges: [Badge] = []
        let goals = api.dashboard?.goals ?? [:]

        // ── Volume ──────────────────────────────────────────────
        let sc = totalSessions
        badges += [
            badge("volume.1",    "figure.walk",               "Premier pas",     "Ta toute première séance.",            .orange,  sc >= 1,   sc, 1),
            badge("volume.10",   "flame.fill",                "10 séances",       "10 séances au compteur.",              .red,     sc >= 10,  sc, 10),
            badge("volume.25",   "star.fill",                 "25 séances",       "Régularité installée.",                .yellow,  sc >= 25,  sc, 25),
            badge("volume.50",   "chart.line.uptrend.xyaxis", "50 séances",       "La moitié du centenaire.",             .purple,  sc >= 50,  sc, 50),
            badge("volume.100",  "crown.fill",                "Centurion",        "100 séances — engagement total.",      .yellow,  sc >= 100, sc, 100),
            badge("volume.200",  "trophy.fill",               "Légende 200",      "200 séances. Tu es une machine.",      .orange,  sc >= 200, sc, 200),
        ]

        // ── Force ────────────────────────────────────────────────
        let maxLift     = weights.values.compactMap { $0.currentWeight }.max() ?? 0
        let liftCount   = totalExercices
        let bwRatio     = profileWeight.map { maxLift / $0 } ?? 0

        badges += [
            badge("force.first", "dumbbell.fill",             "Premier lift",     "Ton premier exercice logué.",          .orange,  liftCount >= 1,    liftCount, 1),
            badge("force.5exos", "figure.strengthtraining.traditional", "5 exercices", "5 exercices différents maîtrisés.", .blue, liftCount >= 5, liftCount, 5),
            badge("force.15exo", "figure.cross.training",     "Polyvalent",       "15 exercices différents maîtrisés.",   .cyan,    liftCount >= 15,   liftCount, 15),
        ]

        // Charge maximale vs poids de corps
        if bwRatio >= 1.5 {
            badges.append(Badge(id: "force.bw1.5", icon: "scalemass.fill", label: "1.5× poids corps",
                                desc: "Charge max = \(String(format: "%.0f", maxLift)) lbs, soit 1.5× ton poids.",
                                color: .indigo, unlocked: true, progress: nil, progressLabel: nil, category: .force))
        } else if bwRatio > 0 {
            badges.append(Badge(id: "force.bw1.5", icon: "scalemass.fill", label: "1.5× poids corps",
                                desc: "Charge max = \(String(format: "%.0f", maxLift)) lbs. Objectif : \(String(format: "%.0f", (profileWeight ?? 0) * 1.5)) lbs.",
                                color: .indigo, unlocked: false,
                                progress: min(1.0, bwRatio / 1.5),
                                progressLabel: "\(Int(bwRatio * 100))%", category: .force))
        }

        // Exercice maîtrisé (≥ 20 sessions)
        let masteredCount = weights.values.filter { ($0.history?.count ?? 0) >= 20 }.count
        badges.append(badge("force.master", "medal.fill", "Maîtrise", "\(masteredCount) exercice(s) avec 20+ sessions.", .yellow, masteredCount >= 1, masteredCount, 1))

        // ── Régularité ────────────────────────────────────────────
        let hiitCount = hiitLog.count
        badges += [
            badge("reg.hiit1",  "bolt.fill",                 "Premier HIIT",     "Ta première séance HIIT.",             .red,    hiitCount >= 1,  hiitCount, 1),
            badge("reg.hiit10", "bolt.circle.fill",          "10 HIIT",          "10 HIIT complétés.",                   .orange, hiitCount >= 10, hiitCount, 10),
            badge("reg.hiit25", "figure.run.circle.fill",    "25 HIIT",          "Machine cardio.",                      .red,    hiitCount >= 25, hiitCount, 25),
        ]

        // Semaine parfaite (≥ 4 séances dans une même semaine ISO)
        let perfectWeek = hasPerfectWeek(sessions: sessions)
        badges.append(Badge(id: "reg.perfect", icon: "calendar.badge.checkmark",
                            label: "Semaine parfaite", desc: "4+ séances dans une même semaine.",
                            color: .green, unlocked: perfectWeek, progress: nil, progressLabel: nil, category: .regularite))

        // ── Style ─────────────────────────────────────────────────
        let recentSessions = Array(sessions.sorted { $0.key > $1.key }.prefix(8).map { $0.value })
        let avgRPE       = recentSessions.compactMap { $0.rpe }.average
        let avgDur       = recentSessions.compactMap { $0.durationMin }.average

        if let rpe = avgRPE {
            badges.append(Badge(id: "style.smart", icon: "brain.head.profile",
                                label: "Entraîneur intelligent", desc: "RPE moyen ≤ 7 sur 8 séances récentes — effort mesuré.",
                                color: .cyan, unlocked: rpe <= 7.0, progress: nil, progressLabel: "RPE \(String(format: "%.1f", rpe))", category: .style))
            badges.append(Badge(id: "style.beast", icon: "flame.circle.fill",
                                label: "Beast mode", desc: "RPE moyen ≥ 8.5 sur 8 séances récentes — tu pousses à fond.",
                                color: .red, unlocked: rpe >= 8.5, progress: nil, progressLabel: "RPE \(String(format: "%.1f", rpe))", category: .style))
        }

        if let dur = avgDur {
            badges.append(Badge(id: "style.iron", icon: "clock.badge.fill",
                                label: "Iron session", desc: "Séances longues et denses (moy. > 90 min).",
                                color: .indigo, unlocked: dur > 90, progress: nil, progressLabel: "\(Int(dur))min moy.", category: .style))
            badges.append(Badge(id: "style.efficient", icon: "bolt.badge.checkmark.fill",
                                label: "Efficace", desc: "Résultats en < 55 min (moy. séances).",
                                color: .teal, unlocked: dur < 55 && avgRPE.map { $0 >= 7 } ?? false,
                                progress: nil, progressLabel: "\(Int(dur))min moy.", category: .style))
        }

        // Récupération : sommeil moyen ≥ 8h
        let avgSleep = recovery.compactMap { $0.sleepHours }.average
        if let sl = avgSleep {
            badges.append(Badge(id: "style.sleep", icon: "moon.stars.fill",
                                label: "Dormeur d'or", desc: "Sommeil moyen ≥ 8h.",
                                color: .blue, unlocked: sl >= 8.0,
                                progress: min(1.0, sl / 8.0),
                                progressLabel: "\(String(format: "%.1f", sl))h moy.", category: .style))
        }

        // ── Spécial ───────────────────────────────────────────────
        let achievedGoals = goals.filter { $0.value.achieved }.count
        if achievedGoals > 0 {
            badges.append(Badge(id: "special.goal1", icon: "checkmark.seal.fill",
                                label: "Objectif atteint", desc: "\(achievedGoals) objectif(s) accompli(s).",
                                color: .green, unlocked: true, progress: nil, progressLabel: nil, category: .special))
        }

        badges.append(Badge(id: "special.lvl5", icon: "star.circle.fill",
                            label: "Niveau 5", desc: "Atteindre le niveau 5.",
                            color: .yellow, unlocked: level >= 5,
                            progress: min(1.0, Double(level) / 5.0),
                            progressLabel: "Niv. \(level)/5", category: .special))

        return badges
    }

    // MARK: - View

    var body: some View {
        ZStack {
            AmbientBackground(color: .yellow)
            if isLoading {
                AppLoadingView()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        levelCard
                        statsRow
                        badgesSection
                    }
                    .padding(.top, 16)
                    .padding(.bottom, contentBottomPadding)
                }
            }
        }
        .navigationTitle("XP & Niveau")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadData() }
        .sheet(item: $selectedBadge) { b in
            BadgeDetailSheet(badge: b)
        }
    }

    // MARK: - Subviews

    private var levelCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 100, height: 100)
                VStack(spacing: 2) {
                    Text("LVL")
                        .font(.system(size: 10, weight: .bold)).tracking(2)
                        .foregroundColor(.orange)
                    Text("\(level)")
                        .font(.system(size: 44, weight: .black))
                        .foregroundColor(.orange)
                }
            }

            Text(levelTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 6) {
                HStack {
                    Text("\(xp) XP total")
                        .font(.system(size: 12)).foregroundColor(.gray)
                    Spacer()
                    Text("\(xpInLevel) / \(xpToNextLevel) XP")
                        .font(.system(size: 12)).foregroundColor(.orange)
                }
                Capsule()
                    .fill(Color(hex: "191926"))
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * Double(xpInLevel) / Double(xpToNextLevel))
                        }
                    }
            }
            .padding(.horizontal, 8)

            HStack(spacing: 4) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 10)).foregroundColor(.orange.opacity(0.7))
                Text("\(unlockedCount)/\(allBadges.count) badges débloqués")
                    .font(.system(size: 11)).foregroundColor(.gray)
            }
        }
        .padding(20)
        .glassCardAccent(.orange)
        .cornerRadius(20)
        .padding(.horizontal, 16)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            KPICard(value: "\(totalSessions)", label: "Séances", color: .orange)
            KPICard(value: "\(hiitLog.count)", label: "HIIT", color: .red)
            KPICard(value: "\(totalExercices)", label: "Exercices", color: .blue)
        }
        .padding(.horizontal, 16)
    }

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Badge.Category.allCases, id: \.self) { cat in
                let catBadges = allBadges.filter { $0.category == cat }
                if !catBadges.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Text(cat.rawValue.uppercased())
                                .font(.system(size: 10, weight: .bold)).tracking(2)
                                .foregroundColor(.gray)
                            Spacer()
                            let unlocked = catBadges.filter { $0.unlocked }.count
                            Text("\(unlocked)/\(catBadges.count)")
                                .font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
                        }
                        .padding(.horizontal, 16)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                            ForEach(catBadges) { b in
                                BadgeCell(badge: b)
                                    .onTapGesture { selectedBadge = b }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func badge(_ id: String, _ icon: String, _ label: String, _ desc: String,
                       _ color: Color, _ unlocked: Bool, _ current: Int, _ target: Int) -> Badge {
        let ratio = min(1.0, Double(current) / Double(target))
        let pLabel = unlocked ? nil : "\(current)/\(target)"
        return Badge(id: id, icon: icon, label: label, desc: desc, color: color,
                     unlocked: unlocked, progress: unlocked ? nil : ratio,
                     progressLabel: pLabel, category: categoryFor(id))
    }

    private func categoryFor(_ id: String) -> Badge.Category {
        if id.hasPrefix("volume")  { return .volume }
        if id.hasPrefix("force")   { return .force }
        if id.hasPrefix("reg")     { return .regularite }
        if id.hasPrefix("style")   { return .style }
        return .special
    }

    private func hasPerfectWeek(sessions: [String: SessionEntry]) -> Bool {
        var weekCounts: [String: Int] = [:]
        let cal = Calendar.current
        for dateStr in sessions.keys {
            guard let date = DateFormatter.isoDate.date(from: dateStr) else { continue }
            let y = cal.component(.yearForWeekOfYear, from: date)
            let w = cal.component(.weekOfYear, from: date)
            let key = "\(y)-W\(w)"
            weekCounts[key, default: 0] += 1
        }
        return weekCounts.values.contains { $0 >= 4 }
    }

    private func loadData() async {
        isLoading = true
        if api.dashboard == nil { await api.fetchDashboard() }
        async let h = try? APIService.shared.fetchHIITData()
        async let w = try? APIService.shared.fetchWeights()
        async let r = try? APIService.shared.fetchRecoveryData()
        let (hh, ww, rr) = await (h, w, r)
        hiitLog  = hh ?? []
        weights  = ww ?? [:]
        recovery = rr ?? []
        isLoading = false
    }
}

// MARK: - Badge Cell

struct BadgeCell: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(badge.unlocked ? badge.color.opacity(0.15) : Color(hex: "191926"))
                    .frame(width: 52, height: 52)

                if !badge.unlocked, let p = badge.progress {
                    Circle()
                        .trim(from: 0, to: p)
                        .stroke(badge.color.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                }

                Image(systemName: badge.icon)
                    .font(.system(size: 20))
                    .foregroundColor(badge.unlocked ? badge.color : .gray.opacity(0.3))
            }

            Text(badge.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(badge.unlocked ? .white : .gray.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !badge.unlocked, let pl = badge.progressLabel {
                Text(pl)
                    .font(.system(size: 8))
                    .foregroundColor(.gray.opacity(0.5))
            }
        }
        .scaleEffect(badge.unlocked ? 1.0 : 0.88)
        .opacity(badge.unlocked ? 1.0 : 0.5)
    }
}

// MARK: - Badge Detail Sheet

struct BadgeDetailSheet: View {
    let badge: Badge
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            ZStack {
                Circle()
                    .fill(badge.unlocked ? badge.color.opacity(0.15) : Color(hex: "191926"))
                    .frame(width: 90, height: 90)
                if !badge.unlocked, let p = badge.progress {
                    Circle()
                        .trim(from: 0, to: p)
                        .stroke(badge.color.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: badge.icon)
                    .font(.system(size: 38))
                    .foregroundColor(badge.unlocked ? badge.color : .gray.opacity(0.35))
            }

            VStack(spacing: 8) {
                Text(badge.label)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text(badge.desc)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if badge.unlocked {
                Label("Badge débloqué", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            } else if let pl = badge.progressLabel {
                Label(pl, systemImage: "hourglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "0D0D14").ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Array average helper

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
