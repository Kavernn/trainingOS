import SwiftUI
import OSLog

private let logger = Logger(subsystem: "TrainingOS", category: "Progression")

struct ProgressionSuggestionsSheet: View {
    let suggestions: [ProgressionSuggestion]
    let context: ProgressionContext
    private var sessionName: String { context.sessionName }
    var onDone: () -> Void

    @StateObject private var rows = ProgressionRows()
    @State private var ignored: Set<String> = []
    @State private var showMaintain = false

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
        actionable.allSatisfy { rows.state($0) == .confirmed || rows.state($0) == .queued || rows.state($0) == .restored || ignored.contains($0.identity) }
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
                                    isApplied: rows.state(s) == .confirmed,
                                    isIgnored: ignored.contains(s.identity),
                                    isApplying: rows.state(s) == .applying,
                                    state: rows.state(s),
                                    canUndo: rows.canUndo(s),
                                    onUndo: { Task { await rows.undo(s, send: { await APIService.shared.applyProgression($0) }) } },
                                    onApply: { apply(s) },
                                    onIgnore: { ignore(s) }
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
            .onAppear {
                ignored = Set(suggestions.filter { UserDefaults.standard.bool(forKey: context.ignoreKey(for: $0)) }.map(\.identity))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func apply(_ suggestion: ProgressionSuggestion) {
        Task { await rows.apply(suggestion, context: context, send: { await APIService.shared.applyProgression($0) }) }
    }

    private func ignore(_ suggestion: ProgressionSuggestion) {
        guard rows.state(suggestion) != .applying, rows.state(suggestion) != .queued else { return }
        ignored.insert(suggestion.identity)
        UserDefaults.standard.set(true, forKey: context.ignoreKey(for: suggestion))
    }
}

// MARK: - Actionable Row

private struct SuggestionRow: View {
    let suggestion: ProgressionSuggestion
    let isApplied: Bool
    let isIgnored: Bool
    let isApplying: Bool
    let state: ProgressionRows.State
    let canUndo: Bool
    let onUndo: () -> Void
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
                            .foregroundColor(delta > 0 ? typeColor.opacity(0.7) : Color.statusRed.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((delta > 0 ? typeColor : Color.statusRed).opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }

            if let target = suggestion.suggestedScheme, target != suggestion.currentScheme {
                Text("Schéma : \(suggestion.currentScheme ?? "—") → \(target)")
                    .font(.appLabel).foregroundColor(.appTextPrimary)
            }

            // Ligne 3 : justification courte
            Text(suggestion.reason)
                .font(.system(size: 12))
                .foregroundColor(Color.appOnSurface.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            // Ligne 4 : actions (rep_progress → pas de bouton Appliquer, juste OK)
            if state == .queued {
                Text("En attente de synchronisation — recharge la séance après synchronisation.")
                    .font(.appLabel).foregroundColor(.statusOrange)
            } else if state == .conflict {
                Text("Recommandation devenue obsolète. Ferme puis recharge les suggestions.")
                    .font(.appLabel).foregroundColor(.statusOrange)
            } else if !isApplied && !isIgnored {
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
                    if suggestion.canApply && !canUndo && state != .restored {
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
                .disabled(isApplying)
            } else if isApplied {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.statusGreen)
                    Text("Appliqué")
                        .font(.appLabel)
                        .foregroundColor(.statusGreen)
                    if canUndo { Button("Annuler", action: onUndo).font(.appLabel) }
                }
            } else {
                Text("Ignoré")
                    .font(.appLabel)
                    .foregroundColor(.gray.opacity(0.6))
            }
            if case .failed(let message) = state {
                Text(message).font(.appLabel).foregroundColor(.statusRed)
                if canUndo { Button("Réessayer l’annulation", action: onUndo).font(.appLabel) }
            }
            if state == .restored { Text("Charge et schéma restaurés").font(.appLabel).foregroundColor(.statusGreen) }
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

