import SwiftUI
import MapKit

struct GymDetailView: View {
    let gym: Gym
    @ObservedObject var vm: GymFinderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showContribute = false
    @State private var showAdapt = false
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
                            .foregroundColor(vm.isFavorite(gym) ? Color.forge : .white.opacity(0.5))
                    }
                }
            }
            .sheet(isPresented: $showContribute) {
                GymContributeView(gym: gym, vm: vm)
            }
            .sheet(isPresented: $showAdapt) {
                AdaptWorkoutSheet(gym: gym, vm: vm)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.forge.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: gym.gymType.icon)
                        .font(.appTitle.weight(.semibold))
                        .foregroundColor(Color.forge)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(gym.name)
                        .font(.appTitle.weight(.bold))
                        .foregroundColor(.appTextPrimary)
                    Text(gym.gymType.label)
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(Color.forge.opacity(0.8))
                }
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "mappin.circle")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.35))
                Text(gym.address)
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(.white.opacity(0.55))
            }

            if let d = gym.distanceMeters {
                Text(d < 1000
                     ? "\(Int(d)) m de ta position"
                     : String(format: "%.1f km de ta position", d / 1000))
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.forge)
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
                    .font(.appLabel.weight(.regular))
                    .foregroundColor(Color.forge)
                Text("Horaires")
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Spacer()
                if let open = gym.isOpenNow {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(open ? Color.appSuccess : Color.appDanger)
                            .frame(width: 6, height: 6)
                        Text(open ? "Ouvert" : "Fermé")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(open ? Color.appSuccess : Color.appDanger)
                    }
                }
            }

            if let hours = gym.openingHours {
                Text(hours)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Appelle pour confirmer avant de te déplacer.")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.25))
                    .italic()
            } else {
                Text("Horaires non disponibles — appelle pour confirmer.")
                    .font(.appCaption)
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
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.statusGreen)
                    Text("Communauté — \(cs.contributionCount) contribution\(cs.contributionCount == 1 ? "" : "s")")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    if let price = cs.dropInPrice {
                        Text("Drop-in: \(String(format: "%.0f", price))$")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(Color.forge)
                    }
                }

                if !cs.equipment.isEmpty {
                    let keys = cs.equipment.compactMap { EquipmentKey(rawValue: $0) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100)), GridItem(.adaptive(minimum: 100))], spacing: 6) {
                        ForEach(keys, id: \.rawValue) { eq in
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                    .font(.appMicro.weight(.bold))
                                    .foregroundColor(.statusGreen)
                                Text(eq.label)
                                    .font(.appCaption.weight(.medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.appSuccess.opacity(0.08))
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
                        .font(.appCaption)
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
                .font(.appCaption.weight(.semibold))
                .foregroundColor(.white.opacity(0.4))
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= value ? Color.forge : Color.white.opacity(0.1))
                        .frame(width: 16, height: 5)
                }
            }
            HStack {
                Text(low).font(.appMicro).foregroundColor(.white.opacity(0.25))
                Spacer()
                Text(high).font(.appMicro).foregroundColor(.white.opacity(0.25))
            }
            .frame(width: 16 * 5 + 3 * 4)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button { openDirections() } label: {
                Label("Itinéraire", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.forge)
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
                outlineButton(label: "Contribuer", icon: "pencil.circle", tint: Color.forge) {
                    showContribute = true
                }
                outlineButton(
                    label: visitLogged ? "Enregistré ✓" : "J'y suis entraîné",
                    icon: "checkmark.circle.fill",
                    tint: .statusGreen
                ) {
                    guard !visitLogged else { return }
                    vm.logVisit(to: gym)
                    visitLogged = true
                }
            }

            if !vm.workoutEquipmentSuggestion.isEmpty {
                Button { showAdapt = true } label: {
                    Label("Adapter mon workout pour ce gym", systemImage: "arrow.triangle.2.circlepath")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(Color.forge)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.forge.opacity(0.10))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.forge.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func outlineButton(label: String, icon: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.appLabel)
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

// MARK: - Adapt Workout Sheet

struct AdaptWorkoutSheet: View {
    let gym: Gym
    @ObservedObject var vm: GymFinderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack { Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        profilePicker
                        equipmentGap
                        substitutionList
                        coachNote
                        Spacer(minLength: 20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Adapter le workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Profile Picker

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROFIL D'ÉQUIPEMENT")
                .font(.appCaption.weight(.bold)).tracking(1.5).foregroundColor(.white.opacity(0.35))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EquipmentProfile.presets) { preset in
                        let selected = vm.selectedEquipmentProfile?.id == preset.id
                        Button { vm.selectedEquipmentProfile = selected ? nil : preset } label: {
                            VStack(spacing: 4) {
                                Image(systemName: preset.icon)
                                    .font(.appBody.weight(.semibold))
                                Text(preset.name)
                                    .font(.appCaption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(selected ? .black : .white.opacity(0.65))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(selected ? Color.forge : Color.appCard)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                    if gym.crowdsource != nil {
                        let autoSelected = vm.selectedEquipmentProfile == nil
                        Button { vm.selectedEquipmentProfile = nil } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.appBody.weight(.semibold))
                                Text("Auto (communauté)")
                                    .font(.appCaption.weight(.medium)).lineLimit(1)
                            }
                            .foregroundColor(autoSelected ? .black : .white.opacity(0.65))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(autoSelected ? Color.forge : Color.appCard)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14).background(Color.appCard).cornerRadius(14)
    }

    // MARK: - Equipment Gap

    private var equipmentGap: some View {
        let available = vm.effectiveAvailable(for: gym)
        let needed = vm.workoutEquipmentSuggestion
        return VStack(alignment: .leading, spacing: 10) {
            Text("ÉQUIPEMENT REQUIS")
                .font(.appCaption.weight(.bold)).tracking(1.5).foregroundColor(.white.opacity(0.35))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(needed, id: \.rawValue) { eq in
                    let ok = available.contains(eq)
                    HStack(spacing: 6) {
                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.appLabel.weight(.regular)).foregroundColor(ok ? .statusGreen : .statusRed)
                        Text(eq.label)
                            .font(.appCaption.weight(.medium)).foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    .padding(8)
                    .background((ok ? Color.appSuccess : Color.appDanger).opacity(0.08))
                    .cornerRadius(8)
                }
            }

            if available.isEmpty && gym.crowdsource == nil {
                Text("Aucune donnée communauté pour ce gym — sélectionne un profil ci-dessus.")
                    .font(.appCaption).foregroundColor(.white.opacity(0.35)).italic()
            }
        }
        .padding(14).background(Color.appCard).cornerRadius(14)
    }

    // MARK: - Substitutions

    @ViewBuilder
    private var substitutionList: some View {
        let available = vm.effectiveAvailable(for: gym)
        let subs = WorkoutSubstitutionEngine.suggestions(needed: vm.workoutEquipmentSuggestion, available: available)
        if !subs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("SUBSTITUTIONS SUGGÉRÉES")
                    .font(.appCaption.weight(.bold)).tracking(1.5).foregroundColor(.white.opacity(0.35))

                ForEach(subs) { sub in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(sub.originalEquipment)
                                .font(.appCaption).foregroundColor(Color.statusRed.opacity(0.8))
                                .strikethrough()
                            Image(systemName: "arrow.right")
                                .font(.appCaption).foregroundColor(.white.opacity(0.3))
                            Text(sub.substitute)
                                .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                            Spacer()
                            Text(sub.setsReps)
                                .font(.appCaption.weight(.bold)).foregroundColor(Color.forge)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "dumbbell.fill")
                                .font(.appMicro).foregroundColor(.white.opacity(0.3))
                            Text(sub.equipment)
                                .font(.appCaption).foregroundColor(.white.opacity(0.4))
                        }
                        if let note = sub.note {
                            Text(note)
                                .font(.appCaption).foregroundColor(.white.opacity(0.35)).italic()
                        }
                    }
                    .padding(10).background(Color.white.opacity(0.04)).cornerRadius(10)
                }
            }
            .padding(14).background(Color.appCard).cornerRadius(14)
        }
    }

    // MARK: - Coach Note

    private var coachNote: some View {
        let available = vm.effectiveAvailable(for: gym)
        let missing = vm.workoutEquipmentSuggestion.filter { !available.contains($0) }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.appLabel.weight(.regular)).foregroundColor(Color.forge).padding(.top, 1)
            Text(WorkoutSubstitutionEngine.coachMessage(missing: missing))
                .font(.appLabel).foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.forge.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.forge.opacity(0.18), lineWidth: 1))
        .cornerRadius(10)
    }
}
