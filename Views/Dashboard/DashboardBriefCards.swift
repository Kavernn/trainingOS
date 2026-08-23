import SwiftUI

// MARK: - Momentum Strip (Streak + WeekProgress fusion)

struct MomentumStripView: View {
    let dash: DashboardData
    var streakData: StreakResponse? = nil
    var weeklyTonnage: Int? = nil

    private var currentStreak: Int { streakData?.currentStreak ?? 0 }
    private var bestStreak: Int    { streakData?.bestStreak ?? 0 }
    private var showStreak: Bool   { currentStreak > 3 }

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
            let dateStr = fmt.string(from: Date(timeIntervalSince1970: base - Double(i) * 86400.0))
            let counted = dash.sessions[dateStr] != nil
                || (dateStr == dash.todayDate && dash.alreadyLoggedToday)
            if counted { count += 1 }
        }
        return count
    }

    var weekTarget: Int {
        let restWords = ["repos", "rest", "off", "récupération"]
        let active = dash.schedule.values.filter { val in
            let lower = val.lowercased()
            return !lower.isEmpty && !restWords.contains(where: { lower.contains($0) })
        }.count
        return max(active, 1)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colonne gauche — semaine
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(.statusCyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(weekSessions) / \(weekTarget) séances")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.appSurfaceInset).frame(height: 4)
                            Capsule()
                                .fill(weekSessions >= weekTarget ? Color.appSuccess : Color.statusCyan)
                                .frame(width: max(4, geo.size.width * min(Double(weekSessions) / Double(weekTarget), 1.0)), height: 4)
                                .animation(.easeOut(duration: 0.5), value: weekSessions)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showStreak {
                Rectangle()
                    .fill(Color.appSurfaceInset)
                    .frame(width: 1)
                    .padding(.vertical, 10)

                // Colonne centre — streak
                VStack(alignment: .center, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("🔥")
                            .font(.appBody)
                        Text("\(currentStreak)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.forge)
                            .contentTransition(.numericText())
                        Text("j")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.gray)
                    }
                    let gap = bestStreak - currentStreak
                    Text(currentStreak >= bestStreak && bestStreak > 0
                         ? "record ✓"
                         : gap <= 5 ? "-\(gap) record" : "meilleur: \(bestStreak)")
                        .font(.appMicro)
                        .foregroundColor(currentStreak >= bestStreak ? Color.forge.opacity(0.7) : .gray.opacity(0.55))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: 100)
            }

            if let t = weeklyTonnage, t > 0 {
                // Convertit lbs (source canonique) vers l'unité d'affichage. Seuil "t"
                // uniquement en mode kg (isKg) : évite l'unité "klbs" sémantiquement
                // absurde en mode lbs.
                let displayed  = UnitSettings.shared.display(Double(t))
                let showTonnes = UnitSettings.shared.isKg && displayed >= 1000
                let rounded    = Int(displayed.rounded())
                let valueStr   = showTonnes
                    ? (rounded % 1000 == 0 ? "\(rounded / 1000)" : String(format: "%.1f", displayed / 1000))
                    : "\(rounded)"
                let unitStr    = showTonnes ? "t" : UnitSettings.shared.label

                Rectangle()
                    .fill(Color.appSurfaceInset)
                    .frame(width: 1)
                    .padding(.vertical, 10)

                // Colonne droite — volume
                VStack(alignment: .center, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(valueStr)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.statusCyan)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                        Text(unitStr)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.gray)
                    }
                    Text("volume sem.")
                        .font(.appMicro)
                        .foregroundColor(.gray.opacity(0.55))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: 90)
            }
        }
        .glassCard(color: .statusCyan, intensity: 0.04)
        .cornerRadius(14)
    }
}

// MARK: - Lesson of Day Card
//
// Registre calme : carte compacte sous CoachInsight, au-dessus de DayActionsRow.
// 2 états : capsule disponible (tap → sheet) | épuisé (message, pas de tap).
// Carte absente si pas de données (fetch vide/échec).

struct LessonOfDayCard: View {
    let capsule: EducationalCapsule?
    let exhausted: Bool
    let onTap: () -> Void

    private var previewLine: String? {
        guard let capsule = capsule else { return nil }
        return capsule.body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first {
                !$0.isEmpty
                && !$0.hasPrefix("#")
                && !$0.hasPrefix("-")
                && !$0.hasPrefix("*")
            }
    }

    var body: some View {
        if let capsule = capsule {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(.appCaption)
                            .foregroundColor(.statusPurple.opacity(0.8))
                        Text("LEÇON DU JOUR")
                            .font(.appCaption).fontWeight(.semibold)
                            .foregroundColor(.statusPurple.opacity(0.8))
                            .tracking(0.8)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.appCaption)
                            .foregroundColor(Color(white: 0.45))
                    }
                    Text(capsule.title)
                        .font(.appHeadline)
                        .foregroundColor(.appTextPrimary)
                        .multilineTextAlignment(.leading)
                    if let preview = previewLine {
                        Text(preview)
                            .font(.appBody)
                            .foregroundColor(Color(white: 0.55))
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 14)
            }
            .buttonStyle(ScaleButtonStyle())
        } else if exhausted {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed")
                        .font(.appCaption)
                        .foregroundColor(.gray.opacity(0.5))
                    Text("LEÇON DU JOUR")
                        .font(.appCaption).fontWeight(.semibold)
                        .foregroundColor(.gray.opacity(0.5))
                        .tracking(0.8)
                }
                Text("Tu as tout parcouru — il est temps d'ajouter des capsules.")
                    .font(.appBody)
                    .foregroundColor(Color(white: 0.55))
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 14)
            .opacity(0.6)
        }
    }
}
