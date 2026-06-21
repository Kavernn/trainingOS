import SwiftUI

struct StatRow: View {
    let label: String
    let value: String
    var labelColor: Color = .gray
    var valueColor: Color = .appTextPrimary
    var dot: Color? = nil
    var icon: String? = nil
    var iconColor: Color = .gray
    var compact: Bool = false

    private var font: Font { compact ? .appCaption : .appLabel }

    var body: some View {
        HStack(spacing: 8) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            } else if let icon {
                Image(systemName: icon)
                    .font(font)
                    .foregroundColor(iconColor)
            }
            Text(label)
                .font(font)
                .foregroundColor(labelColor)
            Spacer()
            Text(value)
                .font(font.weight(.semibold))
                .foregroundColor(valueColor)
        }
    }
}
