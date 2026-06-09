import SwiftUI

// MARK: - BehavioralPRsCard (Dashboard compact)

struct BehavioralPRsCard: View {
    let data: BehavioralPRsData
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            BehavioralPRsDetailSheet(data: data)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("RECORDS COMPORTEMENTAUX")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                if data.activePRs > 0 {
                    Text("\(data.activePRs) actif\(data.activePRs > 1 ? "s" : "")")
                        .font(.appMicro.weight(.black))
                        .foregroundColor(.forge)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.forge.opacity(0.14))
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.22))
            }

            VStack(spacing: 6) {
                ForEach(data.prs, id: \.id) { pr in
                    PRRowCompact(pr: pr)
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Compact PR row

private struct PRRowCompact: View {
    let pr: BehavioralPR

    private var activeColor: Color { pr.isActive ? .forge : .white.opacity(0.28) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: pr.icon)
                .font(.system(size: 12))
                .foregroundColor(pr.isActive ? .forge : .white.opacity(0.35))
                .frame(width: 18)

            Text(pr.label)
                .font(.appCaption)
                .foregroundColor(pr.isActive ? .white.opacity(0.80) : .white.opacity(0.45))
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(pr.formattedValue)
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(activeColor)
                Text("rec: \(pr.formattedBest)")
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.28))
            }

            if pr.isActive {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.forge)
            }
        }
    }
}

// MARK: - Detail Sheet

private struct BehavioralPRsDetailSheet: View {
    let data: BehavioralPRsData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if data.activePRs > 0 {
                        ActivePRsBanner(count: data.activePRs)
                    }
                    ForEach(data.prs, id: \.id) { pr in
                        PRDetailCard(pr: pr)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Records Comportementaux")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Active PRs Banner

private struct ActivePRsBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.appHeadline)
                .foregroundColor(.forge)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) record\(count > 1 ? "s" : "") actif\(count > 1 ? "s" : "")")
                    .font(.appBody.weight(.bold))
                    .foregroundColor(.forge)
                Text("Tu vis en ce moment ton meilleur niveau sur ces dimensions")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.forge.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.forge.opacity(0.22), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - PR Detail Card

private struct PRDetailCard: View {
    let pr: BehavioralPR

    private var accentColor: Color { pr.isActive ? .forge : .white.opacity(0.30) }
    private var progress: Double {
        guard let v = pr.value, pr.bestEver > 0 else { return 0 }
        return min(1.0, v / pr.bestEver)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: pr.icon)
                    .font(.appLabel)
                    .foregroundColor(accentColor)
                    .frame(width: 24)
                Text(pr.label)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(pr.isActive ? .white.opacity(0.90) : .white.opacity(0.55))
                Spacer()
                if pr.isActive {
                    Text("EN VIE")
                        .font(.appMicro.weight(.black)).tracking(1.2)
                        .foregroundColor(.forge)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.forge.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAINTENANT")
                        .font(.appMicro).tracking(0.8)
                        .foregroundColor(.white.opacity(0.28))
                    Text(pr.formattedValue)
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(accentColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("RECORD")
                        .font(.appMicro).tracking(0.8)
                        .foregroundColor(.white.opacity(0.28))
                    Text(pr.formattedBest)
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(.white.opacity(pr.isActive ? 0.90 : 0.50))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentColor.opacity(0.70))
                        .frame(width: geo.size.width * progress, height: 5)
                }
            }
            .frame(height: 5)

            if !pr.setDate.isEmpty {
                Text("Établi le \(pr.setDate)")
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(14)
        .glassCard()
    }
}
