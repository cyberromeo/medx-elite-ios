import SwiftUI
import UIKit

public struct HTMLRichTextView: View {
    public let html: String
    public var fontSize: CGFloat = 15
    public var weight: UIFont.Weight = .regular
    public var textColor: Color = .primary

    public init(html: String, fontSize: CGFloat = 15, weight: UIFont.Weight = .regular, textColor: Color = .primary) {
        self.html = html
        self.fontSize = fontSize
        self.weight = weight
        self.textColor = textColor
    }

    public init(html: String, font: Font, textColor: Color = .primary) {
        self.html = html
        self.fontSize = 15
        self.weight = .regular
        self.textColor = textColor
    }

    public var body: some View {
        if let attributed = parsedAttributedString() {
            Text(attributed)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(cleanPlainText(html))
                .font(.system(size: fontSize, weight: fontWeightFromUIFont(weight)))
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

        let styledHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                font-family: -apple-system, "SF Pro Text", "SF Pro", system-ui, sans-serif;
                font-size: \(fontSize)px;
                line-height: 1.4;
            }
            b, strong {
                font-family: -apple-system, "SF Pro Text", "SF Pro", system-ui, sans-serif;
                font-weight: 700;
            }
            i, em {
                font-style: italic;
            }
        </style>
        </head>
        <body>\(clean)</body>
        </html>
        """

        guard let data = styledHTML.data(using: .utf8) else { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let nsAttr = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }

        // Replace all default fonts (e.g. Times New Roman) with SF Pro System Font, preserving bold & italic traits
        let fullRange = NSRange(location: 0, length: nsAttr.length)
        nsAttr.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if let existingFont = value as? UIFont {
                let isBold = existingFont.fontDescriptor.symbolicTraits.contains(.traitBold)
                let isItalic = existingFont.fontDescriptor.symbolicTraits.contains(.traitItalic)

                var targetFont: UIFont
                if isBold && isItalic {
                    let desc = UIFont.systemFont(ofSize: fontSize, weight: .bold).fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic])
                    targetFont = desc.flatMap { UIFont(descriptor: $0, size: fontSize) } ?? UIFont.boldSystemFont(ofSize: fontSize)
                } else if isBold {
                    targetFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
                } else if isItalic {
                    targetFont = UIFont.italicSystemFont(ofSize: fontSize)
                } else {
                    targetFont = UIFont.systemFont(ofSize: fontSize, weight: weight)
                }

                nsAttr.addAttribute(.font, value: targetFont, range: range)
            } else {
                nsAttr.addAttribute(.font, value: UIFont.systemFont(ofSize: fontSize, weight: weight), range: range)
            }
        }

        // Apply dynamic text color (light/dark adapt)
        nsAttr.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { _, range, _ in
            nsAttr.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        }

        var attr = AttributedString(nsAttr)
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

    private func fontWeightFromUIFont(_ weight: UIFont.Weight) -> Font.Weight {
        switch weight {
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        case .light: return .light
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
