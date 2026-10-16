import SwiftUI

// MARK: - Momentum Strip (Weekly streak + weekly progress fusion)

struct MomentumStripView: View {
    let dash: DashboardData
    var streakData: StreakResponse? = nil
    var weeklyTonnage: Int? = nil

    private var daysActive:  Int    { streakData?.currentWeek.daysActive ?? 0 }
    private var daysTarget:  Int    { streakData?.weeklyTarget ?? 0 }
    private var weeksStreak: Int    { streakData?.weeklyStreakCurrent ?? 0 }
    private var weeksBest:   Int    { streakData?.weeklyStreakBest ?? 0 }
    private var showStreak:  Bool   { weeksStreak > 0 }

    var body: some View {
        HStack(spacing: 0) {
            // Colonne gauche — progression semaine en jours actifs.
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(.statusCyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text(daysTarget > 0
                         ? "\(daysActive) / \(daysTarget) jours"
                         : "\(daysActive) jours")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.appSurfaceInset).frame(height: 4)
                            if daysTarget > 0 {
                                let pct = min(Double(daysActive) / Double(daysTarget), 1.0)
                                Capsule()
                                    .fill(daysActive >= daysTarget ? Color.appSuccess : Color.statusCyan)
                                    .frame(width: max(4, geo.size.width * pct), height: 4)
                                    .animation(.easeOut(duration: 0.5), value: daysActive)
                            }
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

                // Colonne centre — streak hebdo.
                VStack(alignment: .center, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("🔥").font(.appBody)
                        Text("\(weeksStreak)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.forge)
                            .contentTransition(.numericText())
                        Text("sem.")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.gray)
                    }
                    let gap = weeksBest - weeksStreak
                    Text(weeksStreak >= weeksBest && weeksBest > 0
                         ? "record ✓"
                         : gap <= 3 ? "-\(gap) record" : "meilleur: \(weeksBest)")
                        .font(.appMicro)
                        .foregroundColor(weeksStreak >= weeksBest ? Color.forge.opacity(0.7) : .gray.opacity(0.55))
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
// Registre calme : carte compacte dans le cluster secondaire du dashboard.
// 3 états : capsule disponible (tap → sheet) | vérification impossible
// (tap → retry) | épuisé (message, pas de tap). Carte absente si pas de
// données (fetch initial vide/échec).

struct LessonOfDayCard: View {
    let capsule: EducationalCapsule?
    let exhausted: Bool
    let refreshFailed: Bool
    let onTap: () -> Void
    let onRetry: () -> Void

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
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.appLabel)
                            .foregroundColor(Color.statusPurple)
                        Text("LEÇON DU JOUR")
                            .font(.appMicro.weight(.black))
                            .foregroundColor(Color.statusPurple)
                            .tracking(1.4)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.appCaption)
                            .foregroundColor(Color.appTextMuted)
                    }
                    Text(capsule.title)
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(Color.appOnSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let preview = previewLine {
                        Text(preview)
                            .font(.appLabel)
                            .foregroundColor(Color.appTextSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                .background(Color.statusPurple.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.statusPurple.opacity(0.16), lineWidth: 1)
                )
                .glassCard(cornerRadius: 14)
            }
            .buttonStyle(ScaleButtonStyle())
        } else if refreshFailed {
            Button(action: onRetry) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.appLabel)
                            .foregroundColor(Color.appTextMuted)
                        Text("LEÇON DU JOUR")
                            .font(.appMicro.weight(.black))
                            .foregroundColor(Color.appTextMuted)
                            .tracking(1.4)
                    }
                    Text("Vérification du pool impossible — tape pour réessayer.")
                        .font(.appLabel)
                        .foregroundColor(Color.appTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                .glassCard(cornerRadius: 14)
                .opacity(0.75)
            }
            .buttonStyle(ScaleButtonStyle())
        } else if exhausted {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed")
                        .font(.appLabel)
                        .foregroundColor(Color.appTextMuted)
                    Text("LEÇON DU JOUR")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(Color.appTextMuted)
                        .tracking(1.4)
                }
                Text("Tu as tout parcouru — il est temps d'ajouter des capsules.")
                    .font(.appLabel)
                    .foregroundColor(Color.appTextSecondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .glassCard(cornerRadius: 14)
            .opacity(0.6)
        }
    }
}
