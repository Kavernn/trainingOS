import SwiftUI
import Foundation

struct ChatPanel<Placeholder: View>: View {
    @Binding var messages: [ChatMessage]
    @Binding var input: String
    @Binding var isLoading: Bool
    @Binding var userHasInteracted: Bool

    @FocusState private var inputFocused: Bool

    var sendMessage: () -> Void
    @ViewBuilder var placeholder: () -> Placeholder

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    if messages.isEmpty {
                        placeholder()
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { msg in
                                ChatBubble(message: msg)
                                    .id(msg.id)
                            }

                            if isLoading {
                                HStack {
                                    TypingIndicator()
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 2)
                                .id("loading")
                            }

                            Color.clear.frame(height: 8).id("bottom")
                        }
                        .padding(.vertical, 10)
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    // Jump to bottom immediately — no animation on initial render
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: messages.count) {
                    guard userHasInteracted, let last = messages.last else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: isLoading) {
                    guard userHasInteracted, isLoading else { return }
                    withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                }
            }

            // Clear button strip — only when there are messages
            if !messages.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { messages = [] }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Effacer")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(Color(white: 0.28))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .background(Color.appBg)
            }

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message...", text: $input, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .tint(.purple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                inputFocused ? Color.purple.opacity(0.55) : Color.white.opacity(0.09),
                                lineWidth: 1
                            )
                    )
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit {
                        guard canSend else { return }
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(canSend ? Color.purple : Color.white.opacity(0.1))
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(canSend ? .white : Color(white: 0.3))
                    }
                    .frame(width: 38, height: 38)
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.15), value: canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.appBg)
        }
        .frame(maxHeight: .infinity)
    }
}
