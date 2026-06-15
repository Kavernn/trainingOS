import SwiftUI

struct ProgramPreviewSheet: View {
    let program: GeneratedProgram
    var onApprove: (String) -> Void
    var onReject:  () -> Void

    @State private var selectedWeek   = 0
    @State private var expandedDays:  Set<Int> = [1]
    @State private var isApproving    = false
    @State private var approveError:  String?  = nil
    @State private var approveSuccess = false

    private var content: ProgramContent { program.programJson }

    private var phaseColors: [String: Color] {[
        "accumulation":   .statusBlue,
        "intensification": Color.forge,
        "peak":           .statusRed,
        "deload":         .statusGreen
    ]}
    private let phaseLabels: [String: String] = [
        "accumulation":    "Accumulation",
        "intensification": "Intensification",
        "peak":            "Peak",
        "deload":          "Deload"
    ]

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.name)
                            .font(.appHeadline.weight(.bold))
                            .foregroundColor(.appTextPrimary)
                        Text("4 semaines · 5 jours/semaine · Hypertrophie")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: onReject) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(content.weeks) { week in
                            let phase = week.phase
                            let color = phaseColors[phase] ?? .statusPurple
                            let label = phaseLabels[phase] ?? phase.capitalized
                            Button {
                                withAnimation(.spring(response: 0.3)) { selectedWeek = week.week - 1 }
                            } label: {
                                VStack(spacing: 3) {
                                    Text("S\(week.week)")
                                        .font(.appLabel.weight(.bold))
                                    Text(label)
                                        .font(.appMicro.weight(.medium))
                                        .tracking(0.5)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedWeek == week.week - 1 ? color.opacity(0.25) : Color.appSurfaceInset)
                                .foregroundColor(selectedWeek == week.week - 1 ? color : .gray)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                    selectedWeek == week.week - 1 ? color.opacity(0.6) : Color.clear, lineWidth: 1))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 10)

                if !content.muscleVolume.isEmpty {
                    muscleVolumeRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }

                Divider().background(Color.appSeparator)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        if selectedWeek < content.weeks.count {
                            let week = content.weeks[selectedWeek]
                            ForEach(week.days) { day in
                                DayCard(
                                    day: day,
                                    isExpanded: expandedDays.contains(day.day),
                                    weekPhase: week.phase
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        if expandedDays.contains(day.day) {
                                            expandedDays.remove(day.day)
                                        } else {
                                            expandedDays.insert(day.day)
                                        }
                                    }
                                }
                            }

                            if !content.globalRationale.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Justification", systemImage: "lightbulb.fill")
                                        .font(.appCaption.weight(.bold))
                                        .foregroundColor(.statusBlue)
                                    Text(content.globalRationale)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.statusBlue.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.statusBlue.opacity(0.2), lineWidth: 1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 100)
                }

                Spacer(minLength: 0)
            }

            VStack {
                Spacer()
                VStack(spacing: 8) {
                    if let err = approveError {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(Color.forge)
                            .multilineTextAlignment(.center)
                    }
                    if approveSuccess {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.statusGreen)
                            Text("Programme ajouté dans Programme !")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appTextPrimary)
                        }
                        .padding(.vertical, 10)
                    } else {
                        HStack(spacing: 12) {
                            Button(action: onReject) {
                                Text("Rejeter")
                                    .font(.appBody.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.appSurfaceInset)
                                    .foregroundColor(.gray)
                                    .cornerRadius(14)
                            }
                            Button {
                                approve()
                            } label: {
                                HStack(spacing: 8) {
                                    if isApproving {
                                        ProgressView().tint(.onAccent).scaleEffect(0.85)
                                    } else {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(isApproving ? "Activation..." : "Approuver")
                                        .font(.appBody.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(colors: [.statusBlue, .statusPurple],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .foregroundColor(.appTextPrimary)
                                .cornerRadius(14)
                            }
                            .disabled(isApproving)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    Color.appBg
                        .shadow(color: .black.opacity(0.5), radius: 20, y: -8)
                )
            }
        }
    }

    private var muscleVolumeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VOLUME PAR MUSCLE")
                .font(.appMicro.weight(.bold))
                .tracking(1.5)
                .foregroundColor(.gray)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(content.muscleVolume.sorted(by: { $0.value.setsPerWeek > $1.value.setsPerWeek }), id: \.key) { muscle, vol in
                        let inRange = vol.setsPerWeek >= 10 && vol.setsPerWeek <= 20
                        VStack(spacing: 2) {
                            Text("\(vol.setsPerWeek)")
                                .font(.appLabel.weight(.black))
                                .foregroundColor(inRange ? .statusGreen : .statusOrange)
                            Text(muscle.prefix(6))
                                .font(.appMicro)
                                .foregroundColor(.gray)
                            Text("\(vol.frequency)×/sem")
                                .font(.system(size: 8))
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(inRange ? Color.statusGreen.opacity(0.08) : Color.statusOrange.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                            inRange ? Color.statusGreen.opacity(0.3) : Color.statusOrange.opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private func approve() {
        isApproving  = true
        approveError = nil
        Task {
            do {
                let pid = try await APIService.shared.approveGeneratedProgram(program)
                await MainActor.run {
                    isApproving    = false
                    approveSuccess = true
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { onApprove(pid) }
            } catch {
                await MainActor.run {
                    isApproving  = false
                    approveError = error.localizedDescription
                }
            }
        }
    }
}

private struct DayCard: View {
    let day:       ProgramDay
    let isExpanded: Bool
    let weekPhase:  String
    let onTap:     () -> Void

    private let categoryIcons: [String: String] = [
        "compound_heavy":       "bolt.fill",
        "compound_hypertrophy": "flame.fill",
        "isolation":            "circle.fill"
    ]
    private var categoryColors: [String: Color] {[
        "compound_heavy":       .statusRed,
        "compound_hypertrophy": Color.forge,
        "isolation":            .statusBlue
    ]}

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.statusBlue.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Text("\(day.day)")
                            .font(.appLabel.weight(.black))
                            .foregroundColor(.statusBlue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.appTextPrimary)
                        Text(day.muscleFocus.joined(separator: " · "))
                            .font(.appCaption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(day.exercises.count) exo")
                            .font(.appCaption)
                            .foregroundColor(.gray)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(Color.appSeparator)
                VStack(spacing: 0) {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { idx, ex in
                        ProgramExerciseRow(exercise: ex,
                                       categoryIcons: categoryIcons,
                                       categoryColors: categoryColors)
                        if idx < day.exercises.count - 1 {
                            Divider()
                                .background(Color.appSurfaceInset)
                                .padding(.leading, 44)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.appBg)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.statusBlue.opacity(0.15), lineWidth: 1))
        .cornerRadius(14)
    }
}

private struct ProgramExerciseRow: View {
    let exercise:       ProgramExercise
    let categoryIcons:  [String: String]
    let categoryColors: [String: Color]

    @State private var showRationale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: categoryIcons[exercise.category] ?? "dumbbell.fill")
                    .font(.system(size: 10))
                    .foregroundColor(categoryColors[exercise.category] ?? .statusPurple)
                    .frame(width: 24, height: 24)
                    .background((categoryColors[exercise.category] ?? .statusPurple).opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(exercise.name)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.appTextPrimary)
                    Text(exercise.muscleGroup)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(exercise.sets)×\(exercise.reps)")
                        .font(.appLabel.weight(.black))
                        .foregroundColor(.appTextPrimary)
                    if let rest = exercise.restSec {
                        Text("\(rest / 60)'\(rest % 60 == 0 ? "" : "\(rest % 60)\"")")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.25)) { showRationale.toggle() }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(showRationale ? .statusBlue : .gray.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showRationale {
                Text(exercise.rationale)
                    .font(.appCaption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 8)
            }
        }
    }
}
