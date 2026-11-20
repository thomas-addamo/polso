import SwiftUI
import UIKit

/// Blocchi Markdown riconosciuti nelle risposte.
enum MDBlock {
    case heading(Int, String)
    case paragraph(String)
    case list([(marker: String, text: String)])
    case code(language: String?, String)
    case quote(String)
    case table(header: [String], alignments: [TextAlignment], rows: [[String]])
    case rule
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = text.components(separatedBy: "\n")
        var paragraph: [String] = []
        var i = 0

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        func trimmed(_ index: Int) -> String {
            lines[index].trimmingCharacters(in: .whitespaces)
        }

        while i < lines.count {
            let line = trimmed(i)

            if line.hasPrefix("```") {
                flush()
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                // Durante lo streaming il blocco può non essere ancora chiuso.
                while i < lines.count, !trimmed(i).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language, code.joined(separator: "\n")))
                i += 1
                continue
            }
            if line.isEmpty { flush(); i += 1; continue }
            // Tabella: riga di intestazione seguita da una riga di separazione (|---|:---:|).
            if line.contains("|"), i + 1 < lines.count, MarkdownTable.isSeparator(trimmed(i + 1)) {
                flush()
                let header = MarkdownTable.cells(line)
                let alignments = MarkdownTable.alignments(trimmed(i + 1))
                i += 2
                var rows: [[String]] = []
                while i < lines.count, !trimmed(i).isEmpty, trimmed(i).contains("|") {
                    rows.append(MarkdownTable.cells(trimmed(i)))
                    i += 1
                }
                blocks.append(.table(header: header, alignments: alignments, rows: rows))
                continue
            }
            if let heading = heading(line) { flush(); blocks.append(.heading(heading.0, heading.1)); i += 1; continue }
            if ["---", "***", "___"].contains(line) { flush(); blocks.append(.rule); i += 1; continue }
            if line.hasPrefix(">") {
                flush()
                var quote: [String] = []
                while i < lines.count, trimmed(i).hasPrefix(">") {
                    quote.append(String(trimmed(i).dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }
            if listItem(line) != nil {
                flush()
                var items: [(marker: String, text: String)] = []
                while i < lines.count, let item = listItem(trimmed(i)) {
                    items.append(item)
                    i += 1
                }
                blocks.append(.list(items))
                continue
            }
            paragraph.append(lines[i])
            i += 1
        }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func listItem(_ line: String) -> (marker: String, text: String)? {
        for bullet in ["- ", "* ", "• "] where line.hasPrefix(bullet) {
            return ("•", String(line.dropFirst(2)))
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return (digits + ".", String(rest.dropFirst(2)))
            }
        }
        return nil
    }
}

/// Rende il Markdown a blocchi: titoli, elenchi, citazioni e blocchi di codice.
struct MarkdownBlocksView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownText.render(text))
                .font(level == 1 ? .title3.weight(.bold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 2)
        case .paragraph(let text):
            Text(MarkdownText.render(text))
                .lineSpacing(3)
                .textSelection(.enabled)
        case .list(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.marker)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                        Text(MarkdownText.render(item.text))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                }
            }
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent.opacity(0.6))
                    .frame(width: 3)
                Text(MarkdownText.render(text))
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let header, let alignments, let rows):
            MarkdownTableView(header: header, alignments: alignments, rows: rows)
        case .rule:
            Divider()
        }
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "codice")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    withAnimation(.snappy) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(.snappy) { copied = false }
                    }
                } label: {
                    Label(copied ? "Copiato" : "Copia", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Theme.accent : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - Tabelle

struct MarkdownTableView: View {
    let header: [String]
    let alignments: [TextAlignment]
    let rows: [[String]]

    private var columnCount: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid
            ScrollView(.horizontal, showsIndicators: false) { grid }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private var grid: some View {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        cell(value(header, column), column: column, isHeader: true, shaded: false)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            cell(value(row, column), column: column, isHeader: false, shaded: index.isMultiple(of: 2) == false)
                        }
                    }
                }
            }
    }

    private func value(_ cells: [String], _ column: Int) -> String {
        column < cells.count ? cells[column] : ""
    }

    private func cell(_ text: String, column: Int, isHeader: Bool, shaded: Bool) -> some View {
        let alignment = column < alignments.count ? alignments[column] : .leading
        let frameAlignment: Alignment = alignment == .center ? .center : alignment == .trailing ? .trailing : .leading
        return Text(MarkdownText.render(text))
            .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
            .multilineTextAlignment(alignment)
            .textSelection(.enabled)
            .frame(maxWidth: 220, alignment: frameAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minWidth: 64, maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
            .background(isHeader ? Theme.accent.opacity(0.14) : shaded ? Color.primary.opacity(0.035) : .clear)
    }
}
