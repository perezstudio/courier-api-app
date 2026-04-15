import AppKit

enum SyntaxLanguage {
    case json
    case xml // covers HTML too
    case plain

    static func detect(from contentType: String) -> SyntaxLanguage {
        let ct = contentType.lowercased()
        if ct.contains("json") || ct.contains("javascript") {
            return .json
        } else if ct.contains("xml") || ct.contains("html") || ct.contains("xhtml") {
            return .xml
        }
        return .plain
    }
}

enum SyntaxHighlighter {

    // MARK: - Theme (adapts to dark/light mode)

    private static var keyColor: NSColor { .systemBlue }
    private static var stringColor: NSColor { .systemGreen }
    private static var numberColor: NSColor { .systemOrange }
    private static var boolNullColor: NSColor { .systemPurple }
    private static var punctuationColor: NSColor { NSColor.secondaryLabelColor }
    private static var tagColor: NSColor { .systemBlue }
    private static var attrNameColor: NSColor { .systemOrange }
    private static var attrValueColor: NSColor { .systemGreen }
    private static var commentColor: NSColor { .systemGray }
    private static var defaultColor: NSColor { .labelColor }

    static func highlight(_ text: String, language: SyntaxLanguage, font: NSFont) -> NSAttributedString {
        switch language {
        case .json: return highlightJSON(text, font: font)
        case .xml: return highlightXML(text, font: font)
        case .plain: return plainText(text, font: font)
        }
    }

    // MARK: - Plain

    private static func plainText(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: defaultColor,
        ])
    }

    // MARK: - JSON

    private static func highlightJSON(_ text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: defaultColor,
        ])
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Strings (keys and values)
        let stringPattern = #""(?:[^"\\]|\\.)*""#
        if let regex = try? NSRegularExpression(pattern: stringPattern) {
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                let range = match.range
                // Determine if this is a key (followed by optional whitespace then colon)
                let afterEnd = range.location + range.length
                var isKey = false
                if afterEnd < ns.length {
                    let remaining = ns.substring(from: afterEnd)
                    let trimmed = remaining.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix(":") {
                        isKey = true
                    }
                }
                result.addAttribute(.foregroundColor, value: isKey ? keyColor : stringColor, range: range)
            }
        }

        // Numbers (standalone, not inside strings)
        let numberPattern = #"(?<=[\s,\[\{:])-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#
        if let regex = try? NSRegularExpression(pattern: numberPattern) {
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                // Verify not inside a string by checking if an odd number of unescaped quotes precede
                if !isInsideString(text: ns, location: match.range.location) {
                    result.addAttribute(.foregroundColor, value: numberColor, range: match.range)
                }
            }
        }

        // Booleans and null
        let boolNullPattern = #"\b(?:true|false|null)\b"#
        if let regex = try? NSRegularExpression(pattern: boolNullPattern) {
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                if !isInsideString(text: ns, location: match.range.location) {
                    result.addAttribute(.foregroundColor, value: boolNullColor, range: match.range)
                }
            }
        }

        // Punctuation: { } [ ] : ,
        let punctPattern = #"[\{\}\[\]:,]"#
        if let regex = try? NSRegularExpression(pattern: punctPattern) {
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                if !isInsideString(text: ns, location: match.range.location) {
                    result.addAttribute(.foregroundColor, value: punctuationColor, range: match.range)
                }
            }
        }

        return result
    }

    /// Quick heuristic: count unescaped quotes before the location
    private static func isInsideString(text: NSString, location: Int) -> Bool {
        var quoteCount = 0
        var i = 0
        let str = text as String
        let chars = Array(str.utf16)
        let quote: UTF16.CodeUnit = 0x22 // "
        let backslash: UTF16.CodeUnit = 0x5C // \

        while i < location && i < chars.count {
            if chars[i] == quote {
                // Check if escaped
                var backslashes = 0
                var j = i - 1
                while j >= 0 && chars[j] == backslash {
                    backslashes += 1
                    j -= 1
                }
                if backslashes % 2 == 0 {
                    quoteCount += 1
                }
            }
            i += 1
        }
        return quoteCount % 2 == 1
    }

    // MARK: - XML / HTML

    private static func highlightXML(_ text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: defaultColor,
        ])
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Comments: <!-- ... -->
        let commentPattern = #"<!--[\s\S]*?-->"#
        if let regex = try? NSRegularExpression(pattern: commentPattern, options: .dotMatchesLineSeparators) {
            for match in regex.matches(in: text, range: fullRange) {
                result.addAttribute(.foregroundColor, value: commentColor, range: match.range)
            }
        }

        // Tags: < ... > including closing tags and self-closing
        let tagPattern = #"</?[\w][\w\-:.]*(?:\s[^>]*)?\s*/?>"#
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                let tagStr = ns.substring(with: match.range)
                let tagRange = match.range

                // Color the angle brackets and tag name
                // Tag name pattern within this match
                let namePattern = #"</?[\w][\w\-:.]*"#
                if let nameRegex = try? NSRegularExpression(pattern: namePattern) {
                    let localRange = NSRange(location: 0, length: (tagStr as NSString).length)
                    if let nameMatch = nameRegex.firstMatch(in: tagStr, range: localRange) {
                        let globalRange = NSRange(
                            location: tagRange.location + nameMatch.range.location,
                            length: nameMatch.range.length
                        )
                        result.addAttribute(.foregroundColor, value: tagColor, range: globalRange)
                    }
                }

                // Closing bracket(s)
                let closingPattern = #"/?>$"#
                if let closeRegex = try? NSRegularExpression(pattern: closingPattern) {
                    let localRange = NSRange(location: 0, length: (tagStr as NSString).length)
                    if let closeMatch = closeRegex.firstMatch(in: tagStr, range: localRange) {
                        let globalRange = NSRange(
                            location: tagRange.location + closeMatch.range.location,
                            length: closeMatch.range.length
                        )
                        result.addAttribute(.foregroundColor, value: tagColor, range: globalRange)
                    }
                }

                // Attribute names
                let attrNamePattern = #"\s([\w\-:.]+)\s*="#
                if let attrRegex = try? NSRegularExpression(pattern: attrNamePattern) {
                    let localRange = NSRange(location: 0, length: (tagStr as NSString).length)
                    for attrMatch in attrRegex.matches(in: tagStr, range: localRange) {
                        if attrMatch.numberOfRanges > 1 {
                            let nameRange = attrMatch.range(at: 1)
                            let globalRange = NSRange(
                                location: tagRange.location + nameRange.location,
                                length: nameRange.length
                            )
                            result.addAttribute(.foregroundColor, value: attrNameColor, range: globalRange)
                        }
                    }
                }

                // Attribute values (quoted)
                let attrValuePattern = #"=\s*("[^"]*"|'[^']*')"#
                if let valRegex = try? NSRegularExpression(pattern: attrValuePattern) {
                    let localRange = NSRange(location: 0, length: (tagStr as NSString).length)
                    for valMatch in valRegex.matches(in: tagStr, range: localRange) {
                        if valMatch.numberOfRanges > 1 {
                            let valRange = valMatch.range(at: 1)
                            let globalRange = NSRange(
                                location: tagRange.location + valRange.location,
                                length: valRange.length
                            )
                            result.addAttribute(.foregroundColor, value: attrValueColor, range: globalRange)
                        }
                    }
                }
            }
        }

        // CDATA sections
        let cdataPattern = #"<!\[CDATA\[[\s\S]*?\]\]>"#
        if let regex = try? NSRegularExpression(pattern: cdataPattern, options: .dotMatchesLineSeparators) {
            for match in regex.matches(in: text, range: fullRange) {
                result.addAttribute(.foregroundColor, value: commentColor, range: match.range)
            }
        }

        return result
    }
}
