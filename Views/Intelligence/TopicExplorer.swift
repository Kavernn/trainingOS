import SwiftUI

struct CoachTopic {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let query: String
}

let coachTopics: [CoachTopic] = [
    CoachTopic(
        icon: "chart.line.uptrend.xyaxis",
        color: .blue,
        title: "Progression",
        subtitle: "Forces & blocages",
        query: "Analyse ma progression sur les 30 derniers jours. Quels exercices progressent le plus ? Où est-ce que je stagne ?"
    ),
    CoachTopic(
        icon: "moon.zzz.fill",
        color: .blue,
        title: "Récupération",
        subtitle: "HRV, sommeil, fatigue",
        query: "Évalue ma récupération actuelle à partir de mes données HRV et sommeil. Dois-je réduire mon volume ou puis-je pousser ?"
    ),
    CoachTopic(
        icon: "fork.knife",
        color: .orange,
        title: "Nutrition",
        subtitle: "Macros & performance",
        query: "Analyse le lien entre ma nutrition et mes performances. Quels ajustements me feraient progresser plus vite ?"
    ),
    CoachTopic(
        icon: "list.bullet.clipboard",
        color: .green,
        title: "Programme",
        subtitle: "Structure & phases",
        query: "Analyse mon programme d'entraînement actuel. Est-il bien structuré pour mon objectif ? Que changerais-tu ?"
    ),
    CoachTopic(
        icon: "bolt.fill",
        color: .red,
        title: "Intensité",
        subtitle: "RPE & surcharge",
        query: "Mes RPE récents sont-ils cohérents avec mes objectifs ? Est-ce que je m'entraîne avec la bonne intensité ?"
    ),
    CoachTopic(
        icon: "scalemass.fill",
        color: .teal,
        title: "Corps",
        subtitle: "Poids & composition",
        query: "Analyse la tendance de mon poids corporel et de ma composition. Suis-je sur la bonne trajectoire pour mon objectif ?"
    ),
]

struct TopicExplorer: View {
    let onSelect: (String) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXPLORER")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundColor(Color.white.opacity(0.22))

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(coachTopics, id: \.title) { topic in
                    TopicCard(topic: topic, onTap: onSelect)
                }
            }
        }
    }
}

struct TopicCard: View {
    let topic: CoachTopic
    let onTap: (String) -> Void

    var body: some View {
        Button { onTap(topic.query) } label: {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(topic.color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: topic.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(topic.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(topic.subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.32))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "0d0d1a"))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(topic.color.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
