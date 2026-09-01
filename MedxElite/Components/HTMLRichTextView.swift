import SwiftUI
import UIKit

// MARK: - Rich text blocks

/// One renderable run of question / explanation HTML. Arise stores its content as web
/// HTML and a lot of it is `<img>` diagrams sitting between paragraphs, so the content
/// has to become a *list* of blocks rather than a single attributed string.
public enum MedxRichBlock: Identifiable, Hashable {
    case text(index: Int, string: AttributedString)
    case image(index: Int, url: URL)

    public var id: Int {
        switch self {
        case .text(let index, _): return index
        case .image(let index, _): return index
        }
    }
}

/// Full-screen zoom target. `URL` is not `Identifiable`, so presentations need a wrapper.
public struct MedxZoomTarget: Identifiable, Hashable {
    public let url: URL
    public var id: String { url.absoluteString }

    public init(url: URL) {
        self.url = url
    }
}

// MARK: - Rich text view

/// Renders Arise's question / option / explanation HTML.
///
/// Three things this gets right that the old `NSAttributedString(html:)` version did not:
///
/// 1. **Images.** Many stems and most explanations embed `<img>` diagrams. The HTML
///    importer dropped them silently, so a question would refer to a figure that was
///    never on screen.
/// 2. **Dark Mode.** The source HTML carries inline `color:#ffffff` and
///    `background-color:#ffffff` highlights authored for a white web page — rendered
///    verbatim, those words are invisible. Authored colours are re-mapped onto dynamic
///    system colours (`MedxTheme.RichText`) and resolved for the current appearance.
/// 3. **Speed.** `NSAttributedString(data:options:.html)` is a WebKit-backed main-thread
///    parse costing milliseconds per call, and SwiftUI evaluates `body` a lot. This uses
///    a small hand-written parser plus a result cache keyed by content and style, so
///    scrolling a 40-question review no longer stutters.
public struct HTMLRichTextView: View {
    public let html: String
    public var fontSize: CGFloat
    public var weight: UIFont.Weight
    public var textColor: Color
    /// Embedded images are capped to this height so one diagram cannot push the rest of
    /// the question off screen.
    public var maxImageHeight: CGFloat
    /// Off inside another button (an answer option) — a nested button never fires, and
    /// text selection would swallow the row's tap.
    public var interactive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var zoomTarget: MedxZoomTarget?

    public init(
        html: String,
        fontSize: CGFloat = 15,
        weight: UIFont.Weight = .regular,
        textColor: Color = .primary,
        maxImageHeight: CGFloat = 300,
        interactive: Bool = true
    ) {
        self.html = html
        self.fontSize = fontSize
        self.weight = weight
        self.textColor = textColor
        self.maxImageHeight = maxImageHeight
        self.interactive = interactive
    }

    private var blocks: [MedxRichBlock] {
        MedxRichText.blocks(
            html: html,
            fontSize: resolvedFontSize,
            weight: weight,
            secondary: textColor == .secondary,
            isDark: colorScheme == .dark
        )
    }

    /// The parser bakes a concrete point size into its fonts, so Dynamic Type has to be
    /// applied by hand instead of by `.font(.body)`.
    private var resolvedFontSize: CGFloat {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: fontSize)
        return (min(max(scaled, fontSize), fontSize * 1.9) * 2).rounded() / 2
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block {
                case .text(_, let string):
                    textRun(string)
                case .image(_, let url):
                    imageRun(url)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $zoomTarget) { target in
            MedxImageViewer(url: target.url)
        }
    }

    @ViewBuilder
    private func textRun(_ string: AttributedString) -> some View {
        let base = Text(string)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

        if interactive {
            base.textSelection(.enabled)
        } else {
            base
        }
    }

    @ViewBuilder
    private func imageRun(_ url: URL) -> some View {
        if interactive {
            Button {
                HapticManager.light()
                zoomTarget = MedxZoomTarget(url: url)
            } label: {
                imageBody(url)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Figure")
            .accessibilityHint("Opens the image full screen")
        } else {
            imageBody(url)
                .accessibilityLabel("Figure")
        }
    }

    private func imageBody(_ url: URL) -> some View {
        CachedAsyncImage(url: url, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: maxImageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(MedxSurface.separator.opacity(0.35), lineWidth: MedxSurface.hairline)
            )
    }
}

// MARK: - Full-screen image viewer

/// Pinch/double-tap zoom for a figure lifted out of a question. Deliberately small: the
/// flashcard gallery has its own paging viewer, this one shows exactly one image.
struct MedxImageViewer: View {
    let url: URL

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isZoomed: Bool { scale > 1.02 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CachedAsyncImage(url: url, contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
                .gesture(magnification)
                // Panning is only wired up while zoomed in, otherwise it steals the
                // swipe-down-to-dismiss drag.
                .gesture(pan, including: isZoomed ? .all : .subviews)
                .onTapGesture(count: 2) { toggleZoom() }
                .gesture(dismissDrag, including: isZoomed ? .subviews : .all)
                .accessibilityLabel("Figure")
                .accessibilityHint("Pinch or double-tap to zoom. Swipe down to close.")
        }
        .overlay(alignment: .topTrailing) {
            MedxCircleButton(icon: "xmark", accessibilityLabel: "Close figure") {
                HapticManager.light()
                dismiss()
            }
            .padding(.trailing, 6)
            .padding(.top, 2)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    private func toggleZoom() {
        HapticManager.selection()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            if isZoomed {
                reset()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 6) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { withAnimation(.easeOut(duration: 0.18)) { reset() } }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard value.translation.height > 110,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                HapticManager.light()
                dismiss()
            }
    }
}

// MARK: - Parse cache

enum MedxRichText {
    private struct Key: Hashable {
        let html: String
        let size: CGFloat
        let weight: CGFloat
        let secondary: Bool
        let isDark: Bool
    }

    private static let lock = NSLock()
    private static var cache: [Key: [MedxRichBlock]] = [:]
    private static var order: [Key] = []
    private static let limit = 500

    static func blocks(
        html: String,
        fontSize: CGFloat,
        weight: UIFont.Weight,
        secondary: Bool,
        isDark: Bool
    ) -> [MedxRichBlock] {
        guard !html.isEmpty else { return [] }

        let key = Key(
            html: html,
            size: fontSize,
            weight: weight.rawValue,
            secondary: secondary,
            isDark: isDark
        )

        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        var parser = MedxHTMLParser(
            fontSize: fontSize,
            weight: weight,
            secondary: secondary,
            isDark: isDark
        )
        let parsed = parser.parse(html)

        lock.lock()
        if cache[key] == nil {
            cache[key] = parsed
            order.append(key)
            while order.count > limit {
                let stale = order.removeFirst()
                cache.removeValue(forKey: stale)
            }
        }
        lock.unlock()

        return parsed
    }

    /// Plain text with every tag and entity stripped — used for search and previews.
    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .decodingHTMLEntities()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolves a separately exported figure path the same way an inline `<img src>` is
    /// resolved, so `question.images` entries and embedded images behave identically.
    static func figureURL(_ raw: String) -> URL? {
        MedxHTMLParser.imageURL(from: raw)
    }
}

// MARK: - Parser

/// A deliberately small HTML subset parser covering exactly what Arise's editor emits:
/// inline emphasis, coloured / highlighted spans, headings, lists, simple tables and
/// `<img>`. Anything it does not recognise degrades to its text content.
private struct MedxHTMLParser {
    struct InlineStyle {
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        /// +1 superscript, -1 subscript, 0 baseline.
        var script = 0
        var monospace = false
        var sizeScale: CGFloat = 1
        var color: UIColor?
        var highlighted = false
    }

    let fontSize: CGFloat
    let weight: UIFont.Weight
    let secondary: Bool
    let traits: UITraitCollection

    private var blocks: [MedxRichBlock] = []
    private var buffer = NSMutableAttributedString()
    private var stack: [(name: String, style: InlineStyle)] = []
    private var lists: [(ordered: Bool, counter: Int)] = []
    private var skipDepth = 0
    private var cellsInRow = 0
    private var nextIndex = 0

    init(fontSize: CGFloat, weight: UIFont.Weight, secondary: Bool, isDark: Bool) {
        self.fontSize = fontSize
        self.weight = weight
        self.secondary = secondary
        self.traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
    }

    private var currentStyle: InlineStyle {
        stack.last?.style ?? InlineStyle()
    }

    private var baseColor: UIColor {
        secondary ? MedxTheme.RichText.secondaryLabel : MedxTheme.RichText.label
    }

    private func resolve(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: traits)
    }

    // MARK: Entry point

    mutating func parse(_ html: String) -> [MedxRichBlock] {
        let chars = Array(html)
        var pending = ""
        var i = 0

        while i < chars.count {
            if chars[i] == "<", let end = Self.tagEnd(in: chars, from: i) {
                flush(&pending)
                handle(tag: String(chars[(i + 1)..<end]))
                i = end + 1
            } else {
                pending.append(chars[i])
                i += 1
            }
        }

        flush(&pending)
        closeBlock()
        return blocks
    }

    /// Index of the `>` that closes the tag opening at `start`, quote-aware so a
    /// `style="a>b"` attribute cannot end the tag early. `nil` for an unterminated tag,
    /// which is then treated as literal text.
    private static func tagEnd(in chars: [Character], from start: Int) -> Int? {
        var quote: Character?
        var i = start + 1
        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == ">" {
                return i
            }
            i += 1
        }
        return nil
    }

    // MARK: Text nodes

    private mutating func flush(_ pending: inout String) {
        defer { pending = "" }
        guard !pending.isEmpty, skipDepth == 0 else { return }

        var text = pending.decodingHTMLEntities().collapsingHTMLWhitespace()
        guard !text.isEmpty else { return }

        if text.hasPrefix(" "), endsAtBlockBoundary {
            text.removeFirst()
            guard !text.isEmpty else { return }
        }

        buffer.append(NSAttributedString(string: text, attributes: attributes(for: currentStyle)))
    }

    private var endsAtBlockBoundary: Bool {
        guard buffer.length > 0 else { return true }
        let last = (buffer.string as NSString).substring(from: buffer.length - 1)
        return last == "\n" || last == " " || last == "\t"
    }

    private var trailingNewlines: Int {
        let string = buffer.string
        var count = 0
        for ch in string.reversed() {
            if ch == "\n" { count += 1 } else if ch == " " || ch == "\t" { continue } else { break }
        }
        return count
    }

    /// Appends a hard line break unless one is already there.
    private mutating func newLine() {
        guard buffer.length > 0 else { return }
        guard trailingNewlines == 0 else { return }
        append(raw: "\n")
    }

    /// Appends a paragraph gap (one blank line) unless one is already there.
    private mutating func newParagraph() {
        guard buffer.length > 0 else { return }
        let existing = trailingNewlines
        guard existing < 2 else { return }
        append(raw: existing == 0 ? "\n\n" : "\n")
    }

    private mutating func append(raw: String) {
        buffer.append(NSAttributedString(string: raw, attributes: attributes(for: currentStyle)))
    }

    // MARK: Tags

    private static let voidTags: Set<String> = [
        "br", "hr", "img", "input", "meta", "link", "source", "col", "area", "base", "wbr"
    ]

    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "aside",
        "ul", "ol", "table", "thead", "tbody", "tfoot", "blockquote", "figure",
        "figcaption", "h1", "h2", "h3", "h4", "h5", "h6", "pre"
    ]

    private mutating func handle(tag raw: String) {
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        // Comments, CDATA, doctype.
        if body.hasPrefix("!") || body.hasPrefix("?") { return }

        if body.hasPrefix("/") {
            close(name: String(body.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased())
            return
        }

        let selfClosing = body.hasSuffix("/")
        let inner = selfClosing ? String(body.dropLast()) : body
        let (name, tagAttributes) = Self.split(tag: inner)
        guard !name.isEmpty else { return }

        if skipDepth > 0 {
            // Only nesting of the skipped element matters while suppressed.
            if name == "style" || name == "script" { skipDepth += 1 }
            return
        }

        open(name: name, attrs: tagAttributes, selfClosing: selfClosing)
    }

    private static func split(tag: String) -> (String, [String: String]) {
        let scalars = Array(tag)
        var i = 0
        var name = ""
        while i < scalars.count, !scalars[i].isWhitespace {
            name.append(scalars[i])
            i += 1
        }
        let rest = String(scalars[min(i, scalars.count)...])
        return (name.lowercased(), rest.isEmpty ? [:] : parseAttributes(rest))
    }

    private static func parseAttributes(_ source: String) -> [String: String] {
        var result: [String: String] = [:]
        let chars = Array(source)
        var i = 0

        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { break }

            var key = ""
            while i < chars.count, chars[i] != "=", !chars[i].isWhitespace {
                key.append(chars[i])
                i += 1
            }
            while i < chars.count, chars[i].isWhitespace { i += 1 }

            guard i < chars.count, chars[i] == "=" else {
                if !key.isEmpty { result[key.lowercased()] = "" }
                continue
            }
            i += 1
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { break }

            var value = ""
            if chars[i] == "\"" || chars[i] == "'" {
                let quote = chars[i]
                i += 1
                while i < chars.count, chars[i] != quote {
                    value.append(chars[i])
                    i += 1
                }
                if i < chars.count { i += 1 }
            } else {
                while i < chars.count, !chars[i].isWhitespace {
                    value.append(chars[i])
                    i += 1
                }
            }

            if !key.isEmpty {
                result[key.lowercased()] = value
            }
        }

        return result
    }

    private mutating func open(name: String, attrs: [String: String], selfClosing: Bool) {
        switch name {
        case "style", "script", "head", "title":
            skipDepth = 1
            return
        case "br":
            newLine()
            return
        case "hr":
            newParagraph()
            append(raw: "———")
            newParagraph()
            return
        case "img":
            emitImage(attrs)
            return
        case "ul", "ol":
            newParagraph()
            lists.append((ordered: name == "ol", counter: 0))
        case "li":
            newLine()
            appendListMarker()
        case "tr":
            newLine()
            cellsInRow = 0
        case "td", "th":
            if cellsInRow > 0 { append(raw: "   ") }
            cellsInRow += 1
        default:
            if Self.blockTags.contains(name) { newParagraph() }
        }

        guard !Self.voidTags.contains(name), !selfClosing else { return }

        var style = currentStyle
        apply(name: name, attrs: attrs, to: &style)
        stack.append((name, style))
    }

    private mutating func appendListMarker() {
        if var list = lists.last {
            list.counter += 1
            lists[lists.count - 1] = list
            let indent = String(repeating: "    ", count: max(lists.count - 1, 0))
            append(raw: list.ordered ? "\(indent)\(list.counter). " : "\(indent)•  ")
        } else {
            append(raw: "•  ")
        }
    }

    private mutating func close(name: String) {
        if skipDepth > 0 {
            if name == "style" || name == "script" || name == "head" || name == "title" {
                skipDepth = max(skipDepth - 1, 0)
            }
            return
        }

        // Unwind to the matching open tag. Arise's HTML is not always balanced, so an
        // unmatched close is ignored rather than dropping the whole style stack.
        if let index = stack.lastIndex(where: { $0.name == name }) {
            stack.removeSubrange(index..<stack.count)
        }

        switch name {
        case "ul", "ol":
            if !lists.isEmpty { lists.removeLast() }
            newParagraph()
        case "li", "tr":
            newLine()
        case "table":
            newParagraph()
        default:
            if Self.blockTags.contains(name) { newParagraph() }
        }
    }

    private mutating func emitImage(_ attrs: [String: String]) {
        let candidates = [attrs["src"], attrs["data-src"], attrs["data-original"], attrs["srcset"]]
        guard let raw = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }),
              let url = Self.imageURL(from: raw) else { return }
        closeBlock()
        blocks.append(.image(index: takeIndex(), url: url))
    }

    private mutating func closeBlock() {
        guard buffer.length > 0 else { return }
        let trimmed = NSMutableAttributedString(attributedString: buffer)
        while trimmed.length > 0,
              let last = (trimmed.string as NSString).substring(from: trimmed.length - 1).first,
              last.isWhitespace || last.isNewline {
            trimmed.deleteCharacters(in: NSRange(location: trimmed.length - 1, length: 1))
        }
        buffer = NSMutableAttributedString()
        guard trimmed.length > 0 else { return }
        blocks.append(.text(index: takeIndex(), string: AttributedString(trimmed)))
    }

    private mutating func takeIndex() -> Int {
        defer { nextIndex += 1 }
        return nextIndex
    }

    /// Question images arrive as absolute CDN links, protocol-relative links, or bare
    /// paths relative to `FirebaseConfig.imageCdnBase`. Base64 data URIs are skipped.
    static func imageURL(from raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // `srcset` is a comma separated candidate list — take the first entry.
        if let comma = value.firstIndex(of: ","), value.lowercased().contains(" ") {
            value = String(value[value.startIndex..<comma])
        }
        value = value.components(separatedBy: .whitespaces).first ?? value
        guard !value.isEmpty, !value.lowercased().hasPrefix("data:") else { return nil }

        if value.hasPrefix("//") {
            value = "https:" + value
        } else if !value.lowercased().hasPrefix("http") {
            let path = value.hasPrefix("/") ? String(value.dropFirst()) : value
            value = FirebaseConfig.imageCdnBase + "/" + path
        }

        if let direct = URL(string: value) { return direct }
        guard let encoded = value.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.urlQueryAllowed.union(.urlPathAllowed)
        ) else { return nil }
        return URL(string: encoded)
    }

    // MARK: Style resolution

    private func apply(name: String, attrs: [String: String], to style: inout InlineStyle) {
        switch name {
        case "b", "strong", "th": style.bold = true
        case "i", "em", "cite", "var", "dfn": style.italic = true
        case "u", "ins": style.underline = true
        case "s", "strike", "del": style.strike = true
        case "sup": style.script = 1
        case "sub": style.script = -1
        case "mark": style.highlighted = true
        case "code", "kbd", "samp", "tt", "pre": style.monospace = true
        case "small": style.sizeScale = 0.86
        case "big": style.sizeScale = 1.12
        case "h1": style.bold = true; style.sizeScale = 1.32
        case "h2": style.bold = true; style.sizeScale = 1.24
        case "h3": style.bold = true; style.sizeScale = 1.16
        case "h4", "h5", "h6": style.bold = true; style.sizeScale = 1.08
        case "a": style.color = MedxTheme.RichText.emphasisBlue; style.underline = true
        case "blockquote": style.italic = true
        default: break
        }

        applyPresentationAttributes(attrs, to: &style)
    }

    private func applyPresentationAttributes(_ attrs: [String: String], to style: inout InlineStyle) {
        if let legacy = attrs["color"], let parsed = UIColor.cssColor(legacy) {
            style.color = Self.mappedForeground(parsed)
        }

        guard let declarations = attrs["style"], !declarations.isEmpty else { return }

        for declaration in declarations.components(separatedBy: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            guard parts.count == 2 else { continue }
            let property = parts[0]
            let value = parts[1]

            switch property {
            case "font-weight":
                if value == "bold" || value == "bolder" || (Int(value) ?? 0) >= 600 {
                    style.bold = true
                } else if value == "normal" || (Int(value) ?? 900) < 500 {
                    style.bold = false
                }
            case "font-style":
                style.italic = (value == "italic" || value == "oblique")
            case "font-family":
                if value.contains("mono") || value.contains("courier") { style.monospace = true }
            case "text-decoration", "text-decoration-line":
                if value.contains("underline") { style.underline = true }
                if value.contains("line-through") { style.strike = true }
                if value.contains("none") { style.underline = false; style.strike = false }
            case "vertical-align":
                if value == "super" { style.script = 1 }
                if value == "sub" { style.script = -1 }
            case "color":
                if let parsed = UIColor.cssColor(value) {
                    style.color = Self.mappedForeground(parsed)
                }
            case "background-color", "background":
                // Any authored highlight becomes *the* app highlight. A white or
                // near-white background on white text is the exact combination that
                // made words vanish in Dark Mode.
                if let parsed = UIColor.cssColor(value), parsed.medxAlpha > 0.05 {
                    style.highlighted = true
                }
            default:
                break
            }
        }
    }

    /// Snaps an authored colour to a dynamic system colour, or to `nil` meaning "just use
    /// the label colour". Greys, whites and blacks all fall through to `nil`, which is
    /// what fixes text authored as `color:#fff` for a white web page.
    static func mappedForeground(_ color: UIColor) -> UIColor? {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return nil
        }
        guard alpha > 0.15, saturation >= 0.30, brightness >= 0.18 else { return nil }

        switch hue {
        case ..<0.045, 0.925...:
            return MedxTheme.RichText.emphasisRed
        case ..<0.185:
            // Includes yellow, which is unreadable as text on either background.
            return MedxTheme.RichText.emphasisOrange
        case ..<0.47:
            return MedxTheme.RichText.emphasisGreen
        case ..<0.76:
            return MedxTheme.RichText.emphasisBlue
        default:
            return MedxTheme.RichText.emphasisPurple
        }
    }

    private func attributes(for style: InlineStyle) -> [NSAttributedString.Key: Any] {
        let size = fontSize * style.sizeScale * (style.script == 0 ? 1 : 0.74)
        let resolvedWeight: UIFont.Weight = style.bold ? .bold : weight

        var font = style.monospace
            ? UIFont.monospacedSystemFont(ofSize: size, weight: resolvedWeight)
            : UIFont.systemFont(ofSize: size, weight: resolvedWeight)

        if style.italic {
            let descriptor = font.fontDescriptor.withSymbolicTraits(
                font.fontDescriptor.symbolicTraits.union(.traitItalic)
            )
            if let descriptor { font = UIFont(descriptor: descriptor, size: size) }
        }

        var attributes: [NSAttributedString.Key: Any] = [.font: font]

        if style.highlighted {
            attributes[.backgroundColor] = resolve(MedxTheme.RichText.highlightBackground)
            attributes[.foregroundColor] = resolve(MedxTheme.RichText.highlightForeground)
        } else {
            attributes[.foregroundColor] = resolve(style.color ?? baseColor)
        }

        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if style.script != 0 {
            attributes[.baselineOffset] = size * (style.script > 0 ? 0.34 : -0.20)
        }

        return attributes
    }

    // MARK: Whitespace helpers live on String below.
}

// MARK: - String helpers

extension String {
    /// Collapses every run of HTML whitespace to a single space, matching how a browser
    /// lays the same markup out. Explicit breaks come from `<br>` / block tags instead.
    func collapsingHTMLWhitespace() -> String {
        var result = ""
        result.reserveCapacity(count)
        var pendingSpace = false

        for character in self {
            if character.isWhitespace || character.isNewline {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace {
                    result.append(" ")
                    pendingSpace = false
                }
                result.append(character)
            }
        }

        if pendingSpace { result.append(" ") }
        return result
    }

    /// Named and numeric HTML entities. The named table covers what shows up in medical
    /// question text — Greek letters, arrows, degrees, en/em dashes, typographic quotes.
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }

        var result = ""
        result.reserveCapacity(count)
        var index = startIndex

        while index < endIndex {
            let character = self[index]
            guard character == "&" else {
                result.append(character)
                index = self.index(after: index)
                continue
            }

            let searchEnd = self.index(index, offsetBy: 12, limitedBy: endIndex) ?? endIndex
            guard let semicolon = self[index..<searchEnd].firstIndex(of: ";") else {
                result.append(character)
                index = self.index(after: index)
                continue
            }

            let entity = String(self[self.index(after: index)..<semicolon])
            if let decoded = Self.decode(entity: entity) {
                result.append(decoded)
                index = self.index(after: semicolon)
            } else {
                result.append(character)
                index = self.index(after: index)
            }
        }

        return result
    }

    private static func decode(entity: String) -> String? {
        if entity.hasPrefix("#") {
            let digits = entity.dropFirst()
            let scalarValue: UInt32?
            if digits.lowercased().hasPrefix("x") {
                scalarValue = UInt32(digits.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(digits)
            }
            guard let value = scalarValue, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return htmlEntityTable[entity] ?? htmlEntityTable[entity.lowercased()]
    }
}

private let htmlEntityTable: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    "ensp": " ", "emsp": " ", "thinsp": " ", "shy": "", "zwnj": "", "zwj": "",
    "copy": "©", "reg": "®", "trade": "™", "deg": "°", "plusmn": "±", "micro": "µ",
    "middot": "·", "bull": "•", "hellip": "…", "prime": "′", "Prime": "″",
    "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
    "ldquo": "“", "rdquo": "”", "bdquo": "„", "dagger": "†", "Dagger": "‡",
    "permil": "‰", "lsaquo": "‹", "rsaquo": "›", "euro": "€", "pound": "£",
    "yen": "¥", "cent": "¢", "sect": "§", "para": "¶", "laquo": "«", "raquo": "»",
    "times": "×", "divide": "÷", "frac12": "½", "frac14": "¼", "frac34": "¾",
    "sup1": "¹", "sup2": "²", "sup3": "³", "ordm": "º", "ordf": "ª",
    "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔",
    "lArr": "⇐", "uArr": "⇑", "rArr": "⇒", "dArr": "⇓", "hArr": "⇔",
    "forall": "∀", "part": "∂", "exist": "∃", "empty": "∅", "nabla": "∇",
    "isin": "∈", "notin": "∉", "ni": "∋", "prod": "∏", "sum": "∑",
    "minus": "−", "lowast": "∗", "radic": "√", "prop": "∝", "infin": "∞",
    "ang": "∠", "and": "∧", "or": "∨", "cap": "∩", "cup": "∪", "int": "∫",
    "there4": "∴", "sim": "∼", "cong": "≅", "asymp": "≈", "ne": "≠",
    "equiv": "≡", "le": "≤", "ge": "≥", "sub": "⊂", "sup": "⊃", "nsub": "⊄",
    "sube": "⊆", "supe": "⊇", "oplus": "⊕", "otimes": "⊗", "perp": "⊥",
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
    "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
    "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο", "pi": "π",
    "rho": "ρ", "sigmaf": "ς", "sigma": "σ", "tau": "τ", "upsilon": "υ",
    "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
    "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε",
    "Zeta": "Ζ", "Eta": "Η", "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ",
    "Lambda": "Λ", "Mu": "Μ", "Nu": "Ν", "Xi": "Ξ", "Omicron": "Ο", "Pi": "Π",
    "Rho": "Ρ", "Sigma": "Σ", "Tau": "Τ", "Upsilon": "Υ", "Phi": "Φ",
    "Chi": "Χ", "Psi": "Ψ", "Omega": "Ω",
    "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä",
    "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "iacute": "í",
    "oacute": "ó", "ouml": "ö", "uacute": "ú", "uuml": "ü", "ntilde": "ñ",
    "ccedil": "ç", "szlig": "ß", "aring": "å", "aelig": "æ", "oslash": "ø"
]

// MARK: - CSS colour parsing

extension UIColor {
    var medxAlpha: CGFloat {
        cgColor.alpha
    }

    /// Parses the colour syntaxes a web editor actually produces: hex (3/4/6/8 digit),
    /// `rgb()` / `rgba()`, and the common named colours.
    static func cssColor(_ raw: String) -> UIColor? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        if value == "transparent" || value == "none" || value == "inherit" || value == "initial" {
            return nil
        }

        if value.hasPrefix("#") {
            return hexColor(String(value.dropFirst()))
        }

        if value.hasPrefix("rgb") {
            let inside = value
                .replacingOccurrences(of: "rgba", with: "")
                .replacingOccurrences(of: "rgb", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            let parts = inside
                .components(separatedBy: CharacterSet(charactersIn: ",/ "))
                .filter { !$0.isEmpty }
            guard parts.count >= 3,
                  let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]) else {
                return nil
            }
            let a = parts.count > 3 ? (Double(parts[3]) ?? 1) : 1
            return UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
        }

        // A `background:` shorthand can carry more than a colour; pick the first token
        // that parses as one.
        if value.contains(" ") {
            for token in value.components(separatedBy: " ") where !token.isEmpty {
                if let parsed = cssColor(token) { return parsed }
            }
            return nil
        }

        guard let hex = cssNamedColors[value] else { return nil }
        return hexColor(hex)
    }

    private static func hexColor(_ digits: String) -> UIColor? {
        let cleaned = digits.filter { $0.isHexDigit }
        var expanded = cleaned
        if cleaned.count == 3 || cleaned.count == 4 {
            expanded = cleaned.map { "\($0)\($0)" }.joined()
        }
        guard expanded.count == 6 || expanded.count == 8, let value = UInt64(expanded, radix: 16) else {
            return nil
        }
        if expanded.count == 6 {
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
        return UIColor(
            red: CGFloat((value >> 24) & 0xFF) / 255,
            green: CGFloat((value >> 16) & 0xFF) / 255,
            blue: CGFloat((value >> 8) & 0xFF) / 255,
            alpha: CGFloat(value & 0xFF) / 255
        )
    }
}

private let cssNamedColors: [String: String] = [
    "white": "ffffff", "black": "000000", "red": "ff0000", "green": "008000",
    "blue": "0000ff", "yellow": "ffff00", "orange": "ffa500", "purple": "800080",
    "gray": "808080", "grey": "808080", "silver": "c0c0c0", "maroon": "800000",
    "olive": "808000", "lime": "00ff00", "aqua": "00ffff", "cyan": "00ffff",
    "teal": "008080", "navy": "000080", "fuchsia": "ff00ff", "magenta": "ff00ff",
    "pink": "ffc0cb", "brown": "a52a2a", "gold": "ffd700", "indigo": "4b0082",
    "violet": "ee82ee", "crimson": "dc143c", "darkred": "8b0000",
    "darkgreen": "006400", "darkblue": "00008b", "lightgray": "d3d3d3",
    "lightgrey": "d3d3d3", "whitesmoke": "f5f5f5", "ivory": "fffff0",
    "beige": "f5f5dc", "khaki": "f0e68c", "salmon": "fa8072", "coral": "ff7f50",
    "tomato": "ff6347", "royalblue": "4169e1", "steelblue": "4682b4",
    "skyblue": "87ceeb", "lightblue": "add8e6", "seagreen": "2e8b57",
    "forestgreen": "228b22", "yellowgreen": "9acd32", "chocolate": "d2691e"
]

