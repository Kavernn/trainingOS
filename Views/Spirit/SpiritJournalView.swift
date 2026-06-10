import SwiftUI
import LocalAuthentication

// MARK: - Biometric gate

struct SpiritJournalGateView: View {
    @ObservedObject var vm: SpiritViewModel
    @State private var unlocked  = false
    @State private var failed    = false
    @State private var pulse     = false

    var body: some View {
        ZStack {
            Color.voidBg.ignoresSafeArea()

            if unlocked {
                SpiritJournalView(vm: vm)
                    .transition(.opacity)
            } else {
                lockScreen
            }
        }
        .animation(.easeInOut(duration: 0.5), value: unlocked)
        .onAppear { authenticate() }
    }

    private var lockScreen: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.moonlight.opacity(pulse ? 0.06 : 0.02))
                    .frame(width: 110, height: 110)
                    .scaleEffect(pulse ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: pulse)

                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .thin))
                    .foregroundStyle(Color.moonlight.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("JOURNAL INTIME")
                    .font(.system(size: 10, weight: .thin, design: .monospaced))
                    .foregroundStyle(Color.moonlight.opacity(0.55))
                    .tracking(4)
                Text("Tes pensées restent sur cet appareil.")
                    .font(.appLabel.weight(.thin))
                    .foregroundStyle(Color.moonlight.opacity(0.35))
                Text("Jamais transmis au coach IA.")
                    .font(.appCaption.weight(.thin))
                    .foregroundStyle(Color.moonlight.opacity(0.2))
            }

            if failed {
                Button("Réessayer avec Face ID") { authenticate() }
                    .font(.appLabel.weight(.thin))
                    .foregroundStyle(Color.moonlight.opacity(0.6))
            } else {
                Button("Déverrouiller avec Face ID") { authenticate() }
                    .font(.appLabel.weight(.thin))
                    .foregroundStyle(Color.moonlight.opacity(0.4))
            }

            Spacer()
        }
        .onAppear { pulse = true }
    }

    private func authenticate() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Journal Spirit") { success, _ in
            DispatchQueue.main.async {
                if success { unlocked = true } else { failed = true }
            }
        }
    }
}

// MARK: - Journal main view

struct SpiritJournalView: View {
    @ObservedObject var vm: SpiritViewModel
    @State private var showWrite = false

    private var todayISO: String {
        ISO8601DateFormatter().string(from: Date()).prefix(10).description
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                todayCard
                if !vm.journalStubs.isEmpty { pastEntries }
            }
            .padding(20)
        }
        .background(Color.voidBg)
        .sheet(isPresented: $showWrite, onDismiss: { Task { await vm.reloadJournal() } }) {
            SpiritJournalWriteView(date: todayISO)
        }
    }

    private var todayCard: some View {
        let hasEntry = vm.todayHasJournal()
        return VStack(spacing: 16) {
            Text(formattedToday())
                .font(.system(size: 11, weight: .thin, design: .monospaced))
                .foregroundStyle(Color.moonlight.opacity(0.25))
                .tracking(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasEntry {
                HStack {
                    Image(systemName: "checkmark")
                        .font(.appCaption.weight(.thin))
                        .foregroundStyle(Color.moonlight.opacity(0.6))
                    Text("Écrit ce soir.")
                        .font(.appLabel.weight(.thin))
                        .foregroundStyle(Color.moonlight.opacity(0.6))
                    Spacer()
                    Button("Relire") { showWrite = true }
                        .font(.system(size: 12, weight: .thin))
                        .foregroundStyle(Color.moonlight.opacity(0.55))
                }
            } else {
                Button {
                    showWrite = true
                } label: {
                    HStack {
                        Text("Entrer dans le silence")
                            .font(.system(size: 14, weight: .thin))
                            .foregroundStyle(Color.moonlight.opacity(0.5))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.appCaption.weight(.thin))
                            .foregroundStyle(Color.moonlight.opacity(0.2))
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.moonlight.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.moonlight.opacity(0.07), lineWidth: 0.5))
        )
    }

    private var pastEntries: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ARCHIVES")
                .font(.system(size: 9, weight: .thin, design: .monospaced))
                .foregroundStyle(Color.moonlight.opacity(0.2))
                .tracking(3)

            ForEach(vm.journalStubs.filter { $0.date != todayISO }) { stub in
                NavigationLink {
                    SpiritJournalReadView(date: stub.date)
                } label: {
                    HStack {
                        Text(formattedDate(stub.date))
                            .font(.appLabel.weight(.thin))
                            .foregroundStyle(Color.moonlight.opacity(0.6))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.appMicro.weight(.thin))
                            .foregroundStyle(Color.moonlight.opacity(0.15))
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func formattedToday() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        f.locale = Locale(identifier: "fr_CA")
        return f.string(from: Date()).uppercased()
    }

    private func formattedDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        f.dateFormat = "d MMMM yyyy"
        f.locale = Locale(identifier: "fr_CA")
        return f.string(from: d)
    }
}

// MARK: - Write view (sequential questions)

struct SpiritJournalWriteView: View {
    let date: String
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var grateful = ""
    @State private var conquered = ""
    @State private var haunting = ""
    @State private var isSaving = false
    @State private var showFinal = false
    @State private var saveError = false

    private let questions = [
        ("Pour quoi es-tu reconnaissant aujourd'hui ?", "Une pensée."),
        ("Qu'as-tu conquis aujourd'hui ?",              "Une victoire."),
        ("Qu'est-ce qui te hante encore ?",             "Une vérité."),
    ]

    var body: some View {
        ZStack {
            Color.voidBg.ignoresSafeArea()

            if showFinal {
                finalView
            } else {
                questionView
            }
        }
        .animation(.easeInOut(duration: 0.6), value: step)
        .animation(.easeInOut(duration: 0.6), value: showFinal)
    }

    // MARK: - Question step

    private var questionView: some View {
        VStack(spacing: 0) {
            // Step dots
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? Color.moonlight.opacity(0.5) : Color.moonlight.opacity(0.1))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.top, 60)

            Spacer()

            VStack(alignment: .leading, spacing: 24) {
                Text(questions[step].0)
                    .font(.system(size: 18, weight: .thin))
                    .foregroundStyle(Color.moonlight.opacity(0.7))
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .id(step)

                TextField(questions[step].1, text: currentBinding, axis: .vertical)
                    .font(.appBody.weight(.thin))
                    .foregroundStyle(Color.moonlight.opacity(0.8))
                    .tint(Color.moonlight.opacity(0.5))
                    .lineLimit(2)
                    .onChange(of: currentText) { _, v in
                        if v.count > 80 { currentBindingSet(String(v.prefix(80))) }
                    }
                    .id("field_\(step)")
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack {
                if step > 0 {
                    Button("←") { step -= 1 }
                        .font(.system(size: 16, weight: .thin))
                        .foregroundStyle(Color.moonlight.opacity(0.2))
                }
                Spacer()
                Button(step < 2 ? "Suivant →" : "Fermer les yeux →") {
                    if step < 2 {
                        step += 1
                    } else {
                        withAnimation { showFinal = true }
                        save()
                    }
                }
                .font(.system(size: 14, weight: .thin))
                .foregroundStyle(Color.moonlight.opacity(0.45))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }

    // MARK: - Final sacred display

    private var finalView: some View {
        VStack(alignment: .leading, spacing: 32) {
            Spacer()

            if !grateful.isEmpty {
                journalLine("Gratitude", text: grateful, delay: 0)
            }
            if !conquered.isEmpty {
                journalLine("Victoire", text: conquered, delay: 0.6)
            }
            if !haunting.isEmpty {
                journalLine("Ce qui reste", text: haunting, delay: 1.2)
            }

            Spacer()
            Spacer()

            if saveError {
                VStack(spacing: 8) {
                    Text("Non sauvegardé — vérifie ta connexion")
                        .font(.appCaption)
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button("Réessayer") { save() }
                        .font(.appCaption)
                        .foregroundStyle(Color.moonlight.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.bottom, 8)
            }

            Button("Fermer") { dismiss() }
                .font(.appLabel.weight(.thin))
                .foregroundStyle(Color.moonlight.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 52)
        }
        .padding(.horizontal, 32)
    }

    private func journalLine(_ category: String, text: String, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.uppercased())
                .font(.system(size: 9, weight: .thin, design: .monospaced))
                .foregroundStyle(Color.moonlight.opacity(0.2))
                .tracking(3)
            Text("· \(text)")
                .font(.appBody.weight(.thin))
                .foregroundStyle(Color.moonlight.opacity(0.6))
        }
        .opacity(showFinal ? 1 : 0)
        .animation(.easeInOut(duration: 0.8).delay(delay), value: showFinal)
    }

    // MARK: - Helpers

    private var currentText: String {
        switch step {
        case 0: return grateful
        case 1: return conquered
        default: return haunting
        }
    }

    private var currentBinding: Binding<String> {
        switch step {
        case 0: return $grateful
        case 1: return $conquered
        default: return $haunting
        }
    }

    private func currentBindingSet(_ v: String) {
        switch step {
        case 0: grateful  = v
        case 1: conquered = v
        default: haunting = v
        }
    }

    private func save() {
        saveError = false
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await APIService.shared.saveSpiritJournal(
                    date:        date,
                    gratefulFor: grateful.isEmpty  ? nil : grateful,
                    conquered:   conquered.isEmpty ? nil : conquered,
                    haunting:    haunting.isEmpty   ? nil : haunting
                )
            } catch {
                saveError = true
            }
        }
    }
}

// MARK: - Read view (past entry)

struct SpiritJournalReadView: View {
    let date: String
    @State private var entry: SpiritJournalEntry?
    @State private var loading = true

    var body: some View {
        ZStack {
            Color.voidBg.ignoresSafeArea()

            if loading {
                ProgressView().tint(Color.moonlight.opacity(0.55))
            } else if let e = entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        Text(formattedDate(date))
                            .font(.system(size: 11, weight: .thin, design: .monospaced))
                            .foregroundStyle(Color.moonlight.opacity(0.2))
                            .tracking(3)
                            .padding(.top, 8)

                        if let g = e.gratefulFor, !g.isEmpty {
                            readLine("Gratitude", text: g)
                        }
                        if let c = e.conquered, !c.isEmpty {
                            readLine("Victoire", text: c)
                        }
                        if let h = e.haunting, !h.isEmpty {
                            readLine("Ce qui reste", text: h)
                        }
                    }
                    .padding(32)
                }
            } else {
                Text("Aucune entrée.")
                    .font(.system(size: 14, weight: .thin))
                    .foregroundStyle(Color.moonlight.opacity(0.55))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            entry   = try? await APIService.shared.getSpiritJournalEntry(date: date)
            loading = false
        }
    }

    private func readLine(_ category: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.uppercased())
                .font(.system(size: 9, weight: .thin, design: .monospaced))
                .foregroundStyle(Color.moonlight.opacity(0.2))
                .tracking(3)
            Text("· \(text)")
                .font(.system(size: 16, weight: .thin))
                .foregroundStyle(Color.moonlight.opacity(0.55))
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "fr_CA")
        guard let d = f.date(from: iso) else { return iso }
        f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: d).uppercased()
    }
}
