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
        }
    }
    var detail: String? {
        switch state {
        case .pending: "Tes données sont conservées. Vérifie la synchronisation quand la connexion est rétablie."
        case .review: "Le résultat doit être vérifié avant de continuer. Cette vérification ne renvoie pas tes données."
        case .failed: "La séance n’a pas pu être confirmée. Vérifie son état avant de tenter de la terminer à nouveau."
        case .completed: "Tu peux poursuivre l’autre séance de ta journée."
        case .ready, .processing: nil
        }
    }
    var checkTitle: String { state == .pending ? "Vérifier la synchronisation" : "Vérifier l’enregistrement" }
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
