import AppKit

/// Token-level highlighting for JSON and XML.
///
/// A hand-written scanner rather than regular expressions: it is a single pass,
/// it cannot backtrack pathologically on a large minified body, and it can tell
/// a key from a string value — which a regex over `"..."` cannot.
nonisolated struct SyntaxHighlighter {

    enum Language {
        case json
        case xml
    }

    enum TokenKind {
        case key
        case string
        case number
        case literal      // true / false / null
        case punctuation
        case tag
        case attribute
        case comment
    }

    struct Token {
        let range: NSRange
        let kind: TokenKind
    }

    let language: Language

    static func color(for kind: TokenKind) -> NSColor {
        // System colors so Dark Mode and Increase Contrast are handled for us.
        switch kind {
        case .key, .tag: .systemBlue
        case .string: .systemRed
        case .number: .systemPurple
        case .literal: .systemOrange
        case .attribute: .systemTeal
        case .comment: .secondaryLabelColor
        case .punctuation: .tertiaryLabelColor
        }
    }

    func tokens(in text: String) -> [Token] {
        switch language {
        case .json: jsonTokens(in: text)
        case .xml: xmlTokens(in: text)
        }
    }

    // MARK: - JSON

    private func jsonTokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text.utf16)
        var index = 0

        func isDigitStart(_ unit: UInt16) -> Bool {
            (unit >= 48 && unit <= 57) || unit == 45  // 0-9 or '-'
        }

        while index < characters.count {
            let unit = characters[index]

            switch unit {
            case 34:  // "
                let start = index
                index += 1
                while index < characters.count {
                    if characters[index] == 92 {  // backslash escapes the next unit
                        index += 2
                        continue
                    }
                    if characters[index] == 34 { break }
                    index += 1
                }
                index = min(index + 1, characters.count)

                // A string followed by ':' is an object key, not a value.
                var lookahead = index
                while lookahead < characters.count,
                      characters[lookahead] == 32 || characters[lookahead] == 9
                        || characters[lookahead] == 10 || characters[lookahead] == 13 {
                    lookahead += 1
                }
                let isKey = lookahead < characters.count && characters[lookahead] == 58  // ':'
                tokens.append(
                    Token(range: NSRange(location: start, length: index - start), kind: isKey ? .key : .string)
                )

            case 123, 125, 91, 93, 58, 44:  // { } [ ] : ,
                tokens.append(Token(range: NSRange(location: index, length: 1), kind: .punctuation))
                index += 1

            case let value where isDigitStart(value):
                let start = index
                while index < characters.count {
                    let current = characters[index]
                    let isNumeric = (current >= 48 && current <= 57)
                        || current == 46 || current == 45 || current == 43
                        || current == 101 || current == 69  // e / E
                    if !isNumeric { break }
                    index += 1
                }
                tokens.append(
                    Token(range: NSRange(location: start, length: index - start), kind: .number)
                )

            case 116, 102, 110:  // t / f / n
                let start = index
                while index < characters.count,
                      characters[index] >= 97, characters[index] <= 122 {
                    index += 1
                }
                let length = index - start
                if length > 1 {
                    tokens.append(Token(range: NSRange(location: start, length: length), kind: .literal))
                }

            default:
                index += 1
            }
        }

        return tokens
    }

    // MARK: - XML

    private func xmlTokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text.utf16)
        var index = 0

        while index < characters.count {
            guard characters[index] == 60 else {  // '<'
                index += 1
                continue
            }

            let tagStart = index

            // Comments run to '-->' and swallow everything, including quotes.
            if index + 3 < characters.count,
               characters[index + 1] == 33, characters[index + 2] == 45, characters[index + 3] == 45 {
                var end = index + 4
                while end + 2 < characters.count {
                    if characters[end] == 45, characters[end + 1] == 45, characters[end + 2] == 62 {
                        end += 3
                        break
                    }
                    end += 1
                }
                let stop = min(end, characters.count)
                tokens.append(
                    Token(range: NSRange(location: tagStart, length: stop - tagStart), kind: .comment)
                )
                index = stop
                continue
            }

            // Tag name.
            index += 1
            if index < characters.count, characters[index] == 47 { index += 1 }  // '/'
            let nameStart = index
            while index < characters.count {
                let current = characters[index]
                if current == 32 || current == 62 || current == 47 || current == 10 || current == 9 {
                    break
                }
                index += 1
            }
            if index > nameStart {
                tokens.append(
                    Token(range: NSRange(location: nameStart, length: index - nameStart), kind: .tag)
                )
            }

            // Attributes up to '>'.
            while index < characters.count, characters[index] != 62 {
                if characters[index] == 34 || characters[index] == 39 {
                    let quote = characters[index]
                    let start = index
                    index += 1
                    while index < characters.count, characters[index] != quote { index += 1 }
                    index = min(index + 1, characters.count)
                    tokens.append(
                        Token(range: NSRange(location: start, length: index - start), kind: .string)
                    )
                    continue
                }

                if isAttributeStart(characters[index]) {
                    let start = index
                    while index < characters.count, isAttributeBody(characters[index]) { index += 1 }
                    tokens.append(
                        Token(range: NSRange(location: start, length: index - start), kind: .attribute)
                    )
                    continue
                }

                index += 1
            }
            index = min(index + 1, characters.count)
        }

        return tokens
    }

    private func isAttributeStart(_ unit: UInt16) -> Bool {
        (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) || unit == 95
    }

    private func isAttributeBody(_ unit: UInt16) -> Bool {
        isAttributeStart(unit) || (unit >= 48 && unit <= 57) || unit == 45 || unit == 58
    }
}
