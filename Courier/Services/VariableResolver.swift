import Foundation

/// Resolves `{{variable}}` placeholders before a request is sent.
///
/// Scopes, highest priority first: **request → environment → collection →
/// global** (REQUIREMENTS.md §8.6). Building the lookup once per send and
/// reusing it keeps resolution linear in the number of placeholders.
nonisolated enum VariableResolver {

    /// The scopes a value can come from, ordered by precedence.
    enum Scope: Int, CaseIterable, Sendable, Comparable {
        case request = 0
        case environment = 1
        case collection = 2
        case global = 3

        static func < (lhs: Scope, rhs: Scope) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var displayName: String {
            switch self {
            case .request: "Request"
            case .environment: "Environment"
            case .collection: "Collection"
            case .global: "Global"
            }
        }
    }

    struct Binding: Sendable, Equatable {
        let value: String
        let scope: Scope
    }

    /// A flattened lookup, already reduced to the winning binding per name.
    struct Context: Sendable {
        private(set) var bindings: [String: Binding]

        init(bindings: [String: Binding] = [:]) {
            self.bindings = bindings
        }

        /// Builds a context from per-scope dictionaries. Lower-priority scopes
        /// never overwrite a name a higher-priority scope already bound.
        static func build(_ scopes: [(Scope, [String: String])]) -> Context {
            var bindings: [String: Binding] = [:]
            for (scope, values) in scopes.sorted(by: { $0.0 < $1.0 }) {
                for (name, value) in values where bindings[name] == nil {
                    bindings[name] = Binding(value: value, scope: scope)
                }
            }
            return Context(bindings: bindings)
        }

        func binding(for name: String) -> Binding? {
            bindings[name]
        }
    }

    struct Resolution: Sendable, Equatable {
        let text: String
        /// Names with no binding, in first-seen order.
        let unresolved: [String]

        var hasUnresolved: Bool { !unresolved.isEmpty }
    }

    /// Substitutes placeholders. Unresolved ones are **left as written** rather
    /// than blanked: sending `/users/` when the user wrote `/users/{{id}}` would
    /// silently hit the wrong endpoint, while leaving the braces in makes the
    /// mistake visible in the URL and in the response.
    static func resolve(_ text: String, in context: Context) -> Resolution {
        let tokens = VariableTokenizer.tokens(in: text)
        guard !tokens.isEmpty else { return Resolution(text: text, unresolved: []) }

        var result = ""
        var unresolved: [String] = []
        var seenUnresolved = Set<String>()
        var cursor = text.startIndex

        for token in tokens {
            result += text[cursor..<token.range.lowerBound]

            if let binding = context.binding(for: token.name), !token.name.isEmpty {
                result += binding.value
            } else {
                result += text[token.range]
                if !token.name.isEmpty, seenUnresolved.insert(token.name).inserted {
                    unresolved.append(token.name)
                }
            }
            cursor = token.range.upperBound
        }
        result += text[cursor...]

        return Resolution(text: result, unresolved: unresolved)
    }

    /// Resolves several strings against one context, accumulating the union of
    /// unresolved names.
    static func resolveAll(_ texts: [String], in context: Context) -> (texts: [String], unresolved: [String]) {
        var resolvedTexts: [String] = []
        var unresolved: [String] = []
        var seen = Set<String>()

        for text in texts {
            let resolution = resolve(text, in: context)
            resolvedTexts.append(resolution.text)
            for name in resolution.unresolved where seen.insert(name).inserted {
                unresolved.append(name)
            }
        }
        return (resolvedTexts, unresolved)
    }
}
