import SwiftUI

struct WarRoomStripView: View {
    let hasResult: Bool
    let hasTemptation: Bool
    let onResultTap: () -> Void
    let onTemptationTap: () -> Void

    private var statusAccent: Color {
        if hasTemptation && !hasResult { return Color.appDanger }
        if hasResult { return Color.appSuccess }
        return Color.appTextSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.appLabel.weight(.bold))
                    .foregroundColor(statusAccent)
                Text("WAR ROOM")
                    .font(.appMicro.weight(.black))
                    .tracking(1.4)
                    .foregroundColor(Color.appTextSecondary)
                Spacer()
                if hasResult && hasTemptation {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appLabel)
                        .foregroundColor(Color.appSuccess)
                }
            }

            if hasResult && hasTemptation {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appCaption)
                        .foregroundColor(Color.appSuccess)
                    Text("Journée loggée")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(Color.appTextSecondary)
                }
            } else {
                VStack(spacing: 8) {
                    resultButton
                    temptationButton
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(statusAccent.opacity(0.18), lineWidth: 1)
        )
        .glassCard(cornerRadius: 14)
    }

    private var resultButton: some View {
        Button(action: onResultTap) {
            HStack(spacing: 4) {
                Image(systemName: hasResult ? "checkmark" : "flag.fill")
                    .font(.system(size: 10)).fontWeight(.bold)
                Text(hasResult ? "Résultat ✓" : "Résultat →")
                    .font(.appCaption).fontWeight(.semibold)
            }
            .foregroundColor(hasResult ? Color.appTextMuted : Color.appOnSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.appSurfaceInset)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(
                        hasResult ? Color.appSeparatorSubtle : Color.appSuccess.opacity(0.45),
                        lineWidth: 0.5
                    ))
            )
        }
        .buttonStyle(.plain)
        .disabled(hasResult)
    }

    private var temptationButton: some View {
        Button(action: onTemptationTap) {
            HStack(spacing: 4) {
                Image(systemName: hasTemptation ? "checkmark" : "bolt.fill")
                    .font(.system(size: 10)).fontWeight(.bold)
                Text(hasTemptation ? "Tentation ✓" : "Tentation →")
                    .font(.appCaption).fontWeight(.semibold)
            }
            .foregroundColor(hasTemptation ? Color.appTextMuted : Color.appOnSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.appSurfaceInset)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(
                        hasTemptation ? Color.appSeparatorSubtle : Color.appDanger.opacity(0.5),
                        lineWidth: 0.5
                    ))
            )
        }
        .buttonStyle(.plain)
        .disabled(hasTemptation)
    }
}
