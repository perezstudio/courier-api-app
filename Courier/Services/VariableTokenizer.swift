import Foundation

/// Finds `{{variable}}` placeholders in a string.
///
/// Used to highlight them in the URL bar and body editor, and by the resolver
/// in Phase 6. Kept free of any AppKit dependency so it can be tested directly.
nonisolated enum VariableTokenizer {

    struct Token: Equatable {
        /// Range of the whole placeholder, braces included.
        let range: Range<String.Index>
        /// The name between the braces, trimmed.
        let name: String
    }

    /// All placeholders, in order. Unclosed `{{` is ignored rather than
    /// treated as running to the end of the string — a half-typed placeholder
    /// should not highlight the rest of the URL.
    static func tokens(in string: String) -> [Token] {
        var tokens: [Token] = []
        var searchStart = string.startIndex

        while let open = string.range(of: "{{", range: searchStart..<string.endIndex) {
            guard let close = string.range(of: "}}", range: open.upperBound..<string.endIndex) else {
                break
            }
            let name = String(string[open.upperBound..<close.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            tokens.append(Token(range: open.lowerBound..<close.upperBound, name: name))
            searchStart = close.upperBound
        }

        return tokens
    }

    /// Placeholder names, deduplicated, preserving first-seen order.
    static func names(in string: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for token in tokens(in: string) where !token.name.isEmpty {
            if seen.insert(token.name).inserted {
                ordered.append(token.name)
            }
        }
        return ordered
    }

    /// `NSRange`s for the placeholders, for attributed-string highlighting.
    static func nsRanges(in string: String) -> [NSRange] {
        tokens(in: string).map { NSRange($0.range, in: string) }
    }
}
