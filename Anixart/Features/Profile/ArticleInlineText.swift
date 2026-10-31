import SwiftUI

/// Render the editor's small inline-HTML vocabulary natively. No HTML importer,
/// scripts, iframe, style sheet, or hidden remote image is ever executed here.
struct ArticleInlineText: View {
    let html: String
    var style: Font.TextStyle = .body
    var weight: Font.Weight = .regular

    var body: some View {
        ArticleInlineParser.parse(html).reduce(Text("")) { result, span in
            var attributed = AttributedString(span.text)
            attributed.link = span.link
            var text = Text(attributed).font(span.code ? .system(style, design: .monospaced) : .ax(style, span.bold ? .bold : weight))
            if span.italic { text = text.italic() }
            if span.underline { text = text.underline() }
            if span.strikethrough { text = text.strikethrough() }
            return result + text
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ArticleTextSpan: Equatable {
    var text: String
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var code = false
    var link: URL?
}

enum ArticleInlineParser {
    private struct Tag {
        var name: String
        var link: URL?
    }

    static func parse(_ html: String) -> [ArticleTextSpan] {
        guard let expression = try? NSRegularExpression(pattern: "<[^>]*>|[^<]+|<") else { return [ArticleTextSpan(text: html)] }
        var stack: [Tag] = []
        var ignored: [String] = []
        var result: [ArticleTextSpan] = []

        for match in expression.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let token = String(html[range])
            if token.hasPrefix("<"), let name = tagName(token) {
                let closing = token.hasPrefix("</")
                if ["script", "style", "iframe", "object"].contains(name) {
                    if closing { if ignored.last == name { ignored.removeLast() } }
                    else { ignored.append(name) }
                    continue
                }
                guard ignored.isEmpty else { continue }
                if name == "br" { result.append(ArticleTextSpan(text: "\n")); continue }
                if closing {
                    if let index = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(index...) }
                    continue
                }
                if ["b", "strong", "i", "em", "u", "s", "strike", "del", "code", "a"].contains(name) {
                    let link = name == "a" ? attribute("href", in: token).flatMap { ProfileWebURL.url(decodeEntities($0)) } : nil
                    stack.append(Tag(name: name, link: link))
                }
            } else if ignored.isEmpty {
                let names = Set(stack.map(\.name))
                result.append(ArticleTextSpan(text: decodeEntities(token), bold: !names.isDisjoint(with: ["b", "strong"]),
                                             italic: !names.isDisjoint(with: ["i", "em"]), underline: names.contains("u"),
                                             strikethrough: !names.isDisjoint(with: ["s", "strike", "del"]), code: names.contains("code"),
                                             link: stack.last(where: { $0.name == "a" })?.link))
            }
        }
        return result
    }

    private static func tagName(_ token: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: "^</?\\s*([a-zA-Z][a-zA-Z0-9]*)"),
              let match = expression.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
              let range = Range(match.range(at: 1), in: token) else { return nil }
        return token[range].lowercased()
    }

    private static func attribute(_ name: String, in token: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) else { return nil }
        for index in 1...3 {
            if let range = Range(match.range(at: index), in: token) { return String(token[range]) }
        }
        return nil
    }

    static func decodeEntities(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);") else { return text }
        var result = text
        let names = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00a0}"]
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: text), let range = Range(match.range, in: result) else { continue }
            let name = String(text[nameRange])
            var replacement = names[name]
            if name.hasPrefix("#x"), let value = UInt32(name.dropFirst(2), radix: 16), let scalar = UnicodeScalar(value) { replacement = String(scalar) }
            else if name.hasPrefix("#"), let value = UInt32(name.dropFirst()), let scalar = UnicodeScalar(value) { replacement = String(scalar) }
            if let replacement { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }
}
