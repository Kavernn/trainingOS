import SwiftUI

struct NutritionPerfInsight {
    enum Kind {
        case deficitStagnation
        case deficitFatigue
        case proteinVolume
    }
    let kind: Kind
    let title: String
    let detail: String
    let actionHint: String

    var icon: String {
        switch kind {
        case .deficitStagnation: return "chart.line.flattrend.xyaxis"
        case .deficitFatigue:    return "heart.slash.fill"
        case .proteinVolume:     return "fork.knife"
        }
    }

    var accentColor: Color {
        switch kind {
        case .deficitStagnation: return .orange
        case .deficitFatigue:    return .red
        case .proteinVolume:     return .yellow
        }
    }
}

struct NutritionPerfInsightCard: View {
    let insight: NutritionPerfInsight
    let onDismiss: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: insight.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(insight.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(insight.accentColor)
                    Text(insight.detail)
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(expanded ? nil : 1)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if expanded {
                Divider().background(insight.accentColor.opacity(0.2)).padding(.horizontal, 12)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.appCaption)
                        .foregroundColor(insight.accentColor.opacity(0.7))
                    Text(insight.actionHint)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(insight.accentColor.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(insight.accentColor.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
