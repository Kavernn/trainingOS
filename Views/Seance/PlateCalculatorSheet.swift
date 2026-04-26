import SwiftUI

// MARK: - Plate Calculator Sheet
// Shown from ExerciseCard header when equipmentType == "barbell".
// Accepts total weight input → computes plates per side → visual barbell.
struct PlateCalculatorSheet: View {
    @ObservedObject private var units = UnitSettings.shared
    /// Pre-filled total weight in display units (lbs or kg)
    var initialTotal: Double
    /// Called with per-side value in display units when user applies
    var onApply: ((Double) -> Void)?

    @State private var totalStr: String = ""
    @Environment(\.dismiss) private var dismiss

    // Bar weights in display units
    private var barWeight: Double { units.isKg ? 20.0 : 45.0 }

    private var totalInput: Double? {
        Double(totalStr.replacingOccurrences(of: ",", with: "."))
    }

    private var perSide: Double {
        guard let t = totalInput, t > barWeight else { return 0 }
        return (t - barWeight) / 2.0
    }

    private var plates: [PlateItem] {
        PlateItem.calculate(perSide: perSide, isKg: units.isKg)
    }

    private var isValid: Bool {
        guard let t = totalInput else { return false }
        return t > barWeight && perSide >= 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0D0D14").ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Weight input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("POIDS TOTAL (\(units.label.uppercased()))")
                                .font(.system(size: 10, weight: .bold)).tracking(2)
                                .foregroundColor(.gray)
                            HStack(spacing: 12) {
                                TextField("ex. 100", text: $totalStr)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 32, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                Text(units.label)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.gray)
                            }
                            .padding(14)
                            .background(Color(hex: "191926"))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            HStack(spacing: 16) {
                                Label("Barre : \(barWeightStr)", systemImage: "minus.square.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                if isValid {
                                    Label("Par côté : \(String(format: "%.2f", perSide)) \(units.label)", systemImage: "arrow.left.and.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.horizontal, 4)
                        }

                        // Plate breakdown
                        if isValid {
                            VStack(spacing: 16) {
                                // Visual barbell
                                BarbellDiagramView(plates: plates)
                                    .frame(height: 88)
                                    .padding(.horizontal, 8)

                                Divider().background(Color.white.opacity(0.08))

                                // Plate list
                                VStack(spacing: 8) {
                                    ForEach(plates) { plate in
                                        HStack(spacing: 12) {
                                            Circle()
                                                .fill(plate.color)
                                                .frame(width: 12, height: 12)
                                            Text("\(plate.count) × \(plate.label)")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text("= \(String(format: "%.2g", plate.value * Double(plate.count))) \(units.label)")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .background(plate.color.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                            .padding(16)
                            .glassCard()
                            .cornerRadius(16)
                        } else if totalInput != nil {
                            Label("Poids inférieur au poids de barre (\(barWeightStr))", systemImage: "exclamationmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Quick presets
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CHARGES RAPIDES")
                                .font(.system(size: 10, weight: .bold)).tracking(2)
                                .foregroundColor(.gray)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                                GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(presets, id: \.self) { v in
                                    Button {
                                        totalStr = String(format: "%.4g", v)
                                        triggerImpact(style: .light)
                                    } label: {
                                        Text("\(String(format: "%.4g", v))")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(Color.white.opacity(0.06))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(SpringButtonStyle())
                                }
                            }
                        }

                        Spacer(minLength: 32)

                        if let onApply, isValid {
                            Button {
                                onApply(perSide)
                                dismiss()
                            } label: {
                                Text("Appliquer \(String(format: "%.2g", perSide)) \(units.label) / côté")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Color(hex: "080810"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(SpringButtonStyle())
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Calculateur de disques")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color(hex: "0D0D14"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if initialTotal > barWeight {
                totalStr = String(format: "%.4g", initialTotal)
            }
        }
    }

    private var barWeightStr: String { "\(Int(barWeight)) \(units.label)" }

    private var presets: [Double] {
        units.isKg
            ? [40, 60, 80, 100, 120, 140, 160, 180]
            : [95, 115, 135, 155, 185, 225, 275, 315]
    }
}

// MARK: - Barbell diagram
private struct BarbellDiagramView: View {
    let plates: [PlateItem]

    // Expand to individual plate list
    private var flat: [PlateItem] {
        plates.flatMap { p in Array(repeating: p, count: p.count) }
    }

    var body: some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let centerY = geo.size.height / 2
            ZStack {
                // Bar sleeve
                Rectangle()
                    .fill(Color(hex: "8A8A8A"))
                    .frame(width: geo.size.width, height: 7)
                    .position(x: centerX, y: centerY)

                // Collars
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: "C0C0C0"))
                    .frame(width: 10, height: 44)
                    .position(x: centerX - 30, y: centerY)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: "C0C0C0"))
                    .frame(width: 10, height: 44)
                    .position(x: centerX + 30, y: centerY)

                // Right side plates (inner → outer)
                HStack(spacing: 3) {
                    ForEach(Array(flat.enumerated()), id: \.offset) { _, p in
                        plateRect(p)
                    }
                }
                .position(x: centerX + 30 + plateBlockWidth / 2 + 8, y: centerY)

                // Left side plates (mirror: outer → inner)
                HStack(spacing: 3) {
                    ForEach(Array(flat.reversed().enumerated()), id: \.offset) { _, p in
                        plateRect(p)
                    }
                }
                .position(x: centerX - 30 - plateBlockWidth / 2 - 8, y: centerY)
            }
        }
    }

    private var plateBlockWidth: CGFloat {
        let n = CGFloat(flat.count)
        return n * 10 + max(0, n - 1) * 3
    }

    private func plateRect(_ p: PlateItem) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(p.color)
            .frame(width: 10, height: p.visualHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(p.color.opacity(0.6), lineWidth: 1)
            )
    }
}

// MARK: - Plate model
struct PlateItem: Identifiable {
    let id = UUID()
    let value: Double      // weight in display units
    let label: String
    let count: Int
    let color: Color
    let visualHeight: CGFloat

    static func calculate(perSide: Double, isKg: Bool) -> [PlateItem] {
        let available: [(Double, String, Color, CGFloat)] = isKg
            ? [
                (20,    "20 kg",  Color(hex: "D32F2F"), 72),
                (15,    "15 kg",  Color(hex: "F9A825"), 62),
                (10,    "10 kg",  Color(hex: "388E3C"), 54),
                (5,     "5 kg",   Color(hex: "BDBDBD"), 44),
                (2.5,   "2.5 kg", Color(hex: "1565C0"), 34),
                (1.25,  "1.25 kg",Color(hex: "E65100"), 26),
                (0.5,   "0.5 kg", Color(hex: "6A1B9A"), 20),
              ]
            : [
                (45,    "45 lbs", Color(hex: "D32F2F"), 72),
                (35,    "35 lbs", Color(hex: "F9A825"), 62),
                (25,    "25 lbs", Color(hex: "388E3C"), 54),
                (10,    "10 lbs", Color(hex: "BDBDBD"), 44),
                (5,     "5 lbs",  Color(hex: "1565C0"), 34),
                (2.5,   "2.5 lbs",Color(hex: "E65100"), 26),
                (1.25,  "1.25 lbs",Color(hex: "6A1B9A"), 20),
              ]

        var remaining = perSide
        var result: [PlateItem] = []
        for (w, label, color, h) in available {
            let n = Int(remaining / w)
            if n > 0 {
                result.append(PlateItem(value: w, label: label, count: n, color: color, visualHeight: h))
                remaining -= Double(n) * w
                remaining = round(remaining * 1000) / 1000 // float cleanup
            }
        }
        return result
    }
}
