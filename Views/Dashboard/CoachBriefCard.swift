import SwiftUI

struct CoachBriefCard: View {
    let brief: MorningBriefData
    let sessionCompletedToday: Bool

    private var contextLabel: String {
        if sessionCompletedToday { return "Coach · Post-séance" }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5  && hour < 11 { return "Coach · Ce matin" }
        if hour >= 14 && hour < 18 { return "Coach · Pré-séance" }
        if hour >= 19              { return "Coach · Ce soir" }
        return "Coach"
    }

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .navigateToIntelligence, object: nil)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "brain.head.profile")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(contextLabel)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.orange)
                            .textCase(.uppercase)
                            .tracking(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.appCaption.weight(.medium))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Text(brief.message)
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            .padding(14)
            .background(Color.orange.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange.opacity(0.22), lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
