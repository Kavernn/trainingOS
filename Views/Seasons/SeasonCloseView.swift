import SwiftUI
import Combine

struct SeasonCloseView: View {
    let season: Season
    let onSealed: () -> Void

    @State private var step: CloseStep = .capture
    @State private var report: SeasonReport?
    @State private var customTitle = ""
    @State private var personalNote = ""
    @State private var editingTitle = false
    @State private var isSaving = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            switch step {
            case .capture:  captureView
            case .report:   reportStep
            case .title:    titleStep
            case .note:     noteStep
            case .seal:     sealStep
            }
        }
        .animation(.easeInOut(duration: 0.5), value: step)
        .task { await performClose() }
    }

    // MARK: - Capture

    private var captureView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().tint(Color.forge).scaleEffect(1.4)
            Text("Capture de ta saison en cours…")
                .font(.system(size: 14, weight: .light, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .tracking(1)
            Spacer()
        }
    }

    // MARK: - Report

    private var reportStep: some View {
        NavigationStack {
            Group {
                if let r = report {
                    SeasonReportView(report: r)
                } else {
                    ProgressView().tint(Color.forge)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continuer") {
                        if let r = report { customTitle = r.title }
                        withAnimation { step = .title }
                    }
                    .foregroundStyle(Color.forge)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Title reveal

    private var titleStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                if editingTitle {
                    TextField("Titre de la saison", text: $customTitle)
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(arcColor)
                        .padding(.horizontal, 32)
                        .submitLabel(.done)
                        .onSubmit { editingTitle = false }
                } else {
                    Text(customTitle.isEmpty ? report?.title ?? "" : customTitle)
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundStyle(arcColor)
                        .tracking(1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button(editingTitle ? "Valider" : "Changer le titre") {
                    editingTitle.toggle()
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary)
            }
            Spacer()
            Button("Continuer") {
                withAnimation { step = .note }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color.appCard, in: Capsule())
            .padding(.bottom, 52)
        }
    }

    // MARK: - Personal note

    private var noteStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Text("Un mot pour toi-même dans 2 ans.")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)

                ZStack(alignment: .topLeading) {
                    if personalNote.isEmpty {
                        Text("Optionnel…")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .padding(.horizontal, 4).padding(.top, 8)
                    }
                    TextEditor(text: $personalNote)
                        .font(.system(size: 16, weight: .light))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, maxHeight: 160)
                        .tint(Color.forge)
                        .onChange(of: personalNote) { _, v in
                            if v.count > 280 { personalNote = String(v.prefix(280)) }
                        }
                }
                .padding(.horizontal, 32)

                Text("\(personalNote.count)/280")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            Spacer()
            Button("Sceller cette saison") {
                withAnimation { step = .seal }
                Task { await saveSeal() }
            }
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.primary)
            .tracking(2)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color.forge.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.forge.opacity(0.4), lineWidth: 1))
            .padding(.bottom, 52)
        }
    }

    // MARK: - Seal

    private var sealStep: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(arcColor)
            VStack(spacing: 8) {
                Text("SCELLÉE")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(arcColor)
                    .tracking(4)
                Text(customTitle.isEmpty ? report?.title ?? "" : customTitle)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Button("Fermer") { onSealed() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.appCard, in: Capsule())
                .padding(.bottom, 52)
        }
    }

    // MARK: - Actions

    private func performClose() async {
        let r = try? await APIService.shared.closeSeason(id: season.id)
        await MainActor.run {
            report = r
            if let r { customTitle = r.title }
            withAnimation { step = .report }
        }
    }

    private func saveSeal() async {
        guard let r = report else { return }
        isSaving = true
        var fields: [String: Any] = [:]
        let finalTitle = customTitle.trimmingCharacters(in: .whitespaces)
        if !finalTitle.isEmpty && finalTitle != r.title {
            fields["custom_title"] = finalTitle
        }
        if !personalNote.trimmingCharacters(in: .whitespaces).isEmpty {
            fields["personal_note"] = personalNote
        }
        if !fields.isEmpty {
            _ = try? await APIService.shared.updateSeason(id: r.season.id, fields: fields)
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        isSaving = false
    }

    private var arcColor: Color {
        switch report?.arc {
        case "rebirth":      return .purple
        case "comeback":     return Color.forge
        case "war":          return .red
        case "breakthrough": return .yellow
        case "ascent":       return .green
        case "descent":      return Color.red.opacity(0.7)
        case "plateau":      return .secondary
        default:             return .blue
        }
    }
}

private enum CloseStep { case capture, report, title, note, seal }
