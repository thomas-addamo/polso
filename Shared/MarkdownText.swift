import SwiftUI

/// Testo con il Markdown di base (grassetto, corsivo, codice inline, link).
struct MarkdownText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(Self.render(text))
    }

    static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

extension Date {
    var shortRelative: String {
        formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

// MARK: - Tabelle Markdown

enum MarkdownTable {
    static func cells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.replacingOccurrences(of: "\\|", with: "\u{1}")
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\u{1}", with: "|").trimmingCharacters(in: .whitespaces) }
    }

    static func isSeparator(_ line: String) -> Bool {
        let row = line.trimmingCharacters(in: .whitespaces)
        guard row.contains("-"), row.contains("|") || row.hasPrefix(":") || row.hasPrefix("-") else { return false }
        return row.allSatisfy { "|:- ".contains($0) } && cells(row).allSatisfy { $0.contains("-") }
    }

    static func alignments(_ line: String) -> [TextAlignment] {
        cells(line).map { cell in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): .center
            case (false, true): .trailing
            default: .leading
            }
        }
    }
}

extension MarkdownText {
    /// Versione compatta per lo schermo del Watch: titoli in grassetto, elenchi con il pallino,
    /// tabelle trasformate in righe leggibili.
    static func compact(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.contains("|"), i + 1 < lines.count, MarkdownTable.isSeparator(lines[i + 1]) {
                let header = MarkdownTable.cells(line)
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    let cells = MarkdownTable.cells(lines[i])
                    let parts = cells.enumerated().map { index, value in
                        index < header.count && !header[index].isEmpty ? "**\(header[index])**: \(value)" : value
                    }
                    output.append("• " + parts.joined(separator: " · "))
                    i += 1
                }
                continue
            }
            if line.hasPrefix("```") { i += 1; continue }
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                output.append("**\(line.dropFirst(hashes + 1))**")
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                output.append("• " + line.dropFirst(2))
            } else if ["---", "***", "___"].contains(line) {
                output.append("")
            } else {
                output.append(lines[i])
            }
            i += 1
        }
        return output.joined(separator: "\n")
    }
}
