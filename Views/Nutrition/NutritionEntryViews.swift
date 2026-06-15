import SwiftUI

// MARK: - Grouped Entry List
struct GroupedEntryList: View {
    let entries: [NutritionEntry]
    let onEdit: (NutritionEntry) -> Void
    let onDelete: (NutritionEntry) -> Void

    private let mealOrder = ["matin", "midi", "soir", "collation"]
    private let mealLabels: [String: String] = [
        "matin": "Matin", "midi": "Midi", "soir": "Soir", "collation": "Collation"
    ]
    private let mealIcons: [String: String] = [
        "matin": "sunrise.fill", "midi": "sun.max.fill", "soir": "moon.fill", "collation": "leaf.fill"
    ]
    private let mealColors: [String: Color] = [
        "matin": Color.statusYellow, "midi": Color.appWarning, "soir": Color.statusPurple, "collation": Color.appSuccess
    ]

    private var grouped: [(key: String, items: [NutritionEntry])] {
        var dict: [String: [NutritionEntry]] = [:]
        for e in entries { dict[e.mealType ?? "collation", default: []].append(e) }
        return mealOrder.compactMap { key in
            guard let items = dict[key], !items.isEmpty else { return nil }
            return (key: key, items: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AUJOURD'HUI")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text("\(entries.count) aliment\(entries.count != 1 ? "s" : "")")
                    .font(.appCaption)
                    .foregroundColor(.appTextSecondary)
            }

            if entries.isEmpty {
                EmptyStateView(icon: "fork.knife", title: "Aucun aliment enregistré")
            } else {
                ForEach(Array(grouped.enumerated()), id: \.element.key) { idx, group in
                    let totalKcal = group.items.compactMap(\.calories).reduce(0, +)
                    let totalProt = group.items.compactMap(\.proteines).reduce(0, +)
                    let color = mealColors[group.key] ?? .gray

                    VStack(alignment: .leading, spacing: 0) {
                        // Section header with subtotal
                        HStack(spacing: 8) {
                            Image(systemName: mealIcons[group.key] ?? "fork.knife")
                                .font(.appCaption)
                                .foregroundColor(color)
                            Text(mealLabels[group.key] ?? group.key.capitalized)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(color)
                            Spacer()
                            Text("\(Int(totalKcal)) kcal")
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(Color.forge)
                            Text("·")
                                .foregroundColor(.appTextSecondary)
                                .font(.appCaption)
                            Text("\(Int(totalProt))g prot")
                                .font(.appCaption)
                                .foregroundColor(Color.statusBlue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(color.opacity(0.07))

                        ForEach(group.items) { entry in
                            NutritionEntryRow(
                                entry: entry,
                                onEdit: { onEdit(entry) },
                                onDelete: { onDelete(entry) }
                            )
                        }
                    }
                    .background(Color.appCard)
                    .cornerRadius(10)
                    .appearAnimation(delay: Double(idx) * 0.06)
                }
            }
        }
    }
}

// MARK: - Entry Row

struct NutritionEntryRow: View {
    let entry: NutritionEntry
    var onEdit: (() -> Void)? = nil
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack {
            Group {
                if let mt = entry.mealType {
                    Image(systemName: mealTypeIcon(mt))
                        .font(.system(size: 12))
                        .foregroundColor(mealTypeColor(mt))
                } else {
                    // N-C4: fallback icon instead of Color.clear
                    Image(systemName: "fork.knife")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name ?? "—")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appTextPrimary)
                HStack(spacing: 8) {
                    if let p = entry.proteines { Text("\(Int(p))g prot").font(.appCaption).foregroundColor(Color.statusBlue) }
                    if let c = entry.glucides  { Text("\(Int(c))g carbs").font(.appCaption).foregroundColor(Color.statusYellow) }
                    if let l = entry.lipides   { Text("\(Int(l))g lip").font(.appCaption).foregroundColor(Color.statusRed) }
                }
            }
            Spacer()
            Text("\(Int(entry.calories ?? 0)) kcal")
                .font(.appBody.weight(.bold))
                .foregroundColor(Color.forge)
            if let onEdit {
                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(Color.forge.opacity(0.8))
                        .padding(.leading, 12)
                }
            }
            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(Color.appDanger.opacity(0.7))
                    .padding(.leading, 8)
            }
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(10)
        .confirmationDialog("Supprimer \(entry.name ?? "cet aliment") ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { onDelete() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func mealTypeIcon(_ type: String) -> String {
        switch type {
        case "matin":     return "sunrise.fill"
        case "midi":      return "sun.max.fill"
        case "soir":      return "moon.fill"
        case "collation": return "leaf.fill"
        default:          return "fork.knife"
        }
    }

    private func mealTypeColor(_ type: String) -> Color {
        switch type {
        case "matin":     return Color.statusYellow
        case "midi":      return Color.appWarning
        case "soir":      return Color.statusPurple
        case "collation": return Color.appSuccess
        default:          return .gray
        }
    }
}
