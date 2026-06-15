import SwiftUI

struct WarRoomStripView: View {
    let hasResult: Bool
    let hasTemptation: Bool
    let onResultTap: () -> Void
    let onTemptationTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.appCaption).fontWeight(.bold)
                    .foregroundColor(Color.appDanger.opacity(0.75))
                Text("War Room")
                    .font(.appCaption).fontWeight(.semibold)
                    .foregroundColor(Color.appOnSurface.opacity(0.6))
            }

            Spacer()

            if hasResult && hasTemptation {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appCaption)
                        .foregroundColor(Color.statusGreen.opacity(0.7))
                    Text("Journée loggée")
                        .font(.appCaption).fontWeight(.medium)
                        .foregroundColor(Color.appOnSurface.opacity(0.45))
                }
            } else {
                resultButton
                Text("·")
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(0.25))
                temptationButton
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color.appCard)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appSurfaceInset, lineWidth: 0.5))
        .cornerRadius(10)
    }

    private var resultButton: some View {
        Button(action: onResultTap) {
            HStack(spacing: 4) {
                Image(systemName: hasResult ? "checkmark" : "flag.fill")
                    .font(.system(size: 10)).fontWeight(.bold)
                Text(hasResult ? "Résultat ✓" : "Résultat →")
                    .font(.appCaption).fontWeight(.semibold)
            }
            .foregroundColor(hasResult ? Color.appOnSurface.opacity(0.3) : .white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(hasResult ? Color.appSurfaceInset : Color(hex: "0a1a0a"))
                    .overlay(Capsule().stroke(
                        hasResult ? Color.appSurfaceInset : Color.statusGreen.opacity(0.5),
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
            .foregroundColor(hasTemptation ? Color.appOnSurface.opacity(0.3) : .white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(hasTemptation ? Color.appSurfaceInset : Color(hex: "1a0505"))
                    .overlay(Capsule().stroke(
                        hasTemptation ? Color.appSurfaceInset : Color.appDanger.opacity(0.6),
                        lineWidth: 0.5
                    ))
            )
        }
        .buttonStyle(.plain)
        .disabled(hasTemptation)
    }
}
