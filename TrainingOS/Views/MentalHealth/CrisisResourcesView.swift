import SwiftUI

struct CrisisResourcesView: View {
    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Cette section est une ressource d'information. Si tu es en danger immédiat, appelle le 911.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Lignes d'aide — Québec") {
                CrisisResourceRow(
                    name: "Centre de prévention du suicide",
                    number: "1-866-APPELLE (277-3553)",
                    description: "Disponible 24h/24, 7j/7",
                    color: .red
                )
                CrisisResourceRow(
                    name: "Ligne Jeunesse",
                    number: "1-800-668-6868",
                    description: "Pour les jeunes jusqu'à 20 ans",
                    color: .blue
                )
                CrisisResourceRow(
                    name: "Tel-Aide Québec",
                    number: "514-935-1101",
                    description: "Écoute et soutien émotionnel",
                    color: .purple
                )
                CrisisResourceRow(
                    name: "Urgences",
                    number: "911",
                    description: "Danger immédiat pour toi ou autrui",
                    color: .orange
                )
            }

            Section("Exercices anti-panique") {
                AntiPanicCard(
                    title: "Technique 5-4-3-2-1",
                    steps: [
                        "5 choses que tu VOIS",
                        "4 choses que tu TOUCHES",
                        "3 choses que tu ENTENDS",
                        "2 choses que tu SENS",
                        "1 chose que tu GOÛTES",
                    ],
                    icon: "eye.fill",
                    color: .teal
                )
                AntiPanicCard(
                    title: "Respiration 4-7-8",
                    steps: [
                        "Inspire par le nez — 4 secondes",
                        "Retiens ta respiration — 7 secondes",
                        "Expire lentement — 8 secondes",
                        "Répète 4 fois",
                    ],
                    icon: "wind",
                    color: .green
                )
                AntiPanicCard(
                    title: "Ancrage physique",
                    steps: [
                        "Pose les pieds à plat sur le sol",
                        "Appuie le dos contre le dossier",
                        "Serre et relâche les poings 5 fois",
                        "Prends 3 grandes respirations",
                    ],
                    icon: "figure.stand",
                    color: .blue
                )
            }

            Section {
                Text("Si tu traverses une période difficile, n'hésite pas à consulter un professionnel de la santé mentale. Parler à quelqu'un peut faire une grande différence.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ressources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CrisisResourceRow: View {
    let name: String
    let number: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.bold())
                Text(number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(color)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                let clean = number.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "+")).inverted).joined()
                if let url = URL(string: "tel://\(clean)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Appeler")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct AntiPanicCard: View {
    let title: String
    let steps: [String]
    let icon: String
    let color: Color

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .frame(width: 24)
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).")
                                .font(.caption.bold())
                                .foregroundColor(color)
                                .frame(width: 16, alignment: .leading)
                            Text(step)
                                .font(.caption)
                        }
                    }
                }
                .padding(.leading, 32)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
