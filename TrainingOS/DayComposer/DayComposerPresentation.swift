import SwiftUI

/// Shared presentation only; source identity and completion remain coordinator-owned.
struct DayComposerSourceChip: View {
    let source: DayComposerSource
    var body: some View {
        Label(source.title, systemImage: source == .morning ? "sun.max" : "moon")
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.appSurfaceInset, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(source.title)
    }
}

@MainActor
struct DayComposerFinishPresentation {
    let state: DayComposerFinishCoordinator.ProductState
    var symbol: String {
        switch state {
        case .ready: "circle"
        case .processing: "arrow.triangle.2.circlepath"
        case .pending: "clock"
        case .review: "info.circle"
        case .failed: "exclamationmark.circle"
        case .completed: "checkmark.circle.fill"
        case .setAside: "minus.circle"
        }
    }
    var title: String {
        switch state {
        case .ready: "Séance à terminer"
        case .processing: "Finalisation en cours…"
        case .pending: "En attente de synchronisation"
        case .review: "Vérification requise"
        case .failed: "Enregistrement non confirmé"
        case .completed: "Séance terminée"
        case .setAside: "Mise de côté aujourd’hui"
        }
    }
    var detail: String? {
        switch state {
        case .pending: "Tes données sont conservées. Vérifie la synchronisation quand la connexion est rétablie."
        case .review: "Le résultat doit être vérifié avant de continuer. Cette vérification ne renvoie pas tes données."
        case .failed: "La séance n’a pas pu être confirmée. Vérifie son état avant de tenter de la terminer à nouveau."
        case .completed: "Tu peux poursuivre l’autre séance de ta journée."
        case .setAside: "Tous ses exercices sont mis de côté : rien ne sera enregistré pour cette séance."
        case .ready, .processing: nil
        }
    }
    var checkTitle: String { state == .pending ? "Vérifier la synchronisation" : "Vérifier l’enregistrement" }
}

/// Libellé du verrouillage des créneaux : la cause précise, par séance.
enum DayComposerLockPresentation {
    static func message(for cause: DayComposerLockCause) -> String {
        switch cause {
        case .completed(let s): "Créneaux figés : séance du \(s.title) terminée."
        case .finalizing(let s): "Créneaux figés : finalisation en cours (\(s.title))."
        case .launched: "Créneaux figés : Ma journée a déjà été lancée aujourd’hui."
        case .exerciseEntry(let s, let exercise): "Créneaux figés : saisie existante sur « \(exercise) » (\(s.title))."
        case .sessionEntry(let s): "Créneaux figés : saisie de séance existante (\(s.title))."
        case .started(let s): "Créneaux figés : séance du \(s.title) commencée (chronomètre démarré)."
        case .logged: "Créneaux figés : un exercice est déjà enregistré aujourd’hui."
        case .unreadable: "Créneaux figés : état local illisible, verrouillé par sécurité."
        }
    }
}

/// Libellés de la mise de côté — source unique pour l'exécution et la préparation.
enum DayComposerSetAsidePresentation {
    static func toggleTitle(isSetAside: Bool) -> String {
        isSetAside ? "Annuler la mise de côté" : "Mettre de côté aujourd’hui"
    }
    static let confirmationTitle = "Cet exercice contient une saisie non enregistrée. La mettre de côté l’efface."
    static let confirmationAction = "Effacer la saisie et mettre de côté"
    static let lockedPreparationHint = "Tu pourras mettre un exercice de côté pendant la séance."

    static func message(for refusal: DayComposerExecutionCoordinator.SetAsideRefusal) -> String {
        switch refusal {
        case .logged: "Déjà enregistré — impossible de le mettre de côté."
        case .pendingEdits: "Enregistrement en cours… réessaie dans un instant."
        case .lastUnitOfDay: "Garde au moins un exercice pour la journée."
        case .busy: "Finalisation en cours… réessaie dans un instant."
        case .sourceFinished: "Cette séance est terminée ou en cours de finalisation."
        case .locked: "La journée a changé. Tes données sont conservées."
        case .persistence: "Impossible d’enregistrer sur cet appareil. Réessaie."
        case .invalidUnit, .draftRequiresConfirmation: "Action impossible pour cet exercice."
        }
    }
}

struct DayComposerRPEChoices: View {
    let source: DayComposerSource
    @Binding var selection: Int?
    var body: some View {
        Section {
            DayComposerSourceChip(source: source)
            Text("À quel point cette séance a-t-elle été exigeante ?")
                .font(.appHeadline).foregroundStyle(Color.appTextPrimary)
            Text("Évalue l’ensemble de la séance, pas seulement le dernier exercice.")
                .font(.appCaption).foregroundStyle(Color.appTextSecondary)
            ForEach(6...10, id: \.self) { value in
                Button { selection = value } label: {
                    HStack {
                        Text("\(value)").font(.appHeadline).foregroundStyle(Color.appTextPrimary)
                        Text("sur 10").font(.appCaption).foregroundStyle(Color.appTextSecondary)
                        Spacer()
                        Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection == value ? Color.forge : Color.appTextSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("RPE \(value) sur 10, séance \(source.title)")
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .listRowBackground(Color.appCard)
        .tint(Color.forge)
    }
}

struct DayComposerCompletedSummary: View {
    let leave: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Journée terminée", systemImage: "checkmark.circle.fill")
                .font(.appHeadline).accessibilityAddTraits(.isHeader)
            ForEach([DayComposerSource.morning, .evening], id: \.self) { source in
                HStack {
                    DayComposerSourceChip(source: source)
                    Label("Terminée", systemImage: "checkmark.circle")
                }.accessibilityElement(children: .combine)
            }
            Button("Retour au Programme", action: leave)
                .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
        }.foregroundStyle(Color.appTextPrimary).tint(Color.forge)
    }
}

struct DayComposerFinishStatus: View {
    let source: DayComposerSource
    let state: DayComposerFinishCoordinator.ProductState
    var body: some View {
        let copy = DayComposerFinishPresentation(state: state)
        VStack(alignment: .leading, spacing: 6) {
            DayComposerSourceChip(source: source)
            Label(copy.title, systemImage: copy.symbol).font(.appHeadline)
            if state == .processing { ProgressView("Finalisation de \(source.title)…") }
            if let detail = copy.detail {
                Text(detail).font(.appCaption).foregroundStyle(Color.appTextSecondary)
            }
        }.foregroundStyle(Color.appTextPrimary)
    }
}
