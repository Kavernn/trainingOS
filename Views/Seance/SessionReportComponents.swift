import SwiftUI

// MARK: - Session Completion Hero

struct SessionCompletionHero: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let factualSummary: String?

    init(
        eyebrow: String = "COMPLETE",
        title: String,
        subtitle: String? = nil,
        factualSummary: String? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.factualSummary = factualSummary
    }

    private var accent: Color { Color.domainAccent(.training) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.appLabel.weight(.bold))
                    .foregroundColor(accent)

                Text(eyebrow)
                    .font(.appMicro.weight(.bold))
                    .tracking(1.6)
                    .foregroundColor(accent)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.appCardMetric)
                    .fontWeight(.heavy)
                    .foregroundColor(Color.appTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.appLabel)
                        .foregroundColor(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let factualSummary, !factualSummary.isEmpty {
                Divider()
                    .background(Color.appSeparatorSubtle)

                Text(factualSummary)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(Color.appTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, .appCardInsetH)
        .padding(.vertical, .appCardInsetV)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: .appCardRadius)
                .stroke(Color.appSeparator, lineWidth: .appHairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Session Scoreboard

struct SessionReportMetric: View {
    enum Emphasis: Equatable {
        case standard
        case primary
    }

    let label: String
    let value: String
    let emphasis: Emphasis

    init(label: String, value: String, emphasis: Emphasis = .standard) {
        self.label = label
        self.value = value
        self.emphasis = emphasis
    }

    private var accent: Color { Color.domainAccent(.training) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(emphasis == .primary ? .appCardMetric : .appHeadline)
                .fontWeight(.bold)
                .foregroundColor(emphasis == .primary ? accent : Color.appTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()

            Text(label)
                .font(.appMicro.weight(.semibold))
                .tracking(1)
                .foregroundColor(Color.appTextSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SessionScoreboard: View {
    let metrics: [SessionReportMetric]

    init(metrics: [SessionReportMetric]) {
        self.metrics = metrics
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                metric
                    .padding(.horizontal, .appCardInsetH)

                if index < metrics.count - 1 {
                    Rectangle()
                        .fill(Color.appSeparatorStrong)
                        .frame(width: .appHairline)
                }
            }
        }
        .padding(.vertical, .appCardInsetV)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: .appCardRadius)
                .stroke(Color.appSeparator, lineWidth: .appHairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
    }
}

// MARK: - Session Report Section Header

struct SessionReportSectionHeader: View {
    let title: String
    let accessory: String?

    init(title: String, accessory: String? = nil) {
        self.title = title
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.appMicro.weight(.bold))
                .tracking(1.6)
                .foregroundColor(Color.appTextSecondary)

            Spacer(minLength: 0)

            if let accessory, !accessory.isEmpty {
                Text(accessory)
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.appTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Session completion hero — short") {
    SessionCompletionHero(
        title: "Push A",
        subtitle: "Mardi 8 septembre",
        factualSummary: "6 exercices réalisés"
    )
    .padding(.appPagePadding)
    .background(Color.appBg)
}

#Preview("Session completion hero — long") {
    SessionCompletionHero(
        title: "Pull B + Full Body — séance du soir",
        subtitle: "Programme Force · Semaine 4",
        factualSummary: "8 exercices réalisés sur 9 prévus"
    )
    .padding(.appPagePadding)
    .background(Color.appBg)
}

#Preview("Session scoreboard — 1 metric") {
    SessionScoreboard(metrics: [
        SessionReportMetric(label: "VOLUME", value: "4,2 t", emphasis: .primary)
    ])
    .padding(.appPagePadding)
    .background(Color.appBg)
}

#Preview("Session scoreboard — 2 metrics") {
    SessionScoreboard(metrics: [
        SessionReportMetric(label: "DURÉE", value: "52 min", emphasis: .primary),
        SessionReportMetric(label: "RPE", value: "8,0")
    ])
    .padding(.appPagePadding)
    .background(Color.appBg)
}

#Preview("Session scoreboard — 3 metrics") {
    SessionScoreboard(metrics: [
        SessionReportMetric(label: "DURÉE", value: "52 min"),
        SessionReportMetric(label: "VOLUME", value: "4,2 t", emphasis: .primary),
        SessionReportMetric(label: "RPE", value: "8,0")
    ])
    .padding(.appPagePadding)
    .background(Color.appBg)
}
