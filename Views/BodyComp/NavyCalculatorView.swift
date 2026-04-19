import SwiftUI
import SwiftData

// MARK: - Navy Body Fat Calculator (US Navy formula, homme)

struct NavyCalculatorView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var weightLbs: Double = 176
    @State private var heightCm:  Double = 178
    @State private var waistCm:   Double = 84
    @State private var neckCm:    Double = 38
    @State private var savedAt:   Date?  = nil

    // MARK: - Formula

    private struct NavyResult {
        let pct: Double
        let fatMassLbs: Double
        let leanMassLbs: Double
    }

    private var result: NavyResult? {
        guard weightLbs > 0, heightCm > 0, neckCm > 0 else { return nil }
        let diff = waistCm - neckCm
        guard diff > 0 else { return nil }
        let raw = 495.0 / (1.0324 - 0.19077 * log10(diff) + 0.15456 * log10(heightCm)) - 450.0
        let pct = min(max(raw, 2.0), 60.0)
        let fat  = weightLbs * pct / 100.0
        let lean = weightLbs - fat
        return NavyResult(pct: pct, fatMassLbs: fat, leanMassLbs: lean)
    }

    // MARK: - Category

    private func category(for pct: Double) -> (label: String, color: Color) {
        switch pct {
        case ..<6:  return ("Athlète",    .cyan)
        case ..<13: return ("Très fit",   .green)
        case ..<17: return ("Fitness",    .blue)
        case ..<24: return ("Acceptable", .orange)
        default:    return ("Obèse",      .red)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackground(color: .green)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    inputCard
                        .appearAnimation(delay: 0.05)

                    if let res = result {
                        resultCards(res)
                            .appearAnimation(delay: 0.1)
                        compositionBar(res)
                            .appearAnimation(delay: 0.12)
                        categoryBadge(res)
                            .appearAnimation(delay: 0.14)
                        saveButton(res)
                            .appearAnimation(delay: 0.16)
                    } else {
                        invalidHint
                            .appearAnimation(delay: 0.1)
                    }
                }
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Calculateur Navy")
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
        .overlay(alignment: .top) {
            if savedAt != nil {
                savedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: savedAt)
    }

    // MARK: - Input card

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MESURES")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                .padding(.bottom, 14)

            stepperRow("POIDS",        value: $weightLbs, step: 0.5,  format: "%.1f lbs")
            Divider().background(Color.white.opacity(0.06)).padding(.vertical, 10)
            stepperRow("TAILLE",       value: $heightCm,  step: 1.0,  format: "%.0f cm")
            Divider().background(Color.white.opacity(0.06)).padding(.vertical, 10)
            stepperRow("TOUR DE TAILLE", value: $waistCm, step: 0.5, format: "%.1f cm")
            Divider().background(Color.white.opacity(0.06)).padding(.vertical, 10)
            stepperRow("TOUR DE COU",  value: $neckCm,    step: 0.5,  format: "%.1f cm")
        }
        .padding(16)
        .glassCardAccent(.green)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    private func stepperRow(_ label: String, value: Binding<Double>, step: Double, format: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .bold)).tracking(2)
                .foregroundColor(.gray)
            Spacer()
            HStack(spacing: 6) {
                Button {
                    value.wrappedValue = max(0, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundColor(.white)
                }
                .buttonStyle(SpringButtonStyle(scale: 0.93))

                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 90)
                    .multilineTextAlignment(.center)

                Button {
                    value.wrappedValue += step
                } label: {
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
    }

    // MARK: - Result cards

    private func resultCards(_ res: NavyResult) -> some View {
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

    private func compositionBar(_ res: NavyResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMPOSITION")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let leanFrac = CGFloat(res.leanMassLbs / weightLbs)
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

    private func categoryBadge(_ res: NavyResult) -> some View {
        let (label, color) = category(for: res.pct)
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

    // MARK: - Save button

    private func saveButton(_ res: NavyResult) -> some View {
        Button {
            save(res)
        } label: {
            Text("Enregistrer")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.75)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
        }
        .buttonStyle(SpringButtonStyle())
        .padding(.horizontal, 16)
    }

    // MARK: - Invalid hint

    private var invalidHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundColor(.gray)
            Text("Tour de taille doit être supérieur au tour de cou")
                .font(.system(size: 13)).foregroundColor(.gray)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .cornerRadius(14)
        .padding(.horizontal, 16)
    }

    // MARK: - Saved toast

    private var savedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Enregistré dans l'historique")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(hex: "11111c").opacity(0.95))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    // MARK: - Actions

    private func save(_ res: NavyResult) {
        let entry = BodyCompEntry(
            weightLbs:   weightLbs,
            bodyFatPct:  res.pct,
            fatMassLbs:  res.fatMassLbs,
            leanMassLbs: res.leanMassLbs
        )
        modelContext.insert(entry)
        withAnimation { savedAt = .now }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { savedAt = nil }
        }
    }
}
