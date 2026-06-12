import SwiftUI

struct GymContributeView: View {
    let gym: Gym
    @ObservedObject var vm: GymFinderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var dropInPrice: String = ""
    @State private var selectedEquipment: Set<EquipmentKey> = []
    @State private var vibeHardcore: Int = 3
    @State private var vibeCrowded: Int = 2
    @State private var vibeMusic: Int = 3
    @State private var isSubmitting = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                if submitted {
                    thankYouState
                } else {
                    form
                }
            }
            .navigationTitle("Contribuer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Tu aides tous les combattants qui passeront par \(gym.name).")
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                priceCard
                equipmentCard
                vibeCard

                Text("Contribution 100% anonyme. Aucun lien avec ton profil.")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.25))
                    .multilineTextAlignment(.center)

                Button { Task { await submit() } } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(Color.onAccent) }
                        Text(isSubmitting ? "Envoi…" : "Envoyer")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.forge)
                    .cornerRadius(12)
                }
                .disabled(isSubmitting)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Cards

    private var priceCard: some View {
        sectionCard(title: "Prix drop-in") {
            HStack(spacing: 8) {
                TextField("Ex: 15", text: $dropInPrice)
                    .keyboardType(.decimalPad)
                    .font(.appTitle.weight(.bold))
                    .foregroundColor(.appTextPrimary)
                Text("$")
                    .font(.appTitle.weight(.bold))
                    .foregroundColor(Color.forge)
            }
            Text("Laisse vide si tu ne sais pas")
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.25))
        }
    }

    private var equipmentCard: some View {
        sectionCard(title: "Équipement disponible") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(EquipmentKey.allCases, id: \.rawValue) { eq in
                    let selected = selectedEquipment.contains(eq)
                    Button {
                        if selected { selectedEquipment.remove(eq) }
                        else        { selectedEquipment.insert(eq) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selected ? "checkmark.square.fill" : "square")
                                .font(.appLabel.weight(.regular))
                                .foregroundColor(selected ? .green : .white.opacity(0.3))
                            Text(eq.label)
                                .font(.appCaption)
                                .foregroundColor(selected ? .white : .white.opacity(0.45))
                            Spacer()
                        }
                        .padding(8)
                        .background(selected ? Color.green.opacity(0.08) : Color.clear)
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var vibeCard: some View {
        sectionCard(title: "Vibe check") {
            VStack(spacing: 14) {
                vibeRow(label: "Ambiance", value: $vibeHardcore, low: "Casual", high: "Hardcore")
                vibeRow(label: "Affluence", value: $vibeCrowded, low: "Tranquille", high: "Bondé")
                vibeRow(label: "Musique", value: $vibeMusic, low: "Silence", high: "Forte")
            }
        }
    }

    private func vibeRow(label: String, value: Binding<Int>, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.appLabel)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(value.wrappedValue)/5")
                    .font(.appCaption)
                    .foregroundColor(Color.forge)
            }
            HStack(spacing: 0) {
                Text(low)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 52, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { i in
                        Button { value.wrappedValue = i } label: {
                            Circle()
                                .fill(i <= value.wrappedValue ? Color.forge : Color.white.opacity(0.12))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(high)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        let payload = GymContributionPayload(
            gymId: gym.id,
            gymName: gym.name,
            latitude: gym.latitude,
            longitude: gym.longitude,
            dropInPrice: Double(dropInPrice.replacingOccurrences(of: ",", with: ".")),
            equipment: selectedEquipment.map(\.rawValue),
            vibeHardcore: vibeHardcore,
            vibeCrowded: vibeCrowded,
            vibeMusic: vibeMusic
        )
        await vm.submitContribution(payload)
        isSubmitting = false
        withAnimation(.spring(response: 0.4)) { submitted = true }
    }

    // MARK: - Thank You

    private var thankYouState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(Color.forge)
            Text("Merci, soldat.")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.appTextPrimary)
            Text("Ta contribution aide les autres à trouver où se battre.")
                .font(.appLabel.weight(.regular))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Fermer") { dismiss() }
                .foregroundColor(Color.forge)
                .font(.appBody.weight(.medium))
                .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Card Container

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.appCaption.weight(.semibold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            content()
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}
