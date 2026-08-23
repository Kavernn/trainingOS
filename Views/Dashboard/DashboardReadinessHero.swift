import SwiftUI

// Hero readiness — source unique /api/readiness (ReadinessResponse).
// Le brief.recommendation N'ENTRE PAS ici : verdict de récup lu depuis
// readiness.verdict / verdictLabel / score / why. nil = "—" gris, jamais
// de fallback vert. Accent : couleur verdict sur pill/icône/score ;
// frame glassCard sur todayAccent (sessionTypeColor du jour).

struct DashboardReadinessHero: View {
    let readiness: ReadinessResponse?
    var hrvAnalysis: HRVAnalysis? = nil
    let recovery: RecoveryEntry?
    let todayAccent: Color

    private var verdictColor: Color {
        switch readiness?.verdict {
        case "go":       return .statusGreen
        case "moderate": return .statusYellow
        case "rest":     return .statusOrange
        default:         return .gray
        }
    }

    private var verdictIcon: String {
        switch readiness?.verdict {
        case "go":       return "bolt.circle.fill"
        case "moderate": return "exclamationmark.circle.fill"
        case "rest":     return "arrow.down.circle.fill"
        default:         return "questionmark.circle"
        }
    }

    private var subtitle: String {
        readiness?.why ?? "Readiness indisponible"
    }

    private var hrvValue: String {
        guard let ms = recovery?.hrv else { return "–" }
        let arrow = hrvAnalysis?.trendArrow ?? ""
        return "\(Int(ms))\(arrow)"
    }

    private var hrvColor: Color {
        guard recovery?.hrv != nil else { return .gray }
        return hrvAnalysis?.zoneColor ?? .statusGreen
    }

    private var sleepValue: String {
        recovery?.sleepHours.map { String(format: "%.1fh", $0) } ?? "–"
    }

    private var sleepQualitative: String {
        guard let h = recovery?.sleepHours else { return "Sommeil" }
        if h >= 7.5 { return "Récupérateur" }
        if h >= 6.0 { return "Correct" }
        return "Insuffisant"
    }

    private var sleepColor: Color {
        recovery?.sleepHours != nil ? .statusBlue : .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Text(subtitle)
                .font(.appBody)
                .foregroundColor(Color.appOnSurface.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Divider()
                .background(Color.appSeparator)
                .padding(.vertical, 2)
            statsRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(color: todayAccent, cornerRadius: 16)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: verdictIcon)
                .font(.appTitle)
                .foregroundColor(verdictColor)

            if let r = readiness {
                Text(r.verdictLabel)
                    .font(.appTitle.weight(.bold))
                    .foregroundColor(verdictColor)
                Text("·")
                    .font(.appTitle)
                    .foregroundColor(.gray.opacity(0.5))
                Text("\(r.score)")
                    .font(.appHero)
                    .foregroundColor(verdictColor)
            } else {
                Text("—")
                    .font(.appTitle.weight(.bold))
                    .foregroundColor(.gray)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.appCaption.weight(.semibold))
                .foregroundColor(Color.appOnSurface.opacity(0.35))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(icon: "waveform.path.ecg",
                     value: hrvValue,
                     label: recovery?.hrv != nil ? "HRV ms" : "HRV",
                     color: hrvColor)
            Rectangle()
                .fill(Color.appSeparator)
                .frame(width: 1)
                .padding(.vertical, 4)
            statCell(icon: "moon.zzz.fill",
                     value: sleepValue,
                     label: sleepQualitative,
                     color: sleepColor)
        }
    }

    private func statCell(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.appCaption)
                    .foregroundColor(color)
                Text(value)
                    .font(.appHeadline.weight(.semibold))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.appMicro)
                .foregroundColor(Color.appOnSurface.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - Preview fixtures (debug-only, jamais compilé en release)

#if DEBUG
private extension ReadinessResponse {
    static func previewFixture(verdict: String, score: Int, why: String) -> ReadinessResponse {
        let m = ReadinessModule(score: 75, label: "OK", detail: "—")
        let modules = ReadinessModules(
            hrv: m, rhr: m, acwr: m,
            sleepQuality: m, sleepDuration: m,
            subjective: m, muscleRec: m,
            nutrition: m, pattern: m
        )
        return ReadinessResponse(
            score: score, verdict: verdict, why: why,
            adjustment: nil, progressionModifier: 1.0,
            modules: modules, muscleRecovery: [:], todaySession: "Push",
            hrvStatus: nil, verdictMethod: "relative", downgradeReason: nil
        )
    }
}

private extension RecoveryEntry {
    static var previewFixture: RecoveryEntry {
        RecoveryEntry(
            date: "2026-08-23", sleepHours: 7.2, sleepQuality: 8,
            restingHr: 55, hrv: 67, steps: 8500, soreness: 3,
            fatigue: 3, activeEnergy: 450, hrMorning: 58,
            hrPostWorkout: nil, hrEvening: 62, energyPre: 7,
            source: "healthkit", notes: nil, bedtime: "23:15", wakeTime: "06:30"
        )
    }
}
#endif

#Preview("Prêt") {
    DashboardReadinessHero(
        readiness: .previewFixture(verdict: "go", score: 82,
                                    why: "HRV solide, sommeil correct, ACWR dans la zone verte."),
        hrvAnalysis: nil,
        recovery: .previewFixture,
        todayAccent: .blue
    )
    .padding()
    .background(Color.black)
}

#Preview("Modéré") {
    DashboardReadinessHero(
        readiness: .previewFixture(verdict: "moderate", score: 67,
                                    why: "HRV en baisse — garde ta séance dans le raisonnable."),
        hrvAnalysis: nil,
        recovery: .previewFixture,
        todayAccent: .orange
    )
    .padding()
    .background(Color.black)
}

#Preview("Repos") {
    DashboardReadinessHero(
        readiness: .previewFixture(verdict: "rest", score: 32,
                                    why: "Fatigue accumulée — repos actif recommandé."),
        hrvAnalysis: nil,
        recovery: .previewFixture,
        todayAccent: .gray
    )
    .padding()
    .background(Color.black)
}

#Preview("Nil") {
    DashboardReadinessHero(
        readiness: nil,
        hrvAnalysis: nil,
        recovery: nil,
        todayAccent: .blue
    )
    .padding()
    .background(Color.black)
}
