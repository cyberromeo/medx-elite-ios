import SwiftUI

public struct HTMLRichTextView: View {
    public let html: String
    public var font: Font = .body
    public var textColor: Color = .primary

    public init(html: String, font: Font = .body, textColor: Color = .primary) {
        self.html = html
        self.font = font
        self.textColor = textColor
    }

    public var body: some View {
        if let attributed = parsedAttributedString() {
            Text(attributed)
                .font(font)
                .foregroundColor(textColor)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(cleanPlainText(html))
                .font(font)
                .foregroundColor(textColor)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func parsedAttributedString() -> AttributedString? {
        let clean = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "<li>", with: " • ")

        guard let data = clean.data(using: .utf8) else { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let nsAttr = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }

        var attr = AttributedString(nsAttr)
        // Strip excessive trailing newlines
        while let lastChar = attr.characters.last, lastChar.isWhitespace || lastChar.isNewline {
            attr.characters.removeLast()
        }
        return attr
    }

    private func cleanPlainText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
