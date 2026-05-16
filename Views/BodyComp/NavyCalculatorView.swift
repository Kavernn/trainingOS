import SwiftUI

// MARK: - Navy Body Fat — Consultation View (reads from BodyCompService)

struct NavyCalculatorView: View {
    @ObservedObject private var bodyComp = BodyCompService.shared
    @State private var heightCm: Double = 178

    var body: some View {
        ZStack {
            AmbientBackground(color: .green)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    content
                        .padding(.bottom, 40)
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Navy Body Fat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    BodyCompHistoryView()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
        }
        .task { await bodyComp.refresh() }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        if bodyComp.latest == nil {
            neverLoggedView
        } else if !bodyComp.navyMissingFields.isEmpty {
            incompleteView
        } else {
            heightPickerCard
            if let res = bodyComp.getNavyBodyFat(heightCm: heightCm) {
                resultCards(res)
                compositionBar(res)
                categoryBadge(res)
                stalenessRow
            }
        }
    }

    // MARK: - Never logged

    private var neverLoggedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "scalemass")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            Text("Aucune entrée de poids")
                .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            Text("Commence par enregistrer ton poids dans Body Comp.")
                .font(.system(size: 13)).foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassCard()
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    // MARK: - Incomplete data

    private var incompleteView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text("Données manquantes")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            }
            Text("Pour calculer le % de gras, enregistre aussi :")
                .font(.system(size: 13)).foregroundColor(.gray)
            ForEach(bodyComp.navyMissingFields, id: \.self) { field in
                HStack(spacing: 8) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text(field.capitalized)
                        .font(.system(size: 13)).foregroundColor(.white)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardAccent(.orange)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    // MARK: - Height picker

    private var heightPickerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TAILLE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                .padding(.bottom, 14)

            HStack(spacing: 0) {
                Text("HAUTEUR")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 6) {
                    Button { heightCm = max(140, heightCm - 1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(SpringButtonStyle(scale: 0.93))

                    Text(String(format: "%.0f cm", heightCm))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 70)
                        .multilineTextAlignment(.center)

                    Button { heightCm = min(220, heightCm + 1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(SpringButtonStyle(scale: 0.93))
                }
            }

            Divider().background(Color.white.opacity(0.06)).padding(.vertical, 12)

            if let e = bodyComp.latest {
                measuresRow(e)
            }
        }
        .padding(16)
        .glassCardAccent(.green)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    private func measuresRow(_ e: BodyWeightEntry) -> some View {
        HStack(spacing: 16) {
            measureChip(label: "POIDS", value: String(format: "%.1f lbs", e.weight))
            if let w = e.waistCm {
                measureChip(label: "TAILLE", value: String(format: "%.0f cm", w))
            }
            if let n = e.neckCm {
                measureChip(label: "COU", value: String(format: "%.0f cm", n))
            }
            Spacer()
        }
    }

    private func measureChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
            Text(value)
                .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
        }
    }

    // MARK: - Result cards

    private func resultCards(_ res: NavyBodyFatResult) -> some View {
        HStack(spacing: 10) {
            resultCard(label: "% MG",
                       value: String(format: "%.1f%%", res.pct),
                       color: .blue)
            resultCard(label: "MASSE GRASSE",
                       value: String(format: "%.1f lbs", res.fatMassLbs),
                       color: .orange)
            resultCard(label: "MASSE MAIGRE",
                       value: String(format: "%.1f lbs", res.leanMassLbs),
                       color: .green)
        }
        .padding(.horizontal, 16)
    }

    private func resultCard(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .black)).tracking(1)
                .foregroundColor(color.opacity(0.75))
            Text(value)
                .font(.system(size: 17, weight: .black))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardAccent(color)
        .cornerRadius(14)
    }

    // MARK: - Composition bar

    private func compositionBar(_ res: NavyBodyFatResult) -> some View {
        let weight = bodyComp.latest?.weight ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("COMPOSITION")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let leanFrac = CGFloat(res.leanMassLbs / weight)
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.8))
                        .frame(width: geo.size.width * leanFrac)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.8))
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 14)
            }
            .frame(height: 14)

            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("Masse maigre").font(.system(size: 11)).foregroundColor(.gray)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                    Text("Masse grasse").font(.system(size: 11)).foregroundColor(.gray)
                }
            }
        }
        .padding(16)
        .glassCard(color: .green, intensity: 0.04)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    // MARK: - Category badge

    private func categoryBadge(_ res: NavyBodyFatResult) -> some View {
        let (label, color) = res.category()
        return HStack(spacing: 10) {
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            Text("Catégorie : \(label)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text(String(format: "%.1f%%", res.pct))
                .font(.system(size: 14, weight: .black))
                .foregroundColor(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassCardAccent(color)
        .cornerRadius(14)
        .padding(.horizontal, 16)
    }

    // MARK: - Staleness

    private var stalenessRow: some View {
        let freshness = bodyComp.staleness()
        let label = freshness.label
        guard !label.isEmpty else { return AnyView(EmptyView()) }
        let color: Color = freshness.isProblematic ? .red : .orange
        return AnyView(
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundColor(color)
                Text(label)
                    .font(.system(size: 12)).foregroundColor(color)
                Spacer()
            }
            .padding(.horizontal, 20)
        )
    }
}
