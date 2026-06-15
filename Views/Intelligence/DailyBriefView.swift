import SwiftUI

struct DailyBriefView: View {
    let brief: DailyBrief?
    let isLoading: Bool
    let isStale: Bool
    let activeInsight: DailyInsight?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoading && brief == nil {
                BriefSkeletonView()
            } else if let b = brief {
                motSection(b)
                Divider().background(Color.appSeparator)
                lectureSection(b)
                Divider().background(Color.appSeparator)
                recommandationSection(b)
                if let insight = activeInsight, !insight.isEmpty {
                    Divider().background(Color.appSeparator)
                    signauxSection(insight)
                }
                if isStale {
                    HStack(spacing: 5) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 10))
                        Text("Hors ligne — briefing d'hier")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.appTextSecondary)
                    .padding(.top, 4)
                }
            } else {
                BriefFallbackView()
                if let insight = activeInsight, !insight.isEmpty {
                    Divider().background(Color.appSeparator)
                    signauxSection(insight)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 1. Mot du Jour

    @ViewBuilder
    private func motSection(_ b: DailyBrief) -> some View {
        let quote = QuoteData.today()
        VStack(alignment: .leading, spacing: 8) {
            Text("MOT DU JOUR")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundColor(.statusPurple)

            if b.useQuote {
                Text("« \(quote.text) »")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.appTextPrimary)
                    .lineSpacing(4)
                Text("— \(quote.author) · \(quote.context)")
                    .font(.system(size: 12))
                    .foregroundColor(.appTextSecondary)
            } else if let mot = b.mot {
                Text(mot)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.appTextPrimary)
                    .lineSpacing(4)
                Text("— Coach")
                    .font(.system(size: 12))
                    .foregroundColor(.appTextSecondary)
            }
        }
    }

    // MARK: - 2. Lecture du Jour

    @ViewBuilder
    private func lectureSection(_ b: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LECTURE DU JOUR")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundColor(.statusCyan)

            Text(b.lecture)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color(white: 0.82))
                .lineSpacing(5)
        }
    }

    // MARK: - 3. Recommandation

    @ViewBuilder
    private func recommandationSection(_ b: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECOMMANDATION")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundColor(.statusOrange)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(b.recommandation, id: \.self) { action in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.statusOrange)
                            .padding(.top, 2)
                        Text(action)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.appTextPrimary)
                            .lineSpacing(3)
                    }
                }
            }
        }
    }

    // MARK: - 4. Signaux

    @ViewBuilder
    private func signauxSection(_ insight: DailyInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SIGNAL")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundColor(Color(white: 0.4))

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: insight.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(insightColor(insight))
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appTextPrimary)
                    Text(insight.body)
                        .font(.system(size: 12))
                        .foregroundColor(.appTextSecondary)
                        .lineSpacing(3)
                }
            }
        }
    }

    private func insightColor(_ insight: DailyInsight) -> Color {
        switch insight.type {
        case "alert":      return .statusRed
        case "opportunity": return .statusGreen
        default:           return .statusPurple
        }
    }
}

// MARK: - Skeleton

private struct BriefSkeletonView: View {
    @State private var opacity: Double = 0.05

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBar(height: 10, radius: 4)
                        .frame(width: 110)
                    SkeletonBar(height: 14, radius: 5)
                    SkeletonBar(height: 14, radius: 5)
                        .frame(maxWidth: 240)
                }
            }
        }
    }
}

// MARK: - Fallback (no network, no cache)

private struct BriefFallbackView: View {
    private var quote: DailyQuote { QuoteData.today() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MOT DU JOUR")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundColor(.statusPurple)
            Text("« \(quote.text) »")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.appTextPrimary)
                .lineSpacing(4)
            Text("— \(quote.author) · \(quote.context)")
                .font(.system(size: 12))
                .foregroundColor(.appTextSecondary)
        }
    }
}
