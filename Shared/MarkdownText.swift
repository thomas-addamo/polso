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
