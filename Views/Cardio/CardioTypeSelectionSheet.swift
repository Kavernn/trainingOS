import SwiftUI

// MARK: - CardioType model

struct CardioType: Identifiable {
    let id: String
    let label: String
    let description: String
    let icon: String
}

let cardioTypes: [CardioType] = [
    CardioType(id: "hiit",      label: "Intensité haute", description: "Intervalles, sprints, effort max",   icon: "bolt.fill"),
    CardioType(id: "tempo",     label: "Cardio intense",  description: "Course soutenue, effort difficile",  icon: "flame.fill"),
    CardioType(id: "endurance", label: "Endurance",       description: "Course longue, effort modéré",       icon: "heart.fill"),
    CardioType(id: "leger",     label: "Léger",           description: "Marche rapide, jogging léger",       icon: "figure.walk"),
    CardioType(id: "velo",      label: "Vélo",            description: "Route, montagne, stationnaire",      icon: "bicycle"),
    CardioType(id: "autre",     label: "Autre",           description: "Natation, ski, activité custom",     icon: "figure.run"),
]

// MARK: - CardioTypeSelectionSheet

struct CardioTypeSelectionSheet: View {
    @AppStorage("lastCardioType") private var lastCardioType: String = "endurance"
    @State private var selectedId: String = ""

    let onStart: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Text("Type d'effort")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(cardioTypes) { type in
                        CardioTypeCard(type: type, isSelected: selectedId == type.id) {
                            selectedId = type.id
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Button {
                lastCardioType = selectedId
                onStart(selectedId)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text("Démarrer")
                        .font(.system(size: 18, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(selectedId.isEmpty ? Color.teal.opacity(0.3) : Color.teal)
                .foregroundColor(selectedId.isEmpty ? Color.black.opacity(0.4) : .black)
                .cornerRadius(16)
            }
            .disabled(selectedId.isEmpty)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 36)
        }
        .onAppear { selectedId = lastCardioType }
    }
}

// MARK: - CardioTypeCard

private struct CardioTypeCard: View {
    let type: CardioType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(systemName: type.icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(isSelected ? .teal : .white.opacity(0.7))
                    .frame(height: 34)

                Text(type.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Text(type.description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(isSelected ? 0.7 : 0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.teal.opacity(0.15) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.teal : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}
