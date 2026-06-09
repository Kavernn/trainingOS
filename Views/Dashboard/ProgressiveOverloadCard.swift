import SwiftUI

// MARK: - ProgressiveOverloadCard

struct ProgressiveOverloadCard: View {
    let data: ProgressiveOverloadData
    @State private var showDetail = false

    private var hasGainers: Bool { !data.topGainers.isEmpty }

    private var summaryColor: Color {
        hasGainers ? Color(hex: "34C759") : Color(hex: "FF9500")
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("SURCHARGE PROGRESSIVE")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: hasGainers ? "arrow.up.right" : "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(data.topGainers.count) exo en +")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(summaryColor.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(summaryColor.opacity(0.12))
                    .clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.appMicro).foregroundColor(.white.opacity(0.22))
                }

                if data.topGainers.isEmpty && data.stalled.isEmpty {
                    Text("Données insuffisantes pour comparer les périodes")
                        .font(.appCaption).foregroundColor(.white.opacity(0.35))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(data.topGainers.prefix(2), id: \.name) { ex in
                            OverloadExerciseRow(exercise: ex, isGainer: true)
                        }
                        if data.topGainers.isEmpty, let first = data.stalled.first {
                            OverloadExerciseRow(exercise: first, isGainer: false)
                        }
                    }
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            ProgressiveOverloadDetailSheet(data: data)
        }
    }
}

// MARK: - Exercise Row

private struct OverloadExerciseRow: View {
    let exercise: OverloadExercise
    let isGainer: Bool

    private var color: Color { isGainer ? Color(hex: "34C759") : Color(hex: "FF9500") }
    private var sign: String { exercise.pct >= 0 ? "+" : "" }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isGainer ? "arrow.up.right" : "minus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 14)
            Text(exercise.name)
                .font(.appCaption.weight(.medium))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
            Spacer()
            Text("\(sign)\(String(format: "%.1f", exercise.pct))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
    }
}

// MARK: - Detail Sheet

private struct ProgressiveOverloadDetailSheet: View {
    let data: ProgressiveOverloadData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    OverloadSummaryBanner(data: data)
                    if !data.topGainers.isEmpty {
                        OverloadSection(title: "EN PROGRESSION", exercises: data.topGainers, isGainer: true)
                    }
                    if !data.stalled.isEmpty {
                        OverloadSection(title: "STAGNATION", exercises: data.stalled, isGainer: false)
                    }
                    OverloadExplainerCard(tracked: data.exercisesTracked)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Surcharge Progressive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct OverloadSummaryBanner: View {
    let data: ProgressiveOverloadData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SURCHARGE PROGRESSIVE — 4 SEM. VS 4 SEM.")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text(data.message)
                .font(.appCaption).foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(data.exercisesTracked) exercices comparés")
                .font(.appCaption).foregroundColor(.white.opacity(0.30))
        }
        .padding(14)
        .glassCard()
    }
}

private struct OverloadSection: View {
    let title: String
    let exercises: [OverloadExercise]
    let isGainer: Bool

    private var accent: Color { isGainer ? Color(hex: "34C759") : Color(hex: "FF9500") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            ForEach(exercises, id: \.name) { ex in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.80))
                        Text("Avant \(Int(ex.prior)) → Maintenant \(Int(ex.recent))")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                    let sign = ex.pct >= 0 ? "+" : ""
                    Text("\(sign)\(String(format: "%.1f", ex.pct))%")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(accent)
                }
                .padding(.vertical, 4)
                if ex.name != exercises.last?.name {
                    Divider().overlay(Color.white.opacity(0.07))
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct OverloadExplainerCard: View {
    let tracked: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Compare l'estimation de 1RM max (formule Epley : poids × (1 + reps/30)) entre les 4 dernières semaines et les 4 précédentes. Nécessite ≥ 2 séances par période. \(tracked) exercices analysés.")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
