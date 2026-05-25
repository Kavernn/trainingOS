import SwiftUI

// MARK: - Baseline Progress (visible jusqu'à 7 jours de données)

struct HRVBaselineProgressView: View {
    let dataPoints: Int
    let target = 7

    private var progress: Double { min(1.0, Double(dataPoints) / Double(target)) }
    private var daysLeft: Int    { max(0, target - dataPoints) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.cyan)
                Text("BASELINE EN CONSTRUCTION")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
            }

            Text("Continue — ta baseline personnelle se construit.")
                .font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            Text(daysLeft > 0
                 ? "\(daysLeft) jour\(daysLeft > 1 ? "s" : "") de plus pour des insights précis."
                 : "Baseline prête dans quelques instants.")
                .font(.system(size: 13)).foregroundColor(.gray)

            // Barre de progression
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.cyan)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.easeOut(duration: 0.6), value: progress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(dataPoints) / \(target) jours collectés")
                    .font(.system(size: 11)).foregroundColor(.gray.opacity(0.7))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.cyan)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Contextual Tips (affichés une seule fois par scenario)

struct HRVContextualTipView: View {
    let tipId:   String
    let icon:    String
    let message: String

    @State private var dismissed = false

    private var shownKey: String { "hrv_tip_shown_\(tipId)" }

    var body: some View {
        if !dismissed && !UserDefaults.standard.bool(forKey: shownKey) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(.cyan)
                    .padding(.top, 1)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    UserDefaults.standard.set(true, forKey: shownKey)
                    withAnimation { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            .padding(12)
            .background(Color.cyan.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.15), lineWidth: 1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Morning HRV State Nudge (Today page)

struct HRVMorningNudgeView: View {
    let analysis: HRVAnalysis?

    private var currentHour: Int { Calendar.current.component(.hour, from: Date()) }

    private enum MorningState {
        case received
        case missingAfter9
        case watchNotWorn
        case tooEarly
    }

    private var state: MorningState {
        guard let a = analysis else { return .tooEarly }
        if a.todayRmssd != nil { return .received }
        if currentHour < 9    { return .tooEarly }
        // Si on a des données historiques → Watch probablement portée → mesure manquante
        if a.dataPoints7d > 0 { return .missingAfter9 }
        // Pas d'historique → Watch possiblement non portée
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
    let icon:    String
    let message: String
    let color:   Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15), lineWidth: 1))
        .cornerRadius(10)
    }
}

// MARK: - FAQ Sheet

struct HRVFAQView: View {
    private let items: [(String, String)] = [
        (
            "Pourquoi mesurer le matin ?",
            "Le matin au réveil, ton corps est dans son état le plus stable — pas encore influencé par l'effort, la caféine ou le stress. C'est le seul moment où la mesure est comparable d'un jour à l'autre."
        ),
        (
            "Pourquoi rester allongé ?",
            "Le simple fait de se lever fait monter la fréquence cardiaque et perturbe le HRV pendant plusieurs minutes. Rester allongé garantit une mesure propre et reproductible."
        ),
        (
            "Ma valeur est-elle bonne ou mauvaise ?",
            "La valeur absolue ne signifie rien sans contexte. 40 ms peut être excellent pour toi, faible pour quelqu'un d'autre. Ce qui compte : ta valeur du jour vs ta propre baseline. C'est ce que VinceSeven calcule."
        ),
        (
            "Pourquoi ça change chaque jour ?",
            "Le HRV réagit à tout : sommeil, alcool, stress, volume d'entraînement, alimentation. Une variation d'un jour à l'autre est normale. La tendance sur 7 jours est le signal utile."
        ),
        (
            "Alcool, stress, manque de sommeil — quel impact ?",
            "Alcool : baisse significative le lendemain, même en petite quantité. Manque de sommeil : baisse proportionnelle à la dette de sommeil. Stress chronique : baisse graduelle sur 5-10 jours."
        ),
        (
            "Comment lire vert / orange / rouge ?",
            "Vert (≥110% de ta baseline 7j) : récupération optimale, séance à 100%. Orange (90-109%) : dans la norme, séance normale. Rouge (<90%) : récupération incomplète, réduis le volume."
        ),
        (
            "Et si je n'ai pas de mesure ce matin ?",
            "Aucun problème — l'app n'invente pas de valeur. Ton coaching reste actif basé sur les données récentes. Pas de culpabilité : une mesure manquante n'affecte pas ta baseline."
        ),
    ]

    var body: some View {
        ZStack {
            AmbientBackground(color: .cyan)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        FAQItem(question: item.0, answer: item.1)
                    }
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("HRV — Questions fréquentes")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct FAQItem: View {
    let question: String
    let answer:   String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Text(question)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(answer)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(Color.appCard)
        .cornerRadius(12)
    }
}
