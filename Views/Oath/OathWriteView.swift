import SwiftUI

// MARK: - Write / Seal flow

struct OathWriteView: View {
    let existingOath: OathModel?
    let onDone: () -> Void

    @State private var step: OathWriteStep = .intro
    @State private var oathText = ""
    @State private var sealed: OathModel?
    @State private var isSaving = false

    private var wordCount: Int { oathText.split(separator: " ").count }
    private var isRewrite: Bool { existingOath != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch step {
            case .intro:    introView
            case .writing:  writingView
            case .sealing:  sealingView
            case .done:     doneView
            }
        }
        .animation(.easeInOut(duration: 0.5), value: step)
        .preferredColorScheme(.dark)
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                if isRewrite, let old = existingOath {
                    VStack(spacing: 20) {
                        Text("TON SERMENT ACTUEL")
                            .font(.system(size: 10, weight: .light, design: .monospaced))
                            .foregroundStyle(.appOnSurface.opacity(0.3))
                            .tracking(4)
                        Text("\u{201C}\(old.text)\u{201D}")
                            .font(.system(size: 16, weight: .light, design: .serif))
                            .foregroundStyle(.appOnSurface.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .padding(.horizontal, 32)
                    }
                    Divider()
                        .background(.appOnSurface.opacity(0.1))
                        .padding(.horizontal, 40)
                    Text("Réécrire un serment est un acte grave.\nChaque version est archivée.")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(.appOnSurface.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    Image(systemName: "seal")
                        .font(.system(size: 52, weight: .ultraLight))
                        .foregroundStyle(.appOnSurface.opacity(0.3))
                    VStack(spacing: 12) {
                        Text("Un serment définit qui tu deviens.")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(.appOnSurface.opacity(0.8))
                        Text("Ces mots n'appartiennent qu'à toi.\nIls ne seront jamais partagés.")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.appOnSurface.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack {
                Button("Annuler") { onDone() }
                    .font(.system(size: 14))
                    .foregroundStyle(.appOnSurface.opacity(0.3))
                Spacer()
                Button(isRewrite ? "Réécrire" : "Continuer") {
                    withAnimation { step = .writing }
                }
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.appOnSurface.opacity(0.8))
                .tracking(1)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }

    // MARK: - Writing

    private var writingView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation { step = .intro }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.appOnSurface.opacity(0.4))
                        .font(.system(size: 16))
                }
                Spacer()
                Text("\(wordCount) mot\(wordCount != 1 ? "s" : "")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.appOnSurface.opacity(wordCount >= 10 ? 0.5 : 0.25))
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 20)

            ZStack(alignment: .topLeading) {
                if oathText.isEmpty {
                    Text("Écris ton serment ici…")
                        .font(.system(size: 18, weight: .light, design: .serif))
                        .foregroundStyle(.appOnSurface.opacity(0.2))
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                }
                TextEditor(text: $oathText)
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .foregroundStyle(Color.appTextPrimary)                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .lineSpacing(5)
                    .tint(.appOnSurface.opacity(0.6))
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                withAnimation { step = .sealing }
                Task { await performSeal() }
            } label: {
                Text("SCELLER")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(wordCount >= 10 ? .black : .appOnSurface.opacity(0.2))
                    .tracking(3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(wordCount >= 10 ? .white : .appOnSurface.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 2))
            }
            .disabled(wordCount < 10 || isSaving)
            .padding(.horizontal, 24)
            .padding(.bottom, 52)
        }
    }

    // MARK: - Sealing

    private var sealingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SealingAnimationView()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 32) {
                Image(systemName: "seal.fill")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(.appOnSurface.opacity(0.6))

                if let s = sealed {
                    Text("\u{201C}\(s.text)\u{201D}")
                        .font(.system(size: 18, weight: .light, design: .serif))
                        .foregroundStyle(Color.appTextPrimary)                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 32)
                }

                Text("Scellé.")
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .foregroundStyle(.appOnSurface.opacity(0.4))
                    .tracking(4)
            }
            Spacer()
            Button {
                onDone()
            } label: {
                Text("Je suis prêt")
                    .font(.system(size: 14, weight: .light, design: .monospaced))
                    .foregroundStyle(.appOnSurface.opacity(0.7))
                    .tracking(2)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(.appOnSurface.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .padding(.bottom, 60)
        }
    }

    // MARK: - Save

    private func performSeal() async {
        isSaving = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let result = try? await APIService.shared.saveOath(text: oathText, wordCount: wordCount)
        await MainActor.run {
            sealed  = result
            isSaving = false
            withAnimation(.easeInOut(duration: 0.6).delay(1.2)) { step = .done }
        }
    }
}

// MARK: - Sealing animation

private struct SealingAnimationView: View {
    @State private var flash = false
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color(white: flash ? 1 : 0).ignoresSafeArea()
            Image(systemName: "seal.fill")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(flash ? Color.black : Color.white)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                opacity = 1
                scale   = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.15)) { flash = true }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.3)) { flash = false }
                }
            }
        }
    }
}

// MARK: - Steps

enum OathWriteStep {
    case intro, writing, sealing, done
}
