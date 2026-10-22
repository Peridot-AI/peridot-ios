import SwiftUI
import UIKit

/// Renders a model answer. Parsing is cheap enough to redo for every streamed chunk.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Markdown.blocks(text).enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockView: View {
    let block: MDBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(rich(text))
        case .heading(let level, let text):
            Text(rich(text))
                .font(.system(size: level == 1 ? 22 : level == 2 ? 19 : 17, weight: .semibold))
                .padding(.top, 4)
        case .listItem(let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(marker)
                    .foregroundStyle(Theme.muted)
                    .frame(width: marker.count > 2 ? 30 : 22, alignment: .leading)
                Text(rich(text))
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .quote(let text):
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.mint.opacity(0.5)).frame(width: 3)
                Text(rich(text)).foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let code):
            CodeBlock(language: language, code: code)
        case .table(let header, let rows):
            TableBlock(header: header, rows: rows)
        case .rule:
            Divider().overlay(Theme.border).padding(.vertical, 4)
        }
    }
}

private struct CodeBlock: View {
    let language: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: language).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button("copy") { UIPasteboard.general.string = code }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(Theme.code, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}

private struct TableBlock: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(([header] + rows).enumerated()), id: \.offset) { r, row in
                    if r > 0 { Divider().overlay(Theme.border) }
                    GridRow {
                        ForEach(0..<columns, id: \.self) { c in
                            // Modifiers go on the cells: a modified GridRow stops being a row
                            Text(rich(c < row.count ? row[c] : ""))
                                .font(.subheadline.weight(r == 0 ? .semibold : .regular))
                                .frame(maxWidth: 280, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                                .background(r == 0 ? Theme.surface : Color.clear)
                        }
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Inline Markdown as an AttributedString (bold, italics, code, strikethrough, links).
func rich(_ source: String) -> AttributedString {
    var result = AttributedString()
    for span in Markdown.spans(source) {
        var part = AttributedString(span.text)
        var intent: InlinePresentationIntent = []
        if span.bold { intent.insert(.stronglyEmphasized) }
        if span.italic { intent.insert(.emphasized) }
        if span.strike { intent.insert(.strikethrough) }
        if !intent.isEmpty { part.inlinePresentationIntent = intent }
        if span.code {
            part.font = .system(size: 15, design: .monospaced)
            part.backgroundColor = Theme.surfaceHigh
        }
        if let url = span.url, let link = URL(string: url) {
            part.link = link
            part.foregroundColor = Theme.mint
        }
        result += part
    }
    return result
}
