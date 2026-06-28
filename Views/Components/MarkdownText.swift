import SwiftUI

struct MarkdownText: View {
    let markdown: String
    var accent: Color = .statusPurple

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private enum Block {
        case h1(String), h2(String), h3(String)
        case bullet(String)
        case paragraph(String)
        case spacer
    }

    private var blocks: [Block] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> Block in
            let trimmed = String(raw).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty                    { return .spacer }
            if trimmed.hasPrefix("### ")          { return .h3(String(trimmed.dropFirst(4))) }
            if trimmed.hasPrefix("## ")           { return .h2(String(trimmed.dropFirst(3))) }
            if trimmed.hasPrefix("# ")            { return .h1(String(trimmed.dropFirst(2))) }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return .bullet(String(trimmed.dropFirst(2)))
            }
            return .paragraph(trimmed)
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .h1(let s):
            Text(inline(s)).font(.appTitle).foregroundColor(.appTextPrimary)
                .padding(.top, 6)
        case .h2(let s):
            Text(inline(s)).font(.appHeadline).foregroundColor(.appTextPrimary)
                .padding(.top, 4)
        case .h3(let s):
            Text(inline(s)).font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(.appBody).foregroundColor(accent)
                Text(inline(s)).font(.appBody).foregroundColor(.appTextPrimary)
            }
        case .paragraph(let s):
            Text(inline(s)).font(.appBody).foregroundColor(.appTextPrimary)
        case .spacer:
            Spacer().frame(height: 4)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}

#if DEBUG
#Preview("MarkdownText") {
    ScrollView {
        MarkdownText(markdown: """
        ## Titre H2
        - point un
        - point **deux** en gras

        Paragraphe avec **gras inline** et un mot *italique*.

        ### Sous-titre H3
        - autre point
        """)
        .padding()
    }
    .background(Color.appBg)
}
#endif
