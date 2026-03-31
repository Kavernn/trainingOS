import SwiftUI

struct ProgressionSuggestionsSheet: View {
    let suggestions: [ProgressionSuggestion]
    var onDone: () -> Void

    @State private var applied: Set<String> = []
    @State private var applying: String? = nil
    @State private var errorMsg: String? = nil

    private var actionable: [ProgressionSuggestion] {
        suggestions.filter { $0.suggestionType != "maintain" }
    }
    private var maintain: [ProgressionSuggestion] {
        suggestions.filter { $0.suggestionType == "maintain" }
    }
    private var hasFatigue: Bool {
        suggestions.contains { $0.fatigueWarning }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        if hasFatigue {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Fatigue globale détectée — charge réduite recommandée")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }

                        if !actionable.isEmpty {
                            Text("PROGRESSIONS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                                .padding(.top, 8)

                            ForEach(actionable) { s in
                                SuggestionRow(
                                    suggestion: s,
                                    isApplied: applied.contains(s.exerciseName),
                                    isApplying: applying == s.exerciseName,
                                    onApply: { apply(s) }
                                )
                            }
                        }

                        if !maintain.isEmpty {
                            Text("MAINTENIR")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                                .padding(.top, 4)

                            ForEach(maintain) { s in
                                SuggestionRow(
                                    suggestion: s,
                                    isApplied: false,
                                    isApplying: false,
                                    onApply: nil
                                )
                            }
                        }

                        if let err = errorMsg {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminer") { onDone() }
                        .foregroundColor(.cyan)
                }
            }
        }
    }

    private func apply(_ s: ProgressionSuggestion) {
        guard let weight = s.suggestedWeight else { return }
        applying = s.exerciseName
        Task {
            do {
                try await APIService.shared.applyProgression(
                    exerciseName: s.exerciseName,
                    suggestedWeight: weight,
                    suggestedScheme: s.suggestedScheme
                )
                await MainActor.run {
                    applied.insert(s.exerciseName)
                    applying = nil
                }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    applying = nil
                }
            }
        }
    }
}

// MARK: - Row

private struct SuggestionRow: View {
    let suggestion: ProgressionSuggestion
    let isApplied: Bool
    let isApplying: Bool
    let onApply: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Type icon
            Image(systemName: typeIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(typeColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.exerciseName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Text(suggestion.reason)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)

                if let cur = suggestion.currentWeight, let sug = suggestion.suggestedWeight,
                   suggestion.suggestionType != "maintain" {
                    HStack(spacing: 4) {
                        Text("\(cur.formatted()) kg")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text("\(sug.formatted()) kg")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(typeColor)
                    }
                }
            }

            Spacer()

            if let onApply = onApply {
                if isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                } else if isApplying {
                    ProgressView()
                        .tint(.cyan)
                } else {
                    Button(action: onApply) {
                        Text("OK")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(typeColor)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var typeIcon: String {
        switch suggestion.suggestionType {
        case "increase_weight": return "arrow.up.circle.fill"
        case "increase_sets":   return "plus.circle.fill"
        case "deload":          return "arrow.down.circle.fill"
        case "regression":      return "exclamationmark.circle.fill"
        default:                return "minus.circle"
        }
    }

    private var typeColor: Color {
        switch suggestion.suggestionType {
        case "increase_weight": return .cyan
        case "increase_sets":   return .green
        case "deload":          return .orange
        case "regression":      return .red
        default:                return .gray
        }
    }
}

extension Double {
    func formatted() -> String {
        self.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(self))
            : String(format: "%.1f", self)
    }
}
