import SwiftUI
import OSLog

private let logger = Logger(subsystem: "TrainingOS", category: "Progression")

struct ProgressionSuggestionsSheet: View {
    let suggestions: [ProgressionSuggestion]
    let sessionName: String          // F1 — titre contextuel
    var onDone: () -> Void

    @State private var applied: Set<String> = []
    @State private var ignored: Set<String> = []
    @State private var applying: String? = nil
    @State private var errorMsg: String? = nil
    @State private var showMaintain = false
    @State private var undoPrev: (name: String, weight: Double)? = nil
    @State private var undoVisible = false
    @State private var undoTimerTask: Task<Void, Never>? = nil

    private var ignoredKey: String { "prog_ignored_\(sessionName)" }

    private var actionable: [ProgressionSuggestion] {
        suggestions.filter { $0.suggestionType != "maintain" }
    }
    private var maintain: [ProgressionSuggestion] {
        suggestions.filter { $0.suggestionType == "maintain" }
    }
    private var hasFatigue: Bool {
        suggestions.contains { $0.fatigueWarning }
    }
    // F9 — "Passer" tant qu'il reste des suggestions non traitées
    private var allHandled: Bool {
        actionable.allSatisfy { applied.contains($0.exerciseName) || ignored.contains($0.exerciseName) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()  // F10
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        // Fatigue banner
                        if hasFatigue {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color.forge)
                                Text("Fatigue globale — charge réduite recommandée")
                                    .font(.appLabel.weight(.semibold))
                                    .foregroundColor(Color.forge)
                            }
                            .padding(12)
                            .background(Color.forge.opacity(0.12))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // Actionable suggestions
                        if !actionable.isEmpty {
                            Text("COACHING")
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                                .padding(.top, 8)

                            ForEach(actionable) { s in
                                SuggestionRow(
                                    suggestion: s,
                                    isApplied: applied.contains(s.exerciseName),
                                    isIgnored: ignored.contains(s.exerciseName),
                                    isApplying: applying == s.exerciseName,
                                    onApply: { apply(s) },
                                    onIgnore: { ignore(s.exerciseName) }
                                )
                            }
                        }

                        // F4 — MAINTENIR compact, masqué par défaut
                        if !maintain.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showMaintain.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("MAINTENIR (\(maintain.count))")
                                        .font(.appCaption.weight(.bold))
                                        .foregroundColor(.gray)
                                    Image(systemName: showMaintain ? "chevron.up" : "chevron.down")
                                        .font(.appMicro.weight(.bold))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)

                            if showMaintain {
                                ForEach(maintain) { s in
                                    MaintainRow(suggestion: s)
                                }
                            }
                        }

                        if let err = errorMsg {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(.statusRed)
                                .padding(.horizontal)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Coaching — \(sessionName)")   // F1
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // W-C4 — leading cancel button to dismiss without applying any suggestion
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { onDone() }
                        .foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(allHandled ? "Terminer" : "Passer") { onDone() }
                        .foregroundColor(allHandled ? .statusCyan : .gray)
                        .fontWeight(allHandled ? .semibold : .regular)
                }
            }
            .overlay(alignment: .bottom) {
                if undoVisible, let info = undoPrev {
                    HStack(spacing: 12) {
                        Text("Progression appliquée ↑")
                            .font(.appLabel)
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        Button("Annuler") { undoApply(info) }
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(.statusCyan)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.appCard)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: undoVisible)
            .onAppear {
                let stored = UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []
                ignored = Set(stored)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func apply(_ s: ProgressionSuggestion) {
        guard let weight = s.suggestedWeight else { return }
        applying = s.exerciseName
        triggerImpact(style: .medium)
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
                    // Show undo toast for 5 seconds
                    undoPrev = (name: s.exerciseName, weight: s.currentWeight ?? weight)
                    undoVisible = true
                    undoTimerTask?.cancel()
                    undoTimerTask = Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        await MainActor.run { undoVisible = false }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    applying = nil
                }
            }
        }
    }

    private func ignore(_ name: String) {
        ignored.insert(name)
        UserDefaults.standard.set(Array(ignored), forKey: ignoredKey)
    }

    private func undoApply(_ info: (name: String, weight: Double)) {
        undoTimerTask?.cancel()
        undoVisible = false
        applied.remove(info.name)
        Task {
            do {
                try await APIService.shared.applyProgression(
                    exerciseName: info.name,
                    suggestedWeight: info.weight,
                    suggestedScheme: nil
                )
            } catch {
                logger.error("undo apply failed for \(info.name): \(error)")
            }
        }
    }
}

// MARK: - Actionable Row

private struct SuggestionRow: View {
    let suggestion: ProgressionSuggestion
    let isApplied: Bool
    let isIgnored: Bool
    let isApplying: Bool
    let onApply: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {  // F3 — hiérarchie verticale claire

            // Ligne 1 : icône + nom
            HStack(spacing: 8) {
                Image(systemName: typeIcon)
                    .font(.system(size: 18, weight: .regular))  // F12 — 18pt regular
                    .foregroundColor(typeColor)
                    .frame(width: 22)
                Text(suggestion.exerciseName)
                    .font(.appBody.weight(.bold))
                    .foregroundColor(.appTextPrimary)
            }

            // Ligne 2 : poids current → suggested (masqué pour rep_progress et maintain)
            if let cur = suggestion.currentWeight, let sug = suggestion.suggestedWeight,
               suggestion.suggestionType != "maintain",
               suggestion.suggestionType != "rep_progress" {
                HStack(spacing: 6) {
                    Text(UnitSettings.shared.format(cur))
                        .font(.appLabel)
                        .foregroundColor(.gray)
                    Image(systemName: "arrow.right")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.gray)
                    Text(UnitSettings.shared.format(sug))
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(typeColor)
                    let delta = sug - cur
                    if delta != 0 {
                        Text(delta > 0 ? "+\(UnitSettings.shared.format(delta))" : UnitSettings.shared.format(delta))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(delta > 0 ? typeColor.opacity(0.7) : .statusRed.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((delta > 0 ? typeColor : Color.statusRed).opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }

            // Ligne 3 : justification courte
            Text(suggestion.reason)
                .font(.system(size: 12))
                .foregroundColor(Color.appOnSurface.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            // Ligne 4 : actions (rep_progress → pas de bouton Appliquer, juste OK)
            if !isApplied && !isIgnored {
                HStack(spacing: 10) {
                    // F8 — bouton Ignorer
                    Button(action: onIgnore) {
                        Text("Ignorer")
                            .font(.appLabel)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.appSurfaceInset)
                            .cornerRadius(10)   // F11
                    }

                    // F7 — "Appliquer" (masqué pour rep_progress — rien à appliquer)
                    if suggestion.suggestionType != "rep_progress" {
                        if isApplying {
                            ProgressView().tint(.statusCyan)
                                .padding(.horizontal, 14)
                        } else {
                            Button(action: onApply) {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark")
                                        .font(.appCaption.weight(.bold))
                                    if let sug = suggestion.suggestedWeight {
                                        Text("Appliquer · \(UnitSettings.shared.format(sug))")
                                            .font(.appLabel.weight(.semibold))
                                    } else {
                                        Text("Appliquer")
                                            .font(.appLabel.weight(.semibold))
                                    }
                                }
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(typeColor)
                                .cornerRadius(10)
                            }
                        }
                    }
                }
            } else if isApplied {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.statusGreen)
                    Text("Appliqué")
                        .font(.appLabel)
                        .foregroundColor(.statusGreen)
                }
            } else {
                Text("Ignoré")
                    .font(.appLabel)
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
        .padding(14)
        .background(Color.appSurfaceInset)  // F13 — 0.07 vs 0.05
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private var typeIcon: String {
        switch suggestion.suggestionType {
        case "increase_weight": return "arrow.up.circle.fill"
        case "increase_sets":   return "plus.circle.fill"
        case "deload":          return "arrow.down.circle.fill"
        case "regression":      return "exclamationmark.circle.fill"
        case "rep_progress":    return "arrow.up.right.circle.fill"
        default:                return "minus.circle"
        }
    }

    private var typeColor: Color {
        switch suggestion.suggestionType {
        case "increase_weight": return .statusCyan
        case "increase_sets":   return .statusGreen
        case "deload":          return .statusOrange
        case "regression":      return .statusRed
        case "rep_progress":    return .statusGreen
        default:                return .gray
        }
    }
}

// MARK: - Compact Maintain Row  (F4)

private struct MaintainRow: View {
    let suggestion: ProgressionSuggestion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.gray)
                .frame(width: 18)
            Text(suggestion.exerciseName)
                .font(.appLabel)
                .foregroundColor(Color.appOnSurface.opacity(0.55))
            Spacer()
            if let w = suggestion.currentWeight {
                Text(UnitSettings.shared.format(w))
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.appSurfaceInset)
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

