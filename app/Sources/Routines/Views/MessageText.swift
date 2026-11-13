import RoutinesKit
import SwiftUI

/// An agent message as Markdown blocks: headings, lists, quotes, rules and code with a copy button.
struct MessageText: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            ForEach(Array(MessageBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct BlockView: View {
    var block: MessageBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            inline(text).font(Tokens.Font.bodyLarge).lineSpacing(Tokens.Space.s2)
        case .heading(let level, let text):
            inline(text).font(level == 1 ? Tokens.Font.heading2 : level == 2 ? Tokens.Font.subhead : Tokens.Font.cardTitle).padding(.top, Tokens.Space.s4)
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s6) {
                Text(marker).foregroundStyle(Theme.muted).monospacedDigit()
                inline(text).lineSpacing(Tokens.Space.s2)
            }
            .font(Tokens.Font.bodyLarge)
            .padding(.leading, CGFloat(depth) * Tokens.Space.s16)
        case .quote(let text):
            HStack(spacing: Tokens.Space.s8) {
                Capsule().fill(.tertiary).frame(width: Tokens.Space.s3)
                inline(text).font(Tokens.Font.bodyLarge).foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let text):
            CodeBlock(language: language, text: text)
        case .rule:
            Divider()
        }
    }

    private func inline(_ text: String) -> some View {
        Text(Markdown.attributed(text)).fixedSize(horizontal: false, vertical: true)
    }
}

private struct CodeBlock: View {
    var language: String?
    var text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code").font(Tokens.Font.caption).foregroundStyle(Theme.faint)
                Spacer()
                CopyButton(text: text)
            }
            .padding(.horizontal, Tokens.Space.s10)
            .padding(.vertical, Tokens.Space.s6)
            Divider().opacity(0.6)
            ScrollView(.horizontal) {
                Text(text)
                    .font(Tokens.Font.mono.monospaced())
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(Tokens.Space.s10)
            }
            .scrollIndicators(.never)
        }
        .background(shape.fill(.quinary))
        .overlay(shape.strokeBorder(.quaternary))
    }
}
