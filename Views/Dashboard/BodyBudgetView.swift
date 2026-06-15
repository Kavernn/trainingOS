import SwiftUI

// MARK: - Pillar Row

struct PillarRow: View {
    let pillars: BodyBudgetPillars

    var body: some View {
        HStack(spacing: 0) {
            PillarCell(label: "Training",   value: pillars.training,  color: .teal)
            Divider().frame(height: 28).background(Color.appSurfaceInset)
            PillarCell(label: "Stress",     value: pillars.stress,    color: Color(red: 0.55, green: 0.47, blue: 0.9))
            Divider().frame(height: 28).background(Color.appSurfaceInset)
            PillarCell(label: "Nutrition",  value: pillars.nutrition, color: Color(red: 0.95, green: 0.65, blue: 0.1))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color.appSurfaceInset)
        .cornerRadius(10)
    }
}

struct PillarCell: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.appCaption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}
