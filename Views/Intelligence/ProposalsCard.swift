import SwiftUI

struct ProposalsCard: View {
    let proposals: [AIProposal]
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Propositions IA", systemImage: "wand.and.stars")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.purple)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }

            ForEach(proposals) { p in
                HStack(alignment: .top, spacing: 10) {
                    Text(actionIcon(p.action))
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(p.jour).font(.appCaption.weight(.bold)).foregroundColor(.white)
                            if !p.exercise.isEmpty {
                                Text("·").foregroundColor(.gray)
                                Text(p.exercise).font(.appCaption).foregroundColor(.purple)
                            }
                            if !p.scheme.isEmpty {
                                Text(p.scheme).font(.appCaption).foregroundColor(.orange)
                            }
                        }
                        Text(p.reason).font(.system(size: 12)).foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appBg)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.3), lineWidth: 1))
        .cornerRadius(12)
    }

    private func actionIcon(_ action: String) -> String {
        switch action {
        case "add":     return "➕"
        case "remove":  return "➖"
        case "replace": return "🔄"
        case "scheme":  return "📐"
        default:        return "💡"
        }
    }
}
