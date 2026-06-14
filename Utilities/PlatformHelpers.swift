import SwiftUI
import Combine

// MARK: - Action Feedback

struct ActionFeedback {
    let id: UUID
    let message: String
    let storageKey: String?
    let haptic: HapticKind
    let duration: Double

    enum HapticKind {
        case impact(UIImpactFeedbackGenerator.FeedbackStyle)
        case notification(UINotificationFeedbackGenerator.FeedbackType)
        case none
    }

    init(message: String, storageKey: String?, haptic: HapticKind, duration: Double) {
        self.id = UUID()
        self.message = message
        self.storageKey = storageKey
        self.haptic = haptic
        self.duration = duration
    }

    var shouldShow: Bool {
        guard let key = storageKey else { return true }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return UserDefaults.standard.string(forKey: "afb_\(key)") != f.string(from: Date())
    }

    func markShown() {
        guard let key = storageKey else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        UserDefaults.standard.set(f.string(from: Date()), forKey: "afb_\(key)")
    }

    func fireHaptic() {
        switch haptic {
        case .impact(let style):       triggerImpact(style: style)
        case .notification(let type):  triggerNotificationFeedback(type)
        case .none: break
        }
    }

    static func sessionComplete(streak: Int? = nil) -> ActionFeedback {
        let msg: String
        if let s = streak, s > 1 {
            msg = "Séance complète. Streak : \(s) jours."
        } else {
            msg = "Séance complète."
        }
        return ActionFeedback(message: msg, storageKey: "feedbackSessionComplete",
                              haptic: .notification(.success), duration: 2.5)
    }

    static func mealLogged(proteinRemaining: Int?) -> ActionFeedback {
        let msg = proteinRemaining.map { "Repas loggué. Encore \($0)g de protéines." } ?? "Repas loggué."
        return ActionFeedback(message: msg, storageKey: nil, haptic: .impact(.light), duration: 1.5)
    }

    static var ritualComplete: ActionFeedback {
        ActionFeedback(message: "", storageKey: nil, haptic: .impact(.light), duration: 0.8)
    }

    static var proteinGoalReached: ActionFeedback {
        ActionFeedback(message: "Objectif protéines atteint aujourd'hui.",
                       storageKey: "feedbackProteinsGoal",
                       haptic: .notification(.success), duration: 2.0)
    }

    static func pssComplete(score: Int, maxScore: Int) -> ActionFeedback {
        let label = score <= (maxScore / 3) ? "stress faible"
                  : score <= (maxScore * 2 / 3) ? "stress modéré" : "stress élevé"
        return ActionFeedback(message: "Score PSS : \(score)/\(maxScore) — \(label)",
                              storageKey: nil, haptic: .impact(.light), duration: 2.0)
    }

    static var moodLogged: ActionFeedback {
        ActionFeedback(message: "Humeur enregistrée.",
                       storageKey: nil, haptic: .notification(.success), duration: 1.5)
    }

    static func habitCompleted(name: String) -> ActionFeedback {
        ActionFeedback(message: "\(name) — fait.",
                       storageKey: nil, haptic: .impact(.medium), duration: 1.5)
    }
}

final class ActionFeedbackManager: ObservableObject {
    static let shared = ActionFeedbackManager()
    @Published var current: ActionFeedback? = nil

    func show(_ feedback: ActionFeedback) {
        guard feedback.shouldShow else { return }
        feedback.markShown()
        feedback.fireHaptic()
        DispatchQueue.main.async { self.current = feedback }
    }
}

private struct ActionFeedbackModifier: ViewModifier {
    @ObservedObject private var manager = ActionFeedbackManager.shared
    @State private var workItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let fb = manager.current, !fb.message.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(.orange)
                        Text(fb.message)
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(Color(hex: "141428").opacity(0.97))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.orange.opacity(0.28), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
                    .padding(.bottom, 88)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { dismiss() }
                    .id(fb.id)
                }
            }
            .onChange(of: manager.current?.id) { _, _ in
                if let fb = manager.current, !fb.message.isEmpty { schedule(fb.duration) }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.current?.id)
    }

    private func schedule(_ duration: Double) {
        workItem?.cancel()
        let item = DispatchWorkItem { dismiss() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func dismiss() {
        workItem?.cancel()
        workItem = nil
        manager.current = nil
    }
}

extension View {
    func globalActionFeedback() -> some View {
        modifier(ActionFeedbackModifier())
    }
}

// MARK: - Haptic Feedback

func triggerImpact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
#if os(iOS)
    UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
}

func triggerNotificationFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
#if os(iOS)
    UINotificationFeedbackGenerator().notificationOccurred(type)
#endif
}

// MARK: - Presentation Detents

extension View {
    func adaptiveDetents(_ detents: Set<PresentationDetent>) -> some View {
#if os(iOS)
        self.presentationDetents(detents)
#else
        self
#endif
    }

    func numericKeyboard() -> some View {
#if os(iOS)
        self.keyboardType(.decimalPad)
#else
        self
#endif
    }

    func integerKeyboard() -> some View {
#if os(iOS)
        self.keyboardType(.numberPad)
#else
        self
#endif
    }
}
