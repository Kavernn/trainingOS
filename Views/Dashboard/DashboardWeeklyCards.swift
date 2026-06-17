import SwiftUI

// MARK: - Weekly Report Full View

struct WeeklyReportView: View {
    let report: WeeklyReport
    @ObservedObject private var units = UnitSettings.shared

    private var shareText: String {
        var lines = ["📊 Rapport semaine TrainingOS"]
        lines.append("Séances : \(report.sessionCount)")
        if report.prCount > 0 { lines.append("🏆 Limites détruites : \(report.prCount)") }
        if report.totalVolumeLbs > 0 {
            lines.append("Volume : \(_formatK(units.display(report.totalVolumeLbs))) \(units.label)")
        }
        if let r = report.avgRecoveryScore { lines.append("Récupération moy. : \(String(format: "%.1f", r))/10") }
        if let s = report.avgSleepHours   { lines.append("Sommeil moy. : \(String(format: "%.1f", s))h") }
        if let c = report.nutritionCompliance { lines.append("Compliance nutrition : \(c)%") }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: Color.forge)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 4) {
                        Text("RAPPORT SEMAINE")
                            .font(.appCaption.weight(.bold)).tracking(2)
                            .foregroundColor(.gray)
                        Text("\(report.weekStart) → \(report.weekEnd)")
                            .font(.appLabel.weight(.regular)).foregroundColor(Color.appOnSurface.opacity(0.5))
                    }
                    .padding(.top, 8)

                    // KPI grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        WeeklyKPI(value: "\(report.sessionCount)", label: "Séances", icon: "flame.fill", color: Color.forge)
                        WeeklyKPI(value: "\(report.prCount)", label: "Limites détruites", icon: "trophy.fill", color: .statusYellow)
                        if report.totalVolumeLbs > 0 {
                            WeeklyKPI(value: _formatK(units.display(report.totalVolumeLbs)), label: "Volume (\(units.label))", icon: "scalemass.fill", color: .statusCyan)
                        }
                        if let r = report.avgRecoveryScore {
                            WeeklyKPI(value: String(format: "%.1f/10", r), label: "Récup. moy.", icon: "heart.fill", color: .statusGreen)
                        }
                        if let s = report.avgSleepHours {
                            WeeklyKPI(value: String(format: "%.1fh", s), label: "Sommeil moy.", icon: "moon.fill", color: .statusBlue)
                        }
                        if let steps = report.avgSteps {
                            WeeklyKPI(value: "\(steps / 1000)k", label: "Pas/jour", icon: "figure.walk", color: .statusCyan)
                        }
                        if let hrv = report.avgHrv {
                            WeeklyKPI(value: String(format: "%.0f ms", hrv), label: "HRV moy.", icon: "waveform.path.ecg", color: .statusCyan)
                        }
                        if let c = report.nutritionCompliance {
                            WeeklyKPI(value: "\(c)%", label: "Nutrition", icon: "fork.knife", color: .statusGreen)
                        }
                    }

                    // Weekly score ring
                    if let score = report.weeklyScore {
                        let scoreColor: Color = score >= 75 ? .statusGreen : score >= 50 ? .statusOrange : .appDanger
                        HStack(spacing: 20) {
                            ZStack {
                                Circle().stroke(Color.appSurfaceInset, lineWidth: 8).frame(width: 70, height: 70)
                                Circle()
                                    .trim(from: 0, to: CGFloat(score) / 100)
                                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .frame(width: 70, height: 70)
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 0) {
                                    Text("\(score)").font(.appTitle.weight(.black)).foregroundColor(.appTextPrimary)
                                    Text("/100").font(.appMicro).foregroundColor(.gray)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SCORE SEMAINE").font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.gray)
                                Text(score >= 75 ? "Excellente semaine" : score >= 50 ? "Bonne semaine" : "Semaine à améliorer")
                                    .font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
                                if let rpe = report.avgRpe {
                                    Text("RPE moy. \(String(format: "%.1f", rpe))/10")
                                        .font(.appCaption).foregroundColor(.gray)
                                }
                            }
                            Spacer()
                        }
                        .padding(14)
                        .glassCard(color: scoreColor, intensity: 0.06)
                        .cornerRadius(14)
                    }

                    if let top = report.topExercise {
                        HStack(spacing: 10) {
                            Image(systemName: "star.fill").foregroundColor(.statusYellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("EXERCICE PHARE").font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.gray)
                                Text(top).font(.appLabel.weight(.bold)).foregroundColor(.appTextPrimary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .glassCard(color: .statusYellow, intensity: 0.07)
                        .cornerRadius(14)
                    }

                    // PRs list
                    if !report.prs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("RECORDS PERSONNELS", systemImage: "trophy.fill")
                                .font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.statusYellow)
                            ForEach(report.prs, id: \.self) { exo in
                                HStack(spacing: 8) {
                                    Image(systemName: "star.fill").font(.appCaption).foregroundColor(Color.statusYellow.opacity(0.8))
                                    Text(exo).font(.appLabel).foregroundColor(.appTextPrimary)
                                    Spacer()
                                }
                            }
                        }
                        .padding(14)
                        .glassCard(color: .statusYellow, intensity: 0.05)
                        .cornerRadius(14)
                    }

                    // Focus next week
                    if !report.focusNextWeek.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("FOCUS SEMAINE PROCHAINE", systemImage: "target")
                                .font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.statusPurple)
                            ForEach(Array(report.focusNextWeek.enumerated()), id: \.offset) { _, tip in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.appCaption).foregroundColor(.statusPurple)
                                    Text(tip).font(.appLabel.weight(.regular)).foregroundColor(Color.appOnSurface.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                }
                            }
                        }
                        .padding(14)
                        .glassCard(color: .statusPurple, intensity: 0.05)
                        .cornerRadius(14)
                    }

                    ShareLink(item: shareText) {
                        Label("Partager ce rapport", systemImage: "square.and.arrow.up")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.statusPurple.opacity(0.7))
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Semaine")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WeeklyKPI: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.appHeadline.weight(.regular)).foregroundColor(color)
            Text(value)
                .font(.appHeadline.weight(.black)).foregroundColor(color)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(label)
                .font(.appMicro.weight(.medium)).tracking(1).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard(color: color, intensity: 0.05)
        .cornerRadius(14)
    }
}

