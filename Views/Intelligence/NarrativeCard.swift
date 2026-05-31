import SwiftUI

struct NarrativeCard: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Récit de la semaine", systemImage: "text.quote")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.teal)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(hex: "0a1018"))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.teal.opacity(0.3), lineWidth: 1))
        .cornerRadius(12)
    }
}
