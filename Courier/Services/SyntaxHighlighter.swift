import AppKit

// MARK: - Language Detection

enum SyntaxLanguage {
    case json
    case xml

    static func detect(from contentType: String) -> SyntaxLanguage {
        let ct = contentType.lowercased()
        if ct.contains("xml") || ct.contains("html") || ct.contains("xhtml") {
            return .xml
        }
        return .json
    }
}

// MARK: - Theme

struct SyntaxTheme {
    let jsonKey: NSColor
    let jsonString: NSColor
    let jsonNumber: NSColor
    let jsonBoolNull: NSColor
    let jsonPunctuation: NSColor
    let xmlTag: NSColor
    let xmlAttrName: NSColor
    let xmlAttrValue: NSColor
    let xmlComment: NSColor
    let defaultColor: NSColor
    let font: NSFont

    static func current(font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)) -> SyntaxTheme {
        SyntaxTheme(
            jsonKey: .systemBlue,
            jsonString: .systemGreen,
            jsonNumber: .systemOrange,
            jsonBoolNull: .systemPurple,
            jsonPunctuation: .secondaryLabelColor,
            xmlTag: .systemBlue,
            xmlAttrName: .systemOrange,
            xmlAttrValue: .systemGreen,
            xmlComment: .systemGray,
            defaultColor: .labelColor,
            font: font
        )
    }
}

// MARK: - Highlighter

final class SyntaxHighlighter {
    let theme: SyntaxTheme
    let language: SyntaxLanguage

    // Pre-compiled regexes
    private let jsonTokenRegex: NSRegularExpression?
    private let xmlCommentRegex: NSRegularExpression?
    private let xmlTagRegex: NSRegularExpression?
    private let xmlAttrNameRegex: NSRegularExpression?
    private let xmlAttrValueRegex: NSRegularExpression?

    init(theme: SyntaxTheme, language: SyntaxLanguage) {
        self.theme = theme
        self.language = language

        // JSON: match strings (with optional colon after for keys), numbers, bools/null, punctuation
        // Group 1: quoted string, Group 2: colon (if key), Group 3: number, Group 4: bool/null, Group 5: punctuation
        self.jsonTokenRegex = try? NSRegularExpression(
            pattern: #"("(?:[^"\\]|\\.)*")\s*(:)?|(-?\b(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|(\btrue\b|\bfalse\b|\bnull\b)|([{}\[\]:,])"#
        )

        self.xmlCommentRegex = try? NSRegularExpression(
            pattern: #"<!--[\s\S]*?-->"#,
            options: .dotMatchesLineSeparators
        )
        self.xmlTagRegex = try? NSRegularExpression(
            pattern: #"</?[\w][\w\-:.]*|/?>"#
        )
        self.xmlAttrNameRegex = try? NSRegularExpression(
            pattern: #"(?<=\s)([\w\-:.]+)\s*="#
        )
        self.xmlAttrValueRegex = try? NSRegularExpression(
            pattern: #"=\s*("[^"]*"|'[^']*')"#
        )
    }

    /// Highlight a range within an NSTextStorage. Expands to line boundaries internally.
    func highlight(_ textStorage: NSTextStorage, in requestedRange: NSRange) {
        let string = textStorage.string as NSString
        let fullLength = string.length
        guard fullLength > 0, requestedRange.location < fullLength else { return }

        // Clamp and expand to line boundaries
        let clampedRange = NSIntersectionRange(requestedRange, NSRange(location: 0, length: fullLength))
        let lineRange = string.lineRange(for: clampedRange)
        guard lineRange.length > 0 else { return }

        textStorage.beginEditing()

        // Reset to default attributes in the range first
        textStorage.addAttributes([
            .foregroundColor: theme.defaultColor,
            .font: theme.font,
        ], range: lineRange)

        switch language {
        case .json:
            highlightJSON(textStorage, in: lineRange)
        case .xml:
            highlightXML(textStorage, in: lineRange)
        }

        textStorage.endEditing()
    }

    // MARK: - JSON

    private func highlightJSON(_ textStorage: NSTextStorage, in range: NSRange) {
        guard let regex = jsonTokenRegex else { return }
        let string = textStorage.string

        regex.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match else { return }

            // Group 1: quoted string
            if match.range(at: 1).location != NSNotFound {
                let stringRange = match.range(at: 1)
                let hasColon = match.range(at: 2).location != NSNotFound
                let color = hasColon ? theme.jsonKey : theme.jsonString
                textStorage.addAttribute(.foregroundColor, value: color, range: stringRange)
            }
            // Group 3: number
            else if match.range(at: 3).location != NSNotFound {
                textStorage.addAttribute(.foregroundColor, value: theme.jsonNumber, range: match.range(at: 3))
            }
            // Group 4: bool/null
            else if match.range(at: 4).location != NSNotFound {
                textStorage.addAttribute(.foregroundColor, value: theme.jsonBoolNull, range: match.range(at: 4))
            }
            // Group 5: punctuation
            else if match.range(at: 5).location != NSNotFound {
                textStorage.addAttribute(.foregroundColor, value: theme.jsonPunctuation, range: match.range(at: 5))
            }
        }
    }

    // MARK: - XML / HTML

    private func highlightXML(_ textStorage: NSTextStorage, in range: NSRange) {
        let string = textStorage.string

        // Comments first (they override everything inside)
        xmlCommentRegex?.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match else { return }
            textStorage.addAttribute(.foregroundColor, value: theme.xmlComment, range: match.range)
        }

        // Collect comment ranges for exclusion
        var commentRanges: [NSRange] = []
        xmlCommentRegex?.enumerateMatches(in: string, range: range) { match, _, _ in
            if let match { commentRanges.append(match.range) }
        }

        // Tags (opening/closing tag names and brackets)
        xmlTagRegex?.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match else { return }
            if !Self.isInsideAny(location: match.range.location, ranges: commentRanges) {
                textStorage.addAttribute(.foregroundColor, value: theme.xmlTag, range: match.range)
            }
        }

        // Attribute names
        xmlAttrNameRegex?.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let nameRange = match.range(at: 1)
            if !Self.isInsideAny(location: nameRange.location, ranges: commentRanges) {
                textStorage.addAttribute(.foregroundColor, value: theme.xmlAttrName, range: nameRange)
            }
        }

        // Attribute values
        xmlAttrValueRegex?.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let valRange = match.range(at: 1)
            if !Self.isInsideAny(location: valRange.location, ranges: commentRanges) {
                textStorage.addAttribute(.foregroundColor, value: theme.xmlAttrValue, range: valRange)
            }
        }
    }

    private static func isInsideAny(location: Int, ranges: [NSRange]) -> Bool {
        for r in ranges {
            if location >= r.location && location < r.location + r.length {
                return true
            }
        }
        return false
    }
}
