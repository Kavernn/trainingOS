import SwiftUI

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
