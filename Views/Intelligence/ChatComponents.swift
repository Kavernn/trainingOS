//
//  ChatComponents.swift
//  TrainingOS
//
//  Created by Vincent Pinard on 2026-05-03.
//

import SwiftUI

// MARK: - Chat Models

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID

    enum Role: String, Codable {
        case user, assistant
    }

    let role: Role
    let content: String

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
    }
}

struct AIProposal: Identifiable {
    let id = UUID()
    let jour: String
    let action: String
    let exercise: String
    let scheme: String
    let reason: String
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == .user }

    private enum NavChip {
        case seance, recovery, nutrition

        var label: String {
            switch self {
            case .seance:    return "Voir ma séance"
            case .recovery:  return "Voir ma récupération"
            case .nutrition: return "Voir ma nutrition"
            }
        }

        func post() {
            let name: Notification.Name
            switch self {
            case .seance:    name = .navigateToSeance
            case .recovery:  name = .navigateToRecovery
            case .nutrition: name = .navigateToNutrition
            }
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    private var navChip: NavChip? {
        guard !isUser else { return nil }
        let lower = message.content.lowercased()
        let seanceKw    = ["séance", "entraînement", "workout", "exercice", "programme"]
        let recoveryKw  = ["récupération", "sommeil", "hrv", "repos", "fatigue", "soreness"]
        let nutritionKw = ["protéines", "calories", "nutrition", "repas", "glucides", "lipides", "manger"]
        if seanceKw.contains(where: { lower.contains($0) })    { return .seance }
        if recoveryKw.contains(where: { lower.contains($0) })  { return .recovery }
        if nutritionKw.contains(where: { lower.contains($0) }) { return .nutrition }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser { Spacer(minLength: 60) }

                if !isUser {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.18))
                            .frame(width: 30, height: 30)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.purple)
                    }
                }

                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.purple.opacity(0.85) : Color.appSurfaceInset)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius:    18,
                            bottomLeadingRadius: isUser ? 18 : 5,
                            bottomTrailingRadius: isUser ? 5 : 18,
                            topTrailingRadius:   18
                        )
                    )
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius:    18,
                            bottomLeadingRadius: isUser ? 18 : 5,
                            bottomTrailingRadius: isUser ? 5 : 18,
                            topTrailingRadius:   18
                        )
                        .stroke(Color.white.opacity(isUser ? 0 : 0.09), lineWidth: 1)
                    )

                if !isUser { Spacer(minLength: 60) }
            }

            if let chip = navChip {
                Button { chip.post() } label: {
                    Text(chip.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.purple.opacity(0.28), lineWidth: 1))
                }
                .padding(.leading, 50)
            }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase = 0
    @State private var timer: Timer? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.purple.opacity(phase == i ? 1 : 0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.appCard)
        .cornerRadius(18)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
