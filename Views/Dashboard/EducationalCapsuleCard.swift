import SwiftUI

struct EducationalCapsuleCard: View {
    let capsule: EducationalCapsule
    let onTap: () -> Void

    private var previewLine: String? {
        capsule.body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first {
                !$0.isEmpty
                && !$0.hasPrefix("#")
                && !$0.hasPrefix("-")
                && !$0.hasPrefix("*")
            }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(capsule.title)
                    .font(.appHeadline)
                    .foregroundColor(.appTextPrimary)
                    .multilineTextAlignment(.leading)
                if let preview = previewLine {
                    Text(preview)
                        .font(.appBody)
                        .foregroundColor(Color(white: 0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let tags = capsule.tags, !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.appCaption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.statusPurple.opacity(0.12))
                                .foregroundColor(.statusPurple)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard)
            .cornerRadius(14)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct EducationalCapsuleDetailSheet: View {
    let capsule: EducationalCapsule
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(capsule.title)
                        .font(.appTitle)
                        .foregroundColor(.appTextPrimary)
                    MarkdownText(markdown: capsule.body)
                    if let tags = capsule.tags, !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.appCaption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.statusPurple.opacity(0.12))
                                    .foregroundColor(.statusPurple)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(Color.appBg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", action: onDismiss).foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}
