import SwiftUI

// MARK: - SleepHRVCard

struct SleepHRVCard: View {
    let data: SleepHRVData
    @State private var showDetail = false

    private var bestLabel: String {
        switch data.bestBucket {
        case "short":   return "< 7 h"
        case "optimal": return "7–8 h"
        case "long":    return "> 8 h"
        default:        return "—"
        }
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("SOMMEIL × HRV")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    if data.hasData {
                        Text(bestLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.trendPositive.opacity(0.85))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.trendPositive.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.appMicro).foregroundColor(.white.opacity(0.22))
                }

                if data.hasData {
                    SleepHRVBucketBars(buckets: data.buckets, bestBucket: data.bestBucket)
                } else {
                    Text("Pas assez de données")
                        .font(.appCaption).foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            SleepHRVDetailSheet(data: data)
        }
    }
}

// MARK: - Bucket bars

private struct SleepHRVBucketBars: View {
    let buckets: [SleepHRVBucket]
    let bestBucket: String?

    private var maxHRV: Double {
        buckets.compactMap(\.avgHrv).max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(buckets, id: \.bucket) { b in
                let isBest = b.bucket == bestBucket
                let hrv = b.avgHrv ?? 0
                let h = maxHRV > 0 ? max(4.0, 36.0 * hrv / maxHRV) : 4.0
                VStack(spacing: 4) {
                    if let hrv = b.avgHrv {
                        Text("\(Int(hrv))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(isBest ? .white.opacity(0.8) : .white.opacity(0.35))
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isBest ? Color.trendPositive : Color.white.opacity(0.20))
                        .frame(height: h)
                    Text(b.label)
                        .font(.system(size: 8))
                        .foregroundColor(isBest ? .white.opacity(0.55) : .white.opacity(0.25))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 60, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct SleepHRVDetailSheet: View {
    let data: SleepHRVData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SleepHRVBanner(data: data)
                    SleepHRVDetailChart(data: data)
                    SleepHRVExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Sommeil × HRV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct SleepHRVBanner: View {
    let data: SleepHRVData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CORRÉLATION SOMMEIL / HRV")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text(data.message)
                .font(.appCaption).foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(data.sessionsAnalyzed) nuits analysées")
                .font(.appCaption).foregroundColor(.white.opacity(0.35))
        }
        .padding(14)
        .glassCard()
    }
}

private struct SleepHRVDetailChart: View {
    let data: SleepHRVData

    private var maxHRV: Double {
        data.buckets.compactMap(\.avgHrv).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HRV MOYEN PAR DURÉE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(data.buckets, id: \.bucket) { b in
                    let isBest = b.bucket == data.bestBucket
                    let hrv = b.avgHrv ?? 0
                    let h = maxHRV > 0 ? max(12.0, 72.0 * hrv / maxHRV) : 12.0
                    VStack(spacing: 5) {
                        if let avg = b.avgHrv {
                            Text("\(Int(avg)) ms")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(isBest ? .white.opacity(0.85) : .white.opacity(0.40))
                        } else {
                            Text("—")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.25))
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isBest ? Color.trendPositive : Color.white.opacity(0.20))
                            .frame(height: h)
                        Text(b.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(isBest ? .white.opacity(0.65) : .white.opacity(0.30))
                        Text("\(b.count) nuits")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.22))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

private struct SleepHRVExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Les nuits sont regroupées par durée (< 7 h, 7–8 h, > 8 h). Le HRV moyen est calculé pour chaque groupe à partir des 120 derniers jours de recovery logs.")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
