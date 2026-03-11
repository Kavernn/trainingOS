import SwiftUI

struct InventoryItem {
    let type: String
    let category: String
    let level: String
    let barWeight: Double?
    let muscles: [String]
}

struct InventaireView: View {
    @State private var inventory: [String: InventoryItem] = [:]
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedType = "Tous"
    @State private var selectedCategory = "Tous"

    let types      = ["Tous", "barbell", "dumbbell", "cable", "machine", "bodyweight"]
    let categories = ["Tous", "push", "pull", "legs", "core", "mobility"]

    var filtered: [(String, InventoryItem)] {
        inventory
            .filter { name, item in
                (selectedType == "Tous" || item.type == selectedType) &&
                (selectedCategory == "Tous" || item.category == selectedCategory) &&
                (searchText.isEmpty || name.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.orange)
                } else {
                    VStack(spacing: 0) {
                        // Search
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.gray)
                            TextField("Rechercher...", text: $searchText)
                                .foregroundColor(.white)
                                .tint(.orange)
                        }
                        .padding(12)
                        .background(Color(hex: "11111c"))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                        // Type filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(types, id: \.self) { t in
                                    FilterChip(
                                        label: typeLabel(t),
                                        selected: selectedType == t,
                                        color: typeColor(t)
                                    ) { selectedType = t }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 6)

                        // Category filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(categories, id: \.self) { c in
                                    FilterChip(
                                        label: catLabel(c),
                                        selected: selectedCategory == c,
                                        color: catColor(c)
                                    ) { selectedCategory = c }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 8)

                        // Count
                        HStack {
                            Text("\(filtered.count) exercice\(filtered.count != 1 ? "s" : "")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)

                        if filtered.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundColor(.gray)
                                Text("Aucun exercice trouvé").foregroundColor(.gray)
                            }
                            .padding(.top, 40)
                            Spacer()
                        } else {
                            List {
                                ForEach(filtered, id: \.0) { name, item in
                                    InventaireRow(name: name, item: item)
                                        .listRowBackground(Color(hex: "11111c"))
                                        .listRowSeparatorTint(Color.white.opacity(0.07))
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("Inventaire")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await loadData() }
    }

    private func typeLabel(_ t: String) -> String {
        switch t {
        case "barbell":    return "Barre"
        case "dumbbell":   return "Haltère"
        case "cable":      return "Câble"
        case "machine":    return "Machine"
        case "bodyweight": return "Corps"
        default: return "Tous"
        }
    }

    private func catLabel(_ c: String) -> String {
        switch c {
        case "push": return "Push"; case "pull": return "Pull"; case "legs": return "Jambes"
        case "core": return "Core"; case "mobility": return "Mobilité"
        default: return "Tous"
        }
    }

    private func typeColor(_ t: String) -> Color {
        switch t {
        case "barbell": return .orange; case "dumbbell": return .blue
        case "cable": return .teal; case "machine": return .purple
        case "bodyweight": return .green; default: return .gray
        }
    }

    private func catColor(_ c: String) -> Color {
        switch c {
        case "push": return .red; case "pull": return .blue
        case "legs": return .green; case "core": return .orange
        case "mobility": return .purple; default: return .gray
        }
    }

    private func loadData() async {
        isLoading = true
        let url = URL(string: "https://training-os-rho.vercel.app/api/inventaire_data")!
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let inv = json["inventory"] as? [String: [String: Any]] {
            inventory = inv.reduce(into: [:]) { result, pair in
                let d = pair.value
                result[pair.key] = InventoryItem(
                    type:      d["type"] as? String ?? "machine",
                    category:  d["category"] as? String ?? "",
                    level:     d["level"] as? String ?? "",
                    barWeight: d["bar_weight"] as? Double,
                    muscles:   d["muscles"] as? [String] ?? []
                )
            }
        }
        isLoading = false
    }
}

struct FilterChip: View {
    let label: String
    let selected: Bool
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? color.opacity(0.2) : Color(hex: "191926"))
                .foregroundColor(selected ? color : .gray)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? color.opacity(0.5) : Color.clear, lineWidth: 1))
        }
    }
}

struct InventaireRow: View {
    let name: String
    let item: InventoryItem

    var typeIcon: String {
        switch item.type {
        case "barbell":    return "chart.bar.fill"
        case "dumbbell":   return "dumbbell.fill"
        case "cable":      return "link"
        case "bodyweight": return "figure.walk"
        default:           return "figure.strengthtraining.traditional"
        }
    }

    var typeColor: Color {
        switch item.type {
        case "barbell":    return .orange
        case "dumbbell":   return .blue
        case "cable":      return .teal
        case "bodyweight": return .green
        default:           return .purple
        }
    }

    var levelColor: Color {
        switch item.level {
        case "beginner": return .green; case "intermediate": return .orange
        case "advanced": return .red; default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: typeIcon)
                    .font(.system(size: 16))
                    .foregroundColor(typeColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Text(item.type.capitalized)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    if !item.category.isEmpty {
                        Text("·").foregroundColor(.gray.opacity(0.4)).font(.system(size: 11))
                        Text(item.category.capitalized)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    if !item.level.isEmpty {
                        Text("·").foregroundColor(.gray.opacity(0.4)).font(.system(size: 11))
                        Text(item.level.capitalized)
                            .font(.system(size: 11))
                            .foregroundColor(levelColor)
                    }
                }
            }
            Spacer()
            if let bw = item.barWeight, bw > 0 {
                Text("\(Int(bw)) lbs")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 6)
    }
}
