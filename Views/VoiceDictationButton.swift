import SwiftUI
import Speech
import AVFoundation
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Service
// ─────────────────────────────────────────────────────────────────────────────

final class SpeechDictationService: ObservableObject {
    @Published var isRecording  = false
    @Published var errorMessage: String?

    // Text from before dictation started + finished 1-min sessions
    private var accumulatedBase = ""
    // Observed by the view via .onChange — seul pattern SwiftUI garanti pour écrire dans un @Binding
    @Published var latestTranscription = ""

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine    = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?

    // ── Public ──────────────────────────────────────────────────────────────

    func startDictation(existingText: String) {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            guard let self else { return }
            guard speechStatus == .authorized else {
                DispatchQueue.main.async {
                    self.errorMessage = "Permission de reconnaissance vocale refusée — Réglages > Confidentialité > Reconnaissance vocale."
                }
                return
            }
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async { self?.handleMic(granted: granted, existingText: existingText) }
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async { self?.handleMic(granted: granted, existingText: existingText) }
                }
            }
        }
    }

    func stopDictation() {
        isRecording = false
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        cleanup()
        accumulatedBase = ""
    }

    // ── Private ─────────────────────────────────────────────────────────────

    private func handleMic(granted: Bool, existingText: String) {
        guard granted else {
            errorMessage = "Permission microphone refusée — Réglages > Confidentialité > Microphone."
            return
        }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")), rec.isAvailable else {
            errorMessage = "Reconnaissance vocale en français non disponible sur cet appareil."
            return
        }
        guard rec.supportsOnDeviceRecognition else {
            errorMessage = "Reconnaissance hors-ligne non disponible. Vérifie les réglages de langue."
            return
        }
        recognizer         = rec
        accumulatedBase    = existingText
        latestTranscription = ""
        isRecording        = true
        startSession()
    }

    private func startSession() {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Impossible de configurer l'audio."
                self.isRecording  = false
            }
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults   = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Impossible de démarrer le microphone."
                self.isRecording  = false
            }
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let partial = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.latestTranscription = self.compose(partial)
                }
                if result.isFinal {
                    // 1-min limit hit — accumulate and restart transparently
                    DispatchQueue.main.async {
                        guard self.isRecording else { return }
                        self.accumulatedBase = self.compose(partial)
                        self.cleanup()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            guard self.isRecording else { return }
                            self.startSession()
                        }
                    }
                }
            }

            if let error {
                DispatchQueue.main.async {
                    guard self.isRecording else { return } // cancellation from stopDictation() — ignore
                    let code = (error as NSError).code
                    if code != 1110 && code != 203 { // 1110 = no speech, 203 = cancel — not real errors
                        self.errorMessage = "Erreur de reconnaissance — réessaie."
                        self.isRecording  = false
                        self.cleanup()
                    }
                }
            }
        }
    }

    private func compose(_ partial: String) -> String {
        guard !accumulatedBase.isEmpty else { return partial }
        let sep = accumulatedBase.last == " " ? "" : " "
        return accumulatedBase + sep + partial
    }

    private func cleanup() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask    = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - View
// ─────────────────────────────────────────────────────────────────────────────

struct VoiceDictationButton: View {
    @Binding var text: String
    var onStop: (() -> Void)? = nil
    var resetOnStart: Bool = false
    @StateObject private var service = SpeechDictationService()
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 8) {
            if service.isRecording {
                Circle()
                    .fill(Color.statusRed)
                    .frame(width: 7, height: 7)
                    .opacity(pulsing ? 0.25 : 1)
                    .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: pulsing)
                Text("Écoute…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button {
                if service.isRecording {
                    service.stopDictation()
                    onStop?()
                } else {
                    if resetOnStart { text = "" }
                    service.startDictation(existingText: text)
                }
            } label: {
                Image(systemName: service.isRecording ? "stop.circle.fill" : "mic.circle")
                    .font(.title2)
                    .foregroundColor(service.isRecording ? Color.statusRed : .secondary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onChange(of: service.isRecording) { recording in
            pulsing = recording
        }
        .onChange(of: service.latestTranscription) { newText in
            if !newText.isEmpty { text = newText }
        }
        .onDisappear {
            if service.isRecording { service.stopDictation() }
        }
        .alert("Dictée indisponible", isPresented: Binding(
            get:  { service.errorMessage != nil },
            set:  { if !$0 { service.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { service.errorMessage = nil }
        } message: {
            Text(service.errorMessage ?? "")
        }
    }
}
