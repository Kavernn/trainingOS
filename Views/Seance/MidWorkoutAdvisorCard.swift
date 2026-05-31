import SwiftUI

// MARK: - Mid-Workout Intelligence

struct MidWorkoutAdvice {
    let id: String
    let icon: String
    let color: Color
    let title: String
    let message: String
}

struct MidWorkoutAdvisorCard: View {
    let advice: MidWorkoutAdvice
    let onDismiss: () -> Void
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: advice.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(advice.color)

                Text(advice.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(advice.color)

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
            .padding(.horizontal, 12).padding(.vertical, 10)

            if expanded {
                Divider().background(advice.color.opacity(0.2)).padding(.horizontal, 12)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundColor(advice.color.opacity(0.7))
                    Text(advice.message)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(advice.color.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(advice.color.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
