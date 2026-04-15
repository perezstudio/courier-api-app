import AppKit

enum SyntaxLanguage: String, CustomStringConvertible {
    case json
    case xml
    case plain

    var description: String { rawValue }

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

    // MARK: - Theme

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

    /// Archive an NSAttributedString to Data for SwiftData storage.
    static func archive(_ attributedString: NSAttributedString) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: attributedString, requiringSecureCoding: false)
    }

    /// Unarchive Data back to NSAttributedString.
    static func unarchive(_ data: Data) -> NSAttributedString? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data)
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

        // Single pass: find all string ranges for O(1) inside-string checks
        let stringPattern = #""(?:[^"\\]|\\.)*""#
        guard let stringRegex = try? NSRegularExpression(pattern: stringPattern) else { return result }
        let stringMatches = stringRegex.matches(in: text, range: fullRange)

        // Build sorted array of string ranges for binary search
        let stringRanges = stringMatches.map { $0.range }

        // Color strings (keys vs values)
        for match in stringMatches {
            let range = match.range
            let afterEnd = range.location + range.length
            var isKey = false
            if afterEnd < ns.length {
                // Scan forward past whitespace looking for colon
                var idx = afterEnd
                while idx < ns.length {
                    let ch = ns.character(at: idx)
                    if ch == 0x3A { // ':'
                        isKey = true
                        break
                    } else if ch != 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D { // not whitespace
                        break
                    }
                    idx += 1
                }
            }
            result.addAttribute(.foregroundColor, value: isKey ? keyColor : stringColor, range: range)
        }

        // Numbers
        let numberPattern = #"(?<=[\s,\[\{:])-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#
        if let regex = try? NSRegularExpression(pattern: numberPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                if !isInsideStringRanges(location: match.range.location, stringRanges: stringRanges) {
                    result.addAttribute(.foregroundColor, value: numberColor, range: match.range)
                }
            }
        }

        // Booleans and null
        let boolNullPattern = #"\b(?:true|false|null)\b"#
        if let regex = try? NSRegularExpression(pattern: boolNullPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                if !isInsideStringRanges(location: match.range.location, stringRanges: stringRanges) {
                    result.addAttribute(.foregroundColor, value: boolNullColor, range: match.range)
                }
            }
        }

        // Punctuation
        let punctPattern = #"[\{\}\[\]:,]"#
        if let regex = try? NSRegularExpression(pattern: punctPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                if !isInsideStringRanges(location: match.range.location, stringRanges: stringRanges) {
                    result.addAttribute(.foregroundColor, value: punctuationColor, range: match.range)
                }
            }
        }

        return result
    }

    /// O(log n) binary search into precomputed string ranges.
    private static func isInsideStringRanges(location: Int, stringRanges: [NSRange]) -> Bool {
        var lo = 0
        var hi = stringRanges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let range = stringRanges[mid]
            if location < range.location {
                hi = mid - 1
            } else if location >= range.location + range.length {
                lo = mid + 1
            } else {
                return true
            }
        }
        return false
    }

    // MARK: - XML / HTML

    private static func highlightXML(_ text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: defaultColor,
        ])
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Comments
        let commentPattern = #"<!--[\s\S]*?-->"#
        if let regex = try? NSRegularExpression(pattern: commentPattern, options: .dotMatchesLineSeparators) {
            for match in regex.matches(in: text, range: fullRange) {
                result.addAttribute(.foregroundColor, value: commentColor, range: match.range)
            }
        }

        // Tags
        let tagPattern = #"</?[\w][\w\-:.]*(?:\s[^>]*)?\s*/?>"#
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                let tagStr = ns.substring(with: match.range)
                let tagNS = tagStr as NSString
                let tagRange = match.range
                let localRange = NSRange(location: 0, length: tagNS.length)

                // Tag name
                let namePattern = #"</?[\w][\w\-:.]*"#
                if let nameRegex = try? NSRegularExpression(pattern: namePattern),
                   let nameMatch = nameRegex.firstMatch(in: tagStr, range: localRange) {
                    let globalRange = NSRange(
                        location: tagRange.location + nameMatch.range.location,
                        length: nameMatch.range.length
                    )
                    result.addAttribute(.foregroundColor, value: tagColor, range: globalRange)
                }

                // Closing bracket
                let closingPattern = #"/?>$"#
                if let closeRegex = try? NSRegularExpression(pattern: closingPattern),
                   let closeMatch = closeRegex.firstMatch(in: tagStr, range: localRange) {
                    let globalRange = NSRange(
                        location: tagRange.location + closeMatch.range.location,
                        length: closeMatch.range.length
                    )
                    result.addAttribute(.foregroundColor, value: tagColor, range: globalRange)
                }

                // Attribute names
                let attrNamePattern = #"\s([\w\-:.]+)\s*="#
                if let attrRegex = try? NSRegularExpression(pattern: attrNamePattern) {
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

                // Attribute values
                let attrValuePattern = #"=\s*("[^"]*"|'[^']*')"#
                if let valRegex = try? NSRegularExpression(pattern: attrValuePattern) {
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

        // CDATA
        let cdataPattern = #"<!\[CDATA\[[\s\S]*?\]\]>"#
        if let regex = try? NSRegularExpression(pattern: cdataPattern, options: .dotMatchesLineSeparators) {
            for match in regex.matches(in: text, range: fullRange) {
                result.addAttribute(.foregroundColor, value: commentColor, range: match.range)
            }
        }

        return result
    }
}
