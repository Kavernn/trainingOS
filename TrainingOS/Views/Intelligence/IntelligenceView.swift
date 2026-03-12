import SwiftUI
import Combine

struct IntelligenceView: View {
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isLoading = false
    @State private var showPropose = false
    @State private var proposals: [AIProposal] = []
    @State private var isLoadingProposals = false
    @FocusState private var inputFocused: Bool
    @StateObject private var api = APIService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()

                VStack(spacing: 0) {
                    // Propose button
                    Button(action: loadProposals) {
                        HStack {
                            if isLoadingProposals {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(isLoadingProposals ? "Analyse en cours..." : "Propositions de programme")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(10)
                    }
                    .disabled(isLoadingProposals)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // Proposals sheet
                    if !proposals.isEmpty {
                        ProposalsCard(proposals: proposals, onDismiss: { proposals = [] })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    Divider().background(Color.white.opacity(0.07))

                    // Chat history
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if messages.isEmpty {
                                    VStack(spacing: 16) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 48))
                                            .foregroundColor(.purple)
                                        Text("Coach IA")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("Pose une question sur ton entraînement, ta récupération, ou demande une analyse de tes progrès.")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                            .multilineTextAlignment(.center)

                                        VStack(spacing: 8) {
                                            ForEach(suggestions, id: \.self) { s in
                                                Button(action: { input = s }) {
                                                    Text(s)
                                                        .font(.system(size: 13))
                                                        .foregroundColor(.purple)
                                                        .padding(.horizontal, 14)
                                                        .padding(.vertical, 8)
                                                        .background(Color.purple.opacity(0.08))
                                                        .cornerRadius(20)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 32)
                                    .padding(.horizontal, 20)
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
                                    .id("loading")
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .onChange(of: messages.count) {
                            if let last = messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onChange(of: isLoading) {
                            if isLoading {
                                withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                            }
                        }
                    }

                    // Input bar
                    HStack(spacing: 10) {
                        TextField("Demande à ton coach...", text: $input, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(hex: "11111c"))
                            .cornerRadius(22)
                            .lineLimit(1...4)
                            .focused($inputFocused)

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
            }
            .navigationTitle("Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !messages.isEmpty {
                        Button("Effacer") { messages = [] }.foregroundColor(.purple)
                    }
                }
            }
        }
    }

    private let suggestions = [
        "Analyse mes progrès récents",
        "Comment améliorer ma récupération ?",
        "Suis-je en surcharge progressive ?",
        "Quels muscles devrais-je prioriser ?"
    ]

    private func buildContext() -> String {
        guard let dash = api.dashboard else { return "Données indisponibles." }
        let sessionCount = dash.sessions.count
        let avgRPE = dash.sessions.values.compactMap(\.rpe).reduce(0.0, +) / Double(max(dash.sessions.count, 1))
        let goals = dash.goals.map { "\($0.key): \($0.value.current)/\($0.value.goal)lbs" }.joined(separator: ", ")
        return "Séances totales: \(sessionCount). RPE moyen: \(String(format: "%.1f", avgRPE)). Aujourd'hui: \(dash.localToday). Semaine: \(dash.week). Objectifs: \(goals)."
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let context = buildContext()
        let fullPrompt = "Contexte athlète: \(context)\n\nQuestion: \(text)"
        messages.append(ChatMessage(role: .user, content: text))
        input = ""
        isLoading = true
        inputFocused = false

        Task {
            do {
                let url = URL(string: "https://training-os-rho.vercel.app/api/ai/coach")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": fullPrompt])
                let (data, _) = try await URLSession.shared.data(for: req)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let reply = json["response"] as? String ?? json["error"] as? String ?? "Erreur inconnue"
                    await MainActor.run {
                        messages.append(ChatMessage(role: .assistant, content: reply))
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, content: "Erreur: \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }
    }

    private func loadProposals() {
        guard !isLoadingProposals else { return }
        let context = buildContext()
        isLoadingProposals = true
        proposals = []
        Task {
            do {
                let url = URL(string: "https://training-os-rho.vercel.app/api/ai/propose")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: ["context": context])
                let (data, _) = try await URLSession.shared.data(for: req)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let raw = json["proposals"] as? [[String: Any]] {
                    let parsed = raw.compactMap { d -> AIProposal? in
                        guard let reason = d["reason"] as? String else { return nil }
                        return AIProposal(
                            jour: d["jour"] as? String ?? "",
                            action: d["action"] as? String ?? "",
                            exercise: d["exercise"] as? String ?? d["old_exercise"] as? String ?? "",
                            scheme: d["scheme"] as? String ?? "",
                            reason: reason
                        )
                    }
                    await MainActor.run { proposals = parsed; isLoadingProposals = false }
                } else {
                    await MainActor.run { isLoadingProposals = false }
                }
            } catch {
                await MainActor.run { isLoadingProposals = false }
            }
        }
    }
}

// MARK: - Chat Models
struct ChatMessage: Identifiable {
    let id = UUID()
    enum Role { case user, assistant }
    let role: Role
    let content: String
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                ZStack {
                    Circle().fill(Color.purple.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "brain.head.profile").font(.system(size: 12)).foregroundColor(.purple)
                }
            }

            Text(message.content)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.purple : Color(hex: "11111c"))
                .cornerRadius(18, corners: isUser ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }
}

struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.purple.opacity(phase == i ? 1 : 0.3))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "11111c"))
        .cornerRadius(18)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Proposals Card
struct ProposalsCard: View {
    let proposals: [AIProposal]
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Propositions IA", systemImage: "wand.and.stars")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.purple)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }

            ForEach(proposals) { p in
                HStack(alignment: .top, spacing: 10) {
                    Text(actionIcon(p.action))
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(p.jour).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                            if !p.exercise.isEmpty {
                                Text("·").foregroundColor(.gray)
                                Text(p.exercise).font(.system(size: 11)).foregroundColor(.purple)
                            }
                            if !p.scheme.isEmpty {
                                Text(p.scheme).font(.system(size: 11)).foregroundColor(.orange)
                            }
                        }
                        Text(p.reason).font(.system(size: 12)).foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "0d0d1a"))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.3), lineWidth: 1))
        .cornerRadius(12)
    }

    private func actionIcon(_ action: String) -> String {
        switch action {
        case "add":     return "➕"
        case "remove":  return "➖"
        case "replace": return "🔄"
        case "scheme":  return "📐"
        default:        return "💡"
        }
    }
}

// MARK: - Corner radius helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
