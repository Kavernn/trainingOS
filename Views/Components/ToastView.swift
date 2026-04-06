import SwiftUI

enum ToastStyle {
    case success, error, info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .orange
        }
    }
}

struct ToastMessage: Equatable {
    let message: String
    let style: ToastStyle

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.message == rhs.message && lhs.style == rhs.style
    }
}

private struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.icon)
                .foregroundColor(toast.style.color)
            Text(toast.message)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: ToastMessage?
    @State private var workItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(toast: toast)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { dismiss() }
                }
            }
            .onChange(of: toast) { _, newValue in
                if newValue != nil { schedule() }
            }
            .animation(.spring(duration: 0.35), value: toast)
    }

    private func schedule() {
        workItem?.cancel()
        let item = DispatchWorkItem { dismiss() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }

    private func dismiss() {
        workItem?.cancel()
        workItem = nil
        toast = nil
    }
}

extension View {
    func toast(_ toast: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
