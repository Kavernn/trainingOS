import SwiftUI

// Hero State — salutation + ring readiness (verdictAccent) + HRV + sommeil +
// streak relogé + phrase de synthèse (readiness.why). Remplace l'ancien
// DashboardReadinessHero. Source unique par domaine, états vides honnêtes.

struct DashboardHeroState: View {
    let readiness: ReadinessResponse?
    let hrvAnalysis: HRVAnalysis?
    let recovery: RecoveryEntry?
    let streak: Int
    let userName: String?

    // MARK: Salutation
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base = hour < 18 ? "Bonjour" : "Bonsoir"
        if let name = userName, !name.isEmpty {
            return "\(base) \(name)"
        }
        return base
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
        return "\(sign)\(abs(delta))% vs baseline"
    }

    // MARK: Sommeil bloc
    private var sleepValue: String {
        guard let h = recovery?.sleepHours else { return "—" }
        return String(format: "%.1f h", h)
    }
    private var sleepLabel: String { recovery?.sleepQualityLabel ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(greeting)
                .font(.appTitle.weight(.bold))
                .foregroundColor(.appTextPrimary)

            HStack(spacing: 16) {
                ProgressRing(progress: ringProgress, color: ringColor, size: 96, lineWidth: 10) {
                    VStack(spacing: 0) {
                        if let score = readiness?.score {
                            Text("\(score)")
                                .font(.appHero)
                                .foregroundColor(.appTextPrimary)
                            Text("/100")
                                .font(.appMicro)
                                .foregroundColor(.appTextTertiary)
                        } else {
                            Text("—")
                                .font(.appHero)
                                .foregroundColor(.appTextTertiary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(readiness?.verdictLabel ?? "—")
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(ringColor)
                    if streak > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                            Text("\(streak) jours")
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                statCell(icon: "waveform.path.ecg",
                         value: hrvValue,
                         label: hrvDeltaLabel)
                Rectangle()
                    .fill(Color.appSeparator)
                    .frame(width: 1)
                    .padding(.vertical, 4)
                statCell(icon: "moon.zzz.fill",
                         value: sleepValue,
                         label: sleepLabel)
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
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: .appCardRadius)
                .stroke(Color.appSeparator, lineWidth: .appHairline)
        )
        .cornerRadius(.appCardRadius)
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.appCaption)
                    .foregroundColor(.appTextSecondary)
                Text(value)
                    .font(.appHeadline.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
            }
            Text(label)
                .font(.appMicro)
                .foregroundColor(.appTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
