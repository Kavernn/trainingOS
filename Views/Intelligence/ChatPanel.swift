//
//  ChatPanel.swift
//  TrainingOS
//
//  Created by Vincent Pinard on 2026-05-03.
//

import SwiftUI
import Foundation

struct ChatPanel: View {
    @Binding var messages: [ChatMessage]
    @Binding var input: String
    @Binding var isLoading: Bool
    @Binding var userHasInteracted: Bool

    @FocusState private var inputFocused: Bool

    var sendMessage: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !messages.isEmpty {
                            HStack(spacing: 8) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 1)

                                Text("CONVERSATION")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundColor(Color.white.opacity(0.2))
                                    .fixedSize()

                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }

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
                            .padding(.top, 4)
                            .id("loading")
                        }

                        Color.clear.frame(height: 24).id("bottom")
                    }
                    .padding(.bottom, 8)
                }
                .onChange(of: messages.count) {
                    guard userHasInteracted, let last = messages.last else { return }
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: isLoading) {
                    guard userHasInteracted, isLoading else { return }
                    withAnimation {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }

            Divider()
                .background(Color.white.opacity(0.07))

            HStack(spacing: 10) {
                TextField("Demande à ton coach...", text: $input, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .tint(.purple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(hex: "11111c"))
                    .cornerRadius(22)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        if !input.isEmpty && !isLoading {
                            sendMessage()
                        }
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(input.isEmpty || isLoading ? .gray : .purple)
                }
                .disabled(input.isEmpty || isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: "080810"))
        }
        .onTapGesture {
            inputFocused = false
        }
    }
}
