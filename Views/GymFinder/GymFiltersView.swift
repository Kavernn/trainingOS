import SwiftUI

struct GymFiltersView: View {
    @ObservedObject var vm: GymFinderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        typeSection
                        availabilitySection
                        equipmentSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Réinitialiser") {
                        let radius = vm.filters.radiusKm
                        vm.filters = GymFilters()
                        vm.filters.radiusKm = radius
                    }
                    .foregroundColor(Color.appOnSurface.opacity(0.5))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Appliquer") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(Color.forge)
                }
            }
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        filterCard(title: "Type de gym") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(GymType.allCases, id: \.rawValue) { type in
                    typeChip(type)
                }
            }
        }
    }

    private var availabilitySection: some View {
        filterCard(title: "Disponibilité") {
            VStack(spacing: 0) {
                Toggle(isOn: $vm.filters.openNow) {
                    Label("Ouvert maintenant", systemImage: "clock.fill")
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.appTextPrimary)
                }
                .tint(Color.forge)
                .padding(.vertical, 8)

                Divider().background(Color.appSeparator)

                Toggle(isOn: $vm.filters.dropInOnly) {
                    Label("Drop-in confirmé seulement", systemImage: "dollarsign.circle.fill")
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.appTextPrimary)
                }
                .tint(Color.forge)
                .padding(.vertical, 8)
            }
        }
    }

    private var equipmentSection: some View {
        filterCard(title: "Équipement requis") {
            VStack(alignment: .leading, spacing: 10) {
                if !vm.workoutEquipmentSuggestion.isEmpty {
                    Button {
                        vm.filters.requiredEquipment = Set(vm.workoutEquipmentSuggestion)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "wand.and.stars")
                                .font(.appCaption)
                                .foregroundColor(Color.forge)
                            Text("Auto — workout du jour : \(vm.workoutEquipmentSuggestion.map(\.label).joined(separator: ", "))")
                                .font(.appCaption)
                                .foregroundColor(Color.forge.opacity(0.9))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.forge.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(EquipmentKey.allCases, id: \.rawValue) { eq in
                        equipmentChip(eq)
                    }
                }
            }
        }
    }

    // MARK: - Chips

    private func typeChip(_ type: GymType) -> some View {
        let selected = vm.filters.selectedTypes.contains(type)
        return Button {
            if selected { vm.filters.selectedTypes.remove(type) }
            else        { vm.filters.selectedTypes.insert(type) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: type.icon)
                    .font(.appBody.weight(.semibold))
                Text(type.label)
                    .font(.appCaption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(selected ? .black : Color.appOnSurface.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Color.forge : Color.appCard.opacity(0.6))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                selected ? Color.clear : Color.appSurfaceInset, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func equipmentChip(_ eq: EquipmentKey) -> some View {
        let selected = vm.filters.requiredEquipment.contains(eq)
        return Button {
            if selected { vm.filters.requiredEquipment.remove(eq) }
            else        { vm.filters.requiredEquipment.insert(eq) }
        } label: {
            Text(eq.label)
                .font(.appCaption.weight(.medium))
                .foregroundColor(selected ? .black : Color.appOnSurface.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Color.forge : Color.appCard.opacity(0.6))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                    selected ? Color.clear : Color.appSurfaceInset, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Container

    @ViewBuilder
    private func filterCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.appCaption.weight(.semibold))
                .tracking(1.5)
                .foregroundColor(Color.appOnSurface.opacity(0.35))
            content()
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}
