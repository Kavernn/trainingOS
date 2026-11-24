import SwiftUI
import UIKit

// Hero State — salutation + ring readiness (verdictAccent) + HRV + sommeil +
// streak relogé + phrase de synthèse (readiness.why). Remplace l'ancien
// DashboardReadinessHero. Source unique par domaine, états vides honnêtes.

struct DashboardHeroState: View {
    @AppStorage(HeroMoodPreference.storageKey) private var heroMoodRawValue = HeroMoodPreference.currentRawValue

    let readiness: ReadinessResponse?
    let hrvAnalysis: HRVAnalysis?
    let recovery: RecoveryEntry?
    let weeklyStreak: Int
    let userName: String?
    var onRingTap: () -> Void = {}
    var onCheckIn: () -> Void = {}

    /// Readiness reçue mais sans score (aucun signal du jour) → invitation au check-in.
    static func needsCheckIn(_ readiness: ReadinessResponse?) -> Bool {
        readiness != nil && readiness?.score == nil
    }

    // MARK: Salutation
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base = hour < 18 ? "Bonjour" : "Bonsoir"
        if let name = userName, !name.isEmpty {
            return "\(base) \(name)"
        }
        return base
    }

    /// Thème monochrome (Sin City) : anneau gris assumé, verdict en couleur principale.
    static var isSurgicalTheme: Bool {
        let theme = AppTheme.shared.selectedTheme
        return theme != .arctic && theme.colors.accentDistribution == .surgical
    }

    // MARK: Ring readiness
    private var ringProgress: Double {
        guard let s = readiness?.score else { return 0 }
        return Double(s) / 100.0
    }
    private var ringColor: Color { Color.verdictAccent(readiness?.verdict) }

    // MARK: HRV bloc
    private var hrvValue: String {
        guard let ms = hrvAnalysis?.todayRmssd else { return "—" }
        return "HRV \(Int(ms)) ms"
    }
    private var hrvDeltaLabel: String {
        guard let score = hrvAnalysis?.hrvScore else { return "—" }
        let delta = Int(score - 100)
        let sign = delta >= 0 ? "+" : "-"
        return "\(sign)\(abs(delta))% vs ta moyenne 7 j"
    }

    // MARK: Sommeil bloc
    private var sleepValue: String {
        guard let h = recovery?.sleepHours else { return "—" }
        return String(format: "%.1f h", h)
    }

    private var moodImage: UIImage? {
        let normalizedRawValue = HeroMoodPreference.normalizedRawValue(heroMoodRawValue)
        guard let mood = HeroMood(rawValue: normalizedRawValue) else { return nil }
        return UIImage(named: mood.assetName)
    }

    var body: some View {
        let hasPhoto = moodImage != nil
        return VStack(alignment: .leading, spacing: 10) {
            // Haut : photo libre, salutation posée dessus (ombre légère pour le contraste).
            Text(greeting)
                .font(.appTitle.weight(.bold))
                .foregroundColor(.appTextPrimary)
                .shadow(color: hasPhoto ? Color.appCard.opacity(0.7) : .clear, radius: 6)
            if hasPhoto { Spacer(minLength: 56) }

            // Bande compacte, dimensionnée au contenu, sur le dégradé bas.
            HStack(spacing: 12) {
                Button(action: onRingTap) {
                    ProgressRing(progress: ringProgress, color: ringColor, size: 64, lineWidth: 7,
                                 backgroundColor: Color.appTextPrimary.opacity(0.35)) {
                        Text(readiness?.score.map(String.init) ?? "—")
                            .font(.appHeadline.weight(.bold))
                            .foregroundColor(readiness?.score == nil ? .appTextSecondary : .appTextPrimary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(readiness == nil)
                .accessibilityLabel(readiness?.score.map { "Readiness \($0) sur 100, détails" } ?? "Readiness indisponible, détails")
                VStack(alignment: .leading, spacing: 2) {
                    Text(readiness?.verdictLabel ?? "—")
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(readiness?.verdict == nil ? .appTextSecondary
                                         : (Self.isSurgicalTheme ? .appTextPrimary : ringColor))
                    if weeklyStreak > 0 {
                        Label(weeklyStreak == 1 ? "1 semaine" : "\(weeklyStreak) semaines", systemImage: "flame.fill")
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 16) {
                statCell(icon: "waveform.path.ecg", value: hrvValue, label: hrvDeltaLabel)
                // Durée seule : le jugement sur le sommeil vient de la phrase serveur (une seule règle).
                statCell(icon: "moon.zzz.fill", value: sleepValue, label: nil)
                Spacer(minLength: 0)
            }

            if Self.needsCheckIn(readiness) {
                PrimaryButton(title: "Fais ton check-in", icon: "checkmark.circle", size: .medium, action: onCheckIn)
            }

            if let why = readiness?.why, !why.isEmpty {
                Text(why)
                    .font(.appBody)
                    .foregroundColor(.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if let moodImage {
                GeometryReader { geometry in
                    ZStack {
                        Color.appCard
                        Image(uiImage: moodImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                        // Haut (~20 %) : carte → transparent, pour le titre sur une photo chargée.
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.appCard.opacity(0.75), location: 0.00),
                                .init(color: Color.appCard.opacity(0.0), location: 0.20)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        // Bas (~45 %) : transparent → carte du thème.
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.appCard.opacity(0.0), location: 0.40),
                                .init(color: Color.appCard.opacity(0.88), location: 0.62),
                                .init(color: Color.appCard.opacity(0.96), location: 1.00)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else {
                Color.appCard
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: .appCardRadius)
                .stroke(Color.appSeparator, lineWidth: .appHairline)
        )
        .cornerRadius(.appCardRadius)
    }

    /// Une ligne : icône + valeur + libellé (≥ appCaption sur la photo).
    private func statCell(icon: String, value: String, label: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)
            Text(value)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(.appTextPrimary)
            if let label {
                Text(label)
                    .font(.appCaption)
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }
        }
    }
}
