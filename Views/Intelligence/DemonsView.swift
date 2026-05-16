import SwiftUI

struct DemonsView: View {
    let demons: [RitualDemon]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0A").ignoresSafeArea()
                if demons.isEmpty {
                    emptyState
                } else {
                    demonList
                }
            }
            .navigationTitle("Démons")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.4))
                }
            }
        }
    }

    private var demonList: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Ces intentions ont survécu. Elles attendent d'être tuées.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.25))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                ForEach(demons.sorted(by: { $0.carryCount > $1.carryCount })) { demon in
                    DemonCard(demon: demon)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 32)
            }
            .padding(.top, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 32))
                .foregroundColor(Color(white: 0.15))
            Text("Aucun démon")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(white: 0.3))
            Text("Toutes tes intentions ont été tuées.")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.2))
        }
    }
}

private struct DemonCard: View {
    let demon: RitualDemon

    // Fade older demons: opacity drops to 0.45 after 5+ days
    private var textOpacity: Double {
        let nights = demon.carryCount
        if nights >= 5 { return 0.45 }
        return 1.0 - Double(nights) * 0.11
    }

    private var formattedDate: String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: demon.date) else { return demon.date }
        let out = DateFormatter()
        out.dateFormat = "d MMM"
        out.locale = Locale(identifier: "fr_FR")
        return out.string(from: date)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left ghost border
            Rectangle()
                .fill(Color(white: 0.2))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("\"")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(Color(white: 0.15))
                    + Text(demon.intention)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(white: textOpacity))
                    + Text("\"")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(Color(white: 0.15))

                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.25))
                    Text("Survécu · \(demon.carryCount) nuit\(demon.carryCount > 1 ? "s" : "") · \(formattedDate)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.25))
                }
            }
            .padding(.leading, 16)
            .padding(.vertical, 16)
            .padding(.trailing, 12)

            Spacer()
        }
        .background(Color(white: 0.05))
        .cornerRadius(10)
    }
}
