import SwiftUI

struct HRVAnalysisCard: View {
    let analysis: HRVAnalysis

    private var zoneLabel: String {
        switch analysis.hrvZone {
        case "green":  return "OPTIMAL"
        case "orange": return "NORMAL"
        case "red":    return "FAIBLE"
        default:       return "—"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── En-tête ──────────────────────────────────────────────────────
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(analysis.zoneColor)
                Text("ANALYSE HRV PERSONNALISÉE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if analysis.streakAlert {
                    Text("⚠️ FATIGUE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                } else if let zone = analysis.hrvZone {
                    Text(zoneLabel)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(analysis.zoneColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(analysis.zoneColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // ── Métriques principales ─────────────────────────────────────────
            HStack(spacing: 16) {
                if let today = analysis.todayRmssd {
                    HRVMetricPill(label: "AUJOURD'HUI", value: String(format: "%.0f ms", today), color: analysis.zoneColor)
                }
                if let avg7 = analysis.hrv7dAvg {
                    HRVMetricPill(label: "MOY. 7J", value: String(format: "%.0f ms", avg7), color: .gray)
                }
                if let avg30 = analysis.hrv30dAvg {
                    HRVMetricPill(label: "MOY. 30J", value: String(format: "%.0f ms", avg30), color: .gray)
                }
                if let cv = analysis.hrvCv {
                    HRVMetricPill(label: "CV 30J", value: String(format: "%.0f%%", cv), color: .gray)
                }
                Spacer()
            }

            // ── Score normalisé + tendance ────────────────────────────────────
            if let score = analysis.hrvScore {
                HStack(spacing: 8) {
                    Text(String(format: "%.0f%%", score))
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(analysis.zoneColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("vs ta baseline 7j")
                            .font(.system(size: 11)).foregroundColor(.gray)
                        HStack(spacing: 4) {
                            Text(analysis.trendArrow)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(analysis.trendColor)
                            if let trend = analysis.hrvTrend {
                                Text(trend == "up" ? "en hausse" : trend == "down" ? "en baisse" : "stable")
                                    .font(.system(size: 11)).foregroundColor(.gray)
                            }
                            if analysis.consecutiveLowDays >= 2 {
                                Text("· \(analysis.consecutiveLowDays)j consécutifs")
                                    .font(.system(size: 11)).foregroundColor(.orange)
                            }
                        }
                    }
                    Spacer()
                }
            }

            // ── Sparkline 7j ─────────────────────────────────────────────────
            if analysis.history7d.count >= 2 {
                HRVSparkline(points: analysis.history7d, zoneColor: analysis.zoneColor)
                    .frame(height: 36)
            }

            // ── Message contextuel ────────────────────────────────────────────
            if let msg = analysis.contextualMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(analysis.hrvZone == "red" ? .red.opacity(0.9) : .gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("\(analysis.dataPoints7d) jours dans la baseline · \(analysis.dataPoints30d) jours au total")
                    .font(.system(size: 10)).foregroundColor(.gray.opacity(0.5))
                Spacer()
                NavigationLink(destination: HRVFAQView()) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                        Text("FAQ")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.cyan.opacity(0.8))
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

private struct HRVMetricPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
            Text(value).font(.system(size: 15, weight: .black)).foregroundColor(color)
        }
    }
}

private struct HRVSparkline: View {
    let points:    [HRVDataPoint]
    let zoneColor: Color

    var body: some View {
        let values = points.map(\.hrv)
        let minV   = values.min() ?? 0
        let maxV   = values.max() ?? 1
        let range  = maxV - minV > 0 ? maxV - minV : 1

        GeometryReader { geo in
            let w   = geo.size.width
            let h   = geo.size.height
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w

            ZStack(alignment: .leading) {
                // Baseline line (avg of all points)
                let avg = values.reduce(0, +) / Double(values.count)
                let avgY = h - CGFloat((avg - minV) / range) * h
                Path { p in
                    p.move(to: CGPoint(x: 0, y: avgY))
                    p.addLine(to: CGPoint(x: w, y: avgY))
                }
                .stroke(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                // Sparkline
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h - CGFloat((pt.hrv - minV) / range) * h
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else       { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(zoneColor, lineWidth: 2)

                // Last point dot
                if let last = points.last {
                    let x = CGFloat(points.count - 1) * step
                    let y = h - CGFloat((last.hrv - minV) / range) * h
                    Circle()
                        .fill(zoneColor)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - HRV Baseline Progress

struct HRVBaselineProgressView: View {
    let dataPoints: Int
    let target = 7

    @State private var displayProgress: Double = 0

    private var progress: Double { min(1.0, Double(dataPoints) / Double(target)) }
    private var daysLeft: Int    { max(0, target - dataPoints) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundColor(.cyan)
                Text("BASELINE EN CONSTRUCTION")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
            }

            Text("Continue — ta baseline personnelle se construit.")
                .font(.system(size: 14, weight: .medium)).foregroundColor(.white)

            Text(daysLeft > 0
                 ? "\(daysLeft) jour\(daysLeft > 1 ? "s" : "") de plus pour des insights précis."
                 : "Baseline prête dans quelques instants.")
                .font(.system(size: 13)).foregroundColor(.gray)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.cyan)
                        .frame(width: geo.size.width * displayProgress, height: 8)
                }
            }
            .frame(height: 8)

            Text("\(dataPoints) / \(target) jours de données collectés")
                .font(.system(size: 11)).foregroundColor(.gray.opacity(0.6))
        }
        .padding(14)
        .glassCard(color: .cyan, intensity: 0.05).cornerRadius(14)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { displayProgress = progress }
        }
    }
}

// MARK: - HRV Contextual Tip (one-time dismissable)

struct HRVContextualTipView: View {
    let tipId:      String
    let icon:       String
    let message:    String
    var accentColor: Color = .cyan

    @State private var dismissed = false
    private var shownKey: String { "hrv_tip_shown_\(tipId)" }

    var body: some View {
        if !dismissed && !UserDefaults.standard.bool(forKey: shownKey) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(accentColor)
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    UserDefaults.standard.set(true, forKey: shownKey)
                    withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.6))
                        .frame(width: 22, height: 22)
                }
            }
            .padding(10)
            .background(accentColor.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accentColor.opacity(0.12), lineWidth: 1))
            .cornerRadius(10)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - HRV Morning Nudge (Today page)

struct HRVMorningNudgeView: View {
    let analysis: HRVAnalysis?

    private var currentHour: Int { Calendar.current.component(.hour, from: Date()) }

    private enum MorningState { case received, missingAfter9, watchNotWorn, tooEarly }

    private var state: MorningState {
        guard let a = analysis else { return .tooEarly }
        if a.todayRmssd != nil { return .received }
        if currentHour < 9    { return .tooEarly }
        if a.dataPoints7d > 0 { return .missingAfter9 }
        return .watchNotWorn
    }

    var body: some View {
        switch state {
        case .received, .tooEarly:
            EmptyView()
        case .missingAfter9:
            HRVNudgeBanner(
                icon: "waveform.path.ecg",
                message: "Mesure HRV manquante ce matin — pense à rester allongé quelques secondes demain.",
                color: .orange
            )
        case .watchNotWorn:
            HRVNudgeBanner(
                icon: "applewatch",
                message: "Porte ton Apple Watch cette nuit pour une mesure HRV fiable.",
                color: .cyan
            )
        }
    }
}

private struct HRVNudgeBanner: View {
    let icon: String; let message: String; let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            Text(message).font(.system(size: 12)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(color.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15), lineWidth: 1))
        .cornerRadius(10)
    }
}

// MARK: - HRV FAQ Sheet

struct HRVFAQView: View {
    private let items: [(String, String)] = [
        ("Pourquoi mesurer le matin ?",
         "Le matin au réveil, ton corps est dans son état le plus stable — pas encore influencé par l'effort, la caféine ou le stress. C'est le seul moment où la mesure est comparable d'un jour à l'autre."),
        ("Pourquoi rester allongé ?",
         "Le simple fait de se lever fait monter la fréquence cardiaque et perturbe le HRV pendant plusieurs minutes. Rester allongé garantit une mesure propre et reproductible."),
        ("Ma valeur est-elle bonne ou mauvaise ?",
         "La valeur absolue ne signifie rien sans contexte. 40 ms peut être excellent pour toi, faible pour quelqu'un d'autre. Ce qui compte : ta valeur du jour vs ta propre baseline. C'est ce que VinceSeven calcule."),
        ("Pourquoi ça change chaque jour ?",
         "Le HRV réagit à tout : sommeil, alcool, stress, volume d'entraînement, alimentation. Une variation d'un jour à l'autre est normale. La tendance sur 7 jours est le signal utile."),
        ("Alcool, stress, manque de sommeil — quel impact ?",
         "Alcool : baisse significative le lendemain, même en petite quantité. Manque de sommeil : baisse proportionnelle à la dette de sommeil. Stress chronique : baisse graduelle sur 5-10 jours."),
        ("Comment lire vert / orange / rouge ?",
         "Vert (≥110% de ta baseline 7j) : récupération optimale, séance à 100%. Orange (90-109%) : dans la norme, séance normale. Rouge (<90%) : récupération incomplète, réduis le volume."),
        ("Et si je n'ai pas de mesure ce matin ?",
         "Aucun problème — l'app n'invente pas de valeur. Ton coaching reste actif basé sur les données récentes. Pas de culpabilité : une mesure manquante n'affecte pas ta baseline."),
    ]

    var body: some View {
        ZStack {
            AmbientBackground(color: .cyan)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HRVFAQItem(question: item.0, answer: item.1)
                    }
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 20)
            }
        }
        .navigationTitle("HRV — Questions fréquentes")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct HRVFAQItem: View {
    let question: String; let answer: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Text(question).font(.system(size: 14, weight: .semibold)).foregroundColor(.white).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(answer).font(.system(size: 13)).foregroundColor(.gray).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .background(Color.appCard).cornerRadius(12)
    }
}
