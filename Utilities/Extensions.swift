import SwiftUI
import AVFoundation

// MARK: - API Config (single source of truth for base URL)
enum APIConfig {
    static let base = "https://training-os-rho.vercel.app"
}

// MARK: - Keyboard dismiss

extension View {
    func hideKeyboard() {
#if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
#endif
    }

}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

extension DateFormatter {
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Montreal")
        return f
    }()
}

// MARK: - Beep generator (WAV en mémoire, joue par-dessus la musique)
/// Génère un bip sinusoïdal à la fréquence `hz` et le retourne prêt à jouer.
/// Utilise AVAudioSession .playback + .mixWithOthers : audible même en mode silencieux,
/// sans couper la musique en cours de lecture.
func makeBeep(hz: Double, duration: Double) -> AVAudioPlayer? {
    let rate  = 44100
    let count = Int(Double(rate) * duration)
    var wav   = Data()

    func w16(_ v: Int16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
    func w32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }

    wav.append(contentsOf: "RIFF".utf8); w32(Int32(36 + count * 2))
    wav.append(contentsOf: "WAVE".utf8)
    wav.append(contentsOf: "fmt ".utf8); w32(16); w16(1); w16(1)
    w32(Int32(rate)); w32(Int32(rate * 2)); w16(2); w16(16)
    wav.append(contentsOf: "data".utf8); w32(Int32(count * 2))
    for i in 0..<count {
        let t   = Double(i) / Double(rate)
        let env = min(1.0, min(t / 0.005, (duration - t) / 0.005))
        w16(Int16(env * 28000 * sin(2 * .pi * hz * t)))
    }

#if os(iOS)
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
    try? AVAudioSession.sharedInstance().setActive(true)
#endif
    let player = try? AVAudioPlayer(data: wav, fileTypeHint: "wav")
    player?.prepareToPlay()
    return player
}
