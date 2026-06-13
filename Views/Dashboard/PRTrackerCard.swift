import SwiftUI

// MARK: - PRTrackerCard

struct PRTrackerCard: View {
    let data: PRTrackerData
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("RECORDS PERSONNELS")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    if data.totalPrs > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill").font(.appMicro.weight(.semibold))
                            Text("\(data.totalPrs) PR")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(Color.appWarning.opacity(0.85))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.appWarning.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.appMicro).foregroundColor(.white.opacity(0.22))
                }

                if data.recentPrs.isEmpty {
                    Text(data.message)
                        .font(.appCaption).foregroundColor(.white.opacity(0.40))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(data.recentPrs.prefix(3), id: \.name) { pr in
                            PRRow(pr: pr)
                        }
                    }
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            PRTrackerDetailSheet(data: data)
        }
    }
}

// MARK: - PR Row

private struct PRRow: View {
    let pr: RecentPR

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.appMicro)
                .foregroundColor(Color.appWarning)
                .frame(width: 14)
            Text(pr.name)
                .font(.appCaption.weight(.medium))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
            Spacer()
            Text(String(format: "%.0f lbs", pr.est1rm))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color.appWarning)
        }
    }
}

// MARK: - Detail Sheet

private struct PRTrackerDetailSheet: View {
    let data: PRTrackerData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    PRSummaryBanner(data: data)
                    if !data.recentPrs.isEmpty {
                        PRListCard(prs: data.recentPrs)
                    }
                    PRExplainerCard(tracked: data.exercisesTracked)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Records Personnels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

private struct PRSummaryBanner: View {
    let data: PRTrackerData

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("RECORDS — 30 DERNIERS JOURS")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text(data.message)
                    .font(.appCaption).foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("\(data.totalPrs)")
                .font(.appCardHero)
                .foregroundColor(data.totalPrs > 0 ? Color.appWarning : .white.opacity(0.30))
        }
        .padding(14)
        .glassCard()
    }
}

private struct PRListCard: View {
    let prs: [RecentPR]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOUVEAUX RECORDS")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            ForEach(prs, id: \.name) { pr in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pr.name)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.80))
                        Text(pr.date)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.30))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f lbs 1RM", pr.est1rm))
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(Color.appWarning)
                        if let prev = pr.prevBest {
                            Text(String(format: "Préc. %.0f", prev))
                                .font(.appMicro)
                                .foregroundColor(.white.opacity(0.28))
                        }
                    }
                }
                .padding(.vertical, 4)
                if pr.name != prs.last?.name {
                    Divider().overlay(Color.white.opacity(0.07))
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct PRExplainerCard: View {
    let tracked: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Un PR est détecté quand le 1RM estimé (Epley) des 30 derniers jours atteint ou dépasse le maximum des 180 derniers jours. \(tracked) exercices suivis.")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
