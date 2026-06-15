import SwiftUI
import MapKit

struct GymFinderView: View {
    @StateObject private var vm = GymFinderViewModel()
    @State private var showFilters = false
    @State private var listExpanded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                if vm.locationDenied {
                    locationDeniedState
                } else {
                    VStack(spacing: 0) {
                        mapSection
                            .frame(height: listExpanded ? 140 : UIScreen.main.bounds.height * 0.42)
                            .animation(.spring(response: 0.45), value: listExpanded)

                        radiusPicker

                        if !vm.workoutEquipmentSuggestion.isEmpty && vm.filters.requiredEquipment.isEmpty {
                            workoutBanner
                        }

                        listHeader

                        gymList
                    }
                }
            }
            .navigationTitle("Gym Finder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: vm.filters.isActive
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                            if vm.filters.isActive {
                                Text("Actif")
                                    .font(.appCaption.weight(.medium))
                            }
                        }
                        .foregroundColor(vm.filters.isActive ? Color.forge : .white)
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                GymFiltersView(vm: vm)
            }
            .sheet(item: $vm.selectedGym) { gym in
                GymDetailView(gym: gym, vm: vm)
            }
            .task { vm.requestLocation() }
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $vm.cameraPosition) {
                UserAnnotation()
                ForEach(vm.filteredGyms) { gym in
                    Annotation("", coordinate: gym.coordinate) {
                        GymPin(isSelected: vm.selectedGym?.id == gym.id)
                            .onTapGesture { vm.selectedGym = gym }
                    }
                }
            }
            .mapStyle(.standard)

            if vm.isLoading {
                ProgressView()
                    .tint(Color.forge)
                    .padding(10)
                    .background(Color.appCard.opacity(0.9))
                    .clipShape(Circle())
                    .padding(12)
            }
        }
    }

    // MARK: - Radius Picker

    private var radiusPicker: some View {
        HStack(spacing: 8) {
            ForEach([1, 5, 10, 25], id: \.self) { km in
                Button { vm.changeRadius(km) } label: {
                    Text("\(km) km")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(vm.filters.radiusKm == km ? .black : .appOnSurface.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(vm.filters.radiusKm == km ? Color.forge : Color.appCard))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Workout Banner

    private var workoutBanner: some View {
        Button { vm.applyWorkoutFilter() } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(Color.forge)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout du jour détecté")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    Text("Filtrer : \(vm.workoutEquipmentSuggestion.map(\.label).joined(separator: ", "))")
                        .font(.appCaption)
                        .foregroundColor(.appOnSurface.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                Text("Appliquer →")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.forge)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.forge.opacity(0.08))
        }
        .buttonStyle(.plain)
    }

    // MARK: - List Header

    private var listHeader: some View {
        HStack {
            if let err = vm.error {
                Text(err)
                    .font(.appCaption)
                    .foregroundColor(Color.statusRed.opacity(0.8))
                    .lineLimit(1)
            } else {
                Text(vm.isLoading
                     ? "Recherche…"
                     : "\(vm.filteredGyms.count) gym\(vm.filteredGyms.count == 1 ? "" : "s")")
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appOnSurface.opacity(0.5))
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.4)) { listExpanded.toggle() }
            } label: {
                Image(systemName: listExpanded ? "chevron.down" : "chevron.up")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.appOnSurface.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Gym List

    @ViewBuilder
    private var gymList: some View {
        if vm.gyms.isEmpty && !vm.isLoading {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.filteredGyms) { gym in
                        GymCard(gym: gym, isFavorite: vm.isFavorite(gym))
                            .onTapGesture { vm.selectedGym = gym }
                    }
                    if vm.filteredGyms.isEmpty && !vm.gyms.isEmpty {
                        noFilterResultsState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 36))
                .foregroundColor(Color.forge.opacity(0.5))
            Text("Aucun gym trouvé dans ce rayon")
                .font(.appBody.weight(.semibold))
                .foregroundColor(.appOnSurface.opacity(0.7))
            Text("Élargis le rayon ou continue le combat sans équipement.")
                .font(.appLabel.weight(.regular))
                .foregroundColor(.appOnSurface.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var noFilterResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 28))
                .foregroundColor(Color.forge.opacity(0.5))
            Text("Aucun résultat avec ces filtres")
                .font(.appBody.weight(.semibold))
                .foregroundColor(.appOnSurface.opacity(0.7))
            Button("Réinitialiser les filtres") {
                let radius = vm.filters.radiusKm
                vm.filters = GymFilters()
                vm.filters.radiusKm = radius
            }
            .foregroundColor(Color.forge)
            .font(.appLabel)
        }
        .padding(.top, 30)
    }

    private var locationDeniedState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "location.slash.fill")
                .font(.system(size: 52))
                .foregroundColor(Color.forge.opacity(0.7))
            VStack(spacing: 8) {
                Text("Position requise")
                    .font(.appTitle.weight(.bold))
                    .foregroundColor(.appTextPrimary)
                Text("Gym Finder utilise ta position localement pour trouver les salles à proximité. Ta position n'est jamais envoyée à nos serveurs.")
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(.appOnSurface.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Autoriser dans Réglages")
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.forge)
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }
}

// MARK: - Gym Pin

struct GymPin: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.forge)
                .frame(width: isSelected ? 40 : 30, height: isSelected ? 40 : 30)
                .shadow(color: Color.forge.opacity(0.6), radius: isSelected ? 10 : 4)
            Image(systemName: "dumbbell.fill")
                .font(.system(size: isSelected ? 16 : 12, weight: .bold))
                .foregroundColor(Color.onAccent)
        }
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Gym Card

struct GymCard: View {
    let gym: Gym
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.forge.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: gym.gymType.icon)
                    .font(.appHeadline)
                    .foregroundColor(Color.forge)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(gym.name)
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.appCaption)
                            .foregroundColor(Color.forge)
                    }
                }

                HStack(spacing: 5) {
                    Text(gym.distanceFormatted)
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(.appOnSurface.opacity(0.45))

                    if let open = gym.isOpenNow {
                        Circle()
                            .fill(open ? Color.appSuccess : Color.appDanger)
                            .frame(width: 5, height: 5)
                        Text(open ? "Ouvert" : "Fermé")
                            .font(.appCaption)
                            .foregroundColor(open ? .statusGreen : .statusRed.opacity(0.9))
                    }

                    Text("·")
                        .foregroundColor(.appOnSurface.opacity(0.2))
                    Text(gym.gymType.label)
                        .font(.appCaption)
                        .foregroundColor(.appOnSurface.opacity(0.35))
                }

                if let price = gym.crowdsource?.dropInPrice {
                    Text("Drop-in: \(String(format: "%.0f", price))$")
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(Color.forge.opacity(0.8))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.appCaption.weight(.medium))
                .foregroundColor(.appOnSurface.opacity(0.2))
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}
