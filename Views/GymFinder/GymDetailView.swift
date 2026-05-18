import SwiftUI
import MapKit

struct GymDetailView: View {
    let gym: Gym
    @ObservedObject var vm: GymFinderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showContribute = false
    @State private var visitLogged = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        headerSection
                        hoursCard
                        if gym.crowdsource != nil { equipmentCard }
                        actionButtons
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(.white.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.toggleFavorite(gym) } label: {
                        Image(systemName: vm.isFavorite(gym) ? "star.fill" : "star")
                            .foregroundColor(vm.isFavorite(gym) ? .orange : .white.opacity(0.5))
                    }
                }
            }
            .sheet(isPresented: $showContribute) {
                GymContributeView(gym: gym, vm: vm)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: gym.gymType.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(gym.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text(gym.gymType.label)
                        .font(.system(size: 13))
                        .foregroundColor(.orange.opacity(0.8))
                }
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "mappin.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
                Text(gym.address)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
            }

            if let d = gym.distanceMeters {
                Text(d < 1000
                     ? "\(Int(d)) m de ta position"
                     : String(format: "%.1f km de ta position", d / 1000))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    // MARK: - Hours

    private var hoursCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                Text("Horaires")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let open = gym.isOpenNow {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(open ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(open ? "Ouvert" : "Fermé")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(open ? .green : .red)
                    }
                }
            }

            if let hours = gym.openingHours {
                Text(hours)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Appelle pour confirmer avant de te déplacer.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                    .italic()
            } else {
                Text("Horaires non disponibles — appelle pour confirmer.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
                    .italic()
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    // MARK: - Equipment (crowdsource)

    @ViewBuilder
    private var equipmentCard: some View {
        if let cs = gym.crowdsource {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                    Text("Communauté — \(cs.contributionCount) contribution\(cs.contributionCount == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    if let price = cs.dropInPrice {
                        Text("Drop-in: \(String(format: "%.0f", price))$")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }

                if !cs.equipment.isEmpty {
                    let keys = cs.equipment.compactMap { EquipmentKey(rawValue: $0) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100)), GridItem(.adaptive(minimum: 100))], spacing: 6) {
                        ForEach(keys, id: \.rawValue) { eq in
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                                Text(eq.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.08))
                            .cornerRadius(7)
                        }
                    }
                }

                if let hardcore = cs.vibeHardcore {
                    HStack(spacing: 20) {
                        vibeRow(label: "Ambiance", value: hardcore, low: "Casual", high: "Hardcore")
                        if let crowded = cs.vibeCrowded {
                            vibeRow(label: "Affluence", value: crowded, low: "Calme", high: "Bondé")
                        }
                    }
                }

                if let last = cs.lastUpdated {
                    Text("Mis à jour \(last)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
            .padding(14)
            .background(Color.appCard)
            .cornerRadius(14)
        }
    }

    private func vibeRow(label: String, value: Int, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= value ? Color.orange : Color.white.opacity(0.1))
                        .frame(width: 16, height: 5)
                }
            }
            HStack {
                Text(low).font(.system(size: 9)).foregroundColor(.white.opacity(0.25))
                Spacer()
                Text(high).font(.system(size: 9)).foregroundColor(.white.opacity(0.25))
            }
            .frame(width: 16 * 5 + 3 * 4)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button { openDirections() } label: {
                Label("Itinéraire", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .cornerRadius(12)
            }

            HStack(spacing: 10) {
                if let phone = gym.phone {
                    outlineButton(label: "Appeler", icon: "phone.fill") {
                        let digits = phone.filter { $0.isNumber || $0 == "+" }
                        if let url = URL(string: "tel://\(digits)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                if let site = gym.website, let url = URL(string: site) {
                    outlineButton(label: "Site web", icon: "globe") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            HStack(spacing: 10) {
                outlineButton(label: "Contribuer", icon: "pencil.circle", tint: .orange) {
                    showContribute = true
                }
                outlineButton(
                    label: visitLogged ? "Enregistré ✓" : "J'y suis entraîné",
                    icon: "checkmark.circle.fill",
                    tint: .green
                ) {
                    guard !visitLogged else { return }
                    vm.logVisit(to: gym)
                    visitLogged = true
                }
            }
        }
    }

    private func outlineButton(label: String, icon: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tint.opacity(0.08))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.2), lineWidth: 1))
        }
    }

    private func openDirections() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: gym.latitude, longitude: gym.longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = gym.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
