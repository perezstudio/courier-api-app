import Foundation

/// Body types offered in the editor.
nonisolated enum BodyType: String, CaseIterable, Sendable {
    case none
    case json
    case xml
    case text
    case html
    case javascript
    case formData
    case urlEncoded
    case binary
    case graphql

    var displayName: String {
        switch self {
        case .none: "None"
        case .json: "JSON"
        case .xml: "XML"
        case .text: "Text"
        case .html: "HTML"
        case .javascript: "JavaScript"
        case .formData: "Form Data"
        case .urlEncoded: "URL Encoded"
        case .binary: "Binary"
        case .graphql: "GraphQL"
        }
    }

    /// Whether this body is edited as free text in the code editor.
    var isTextual: Bool {
        switch self {
        case .json, .xml, .text, .html, .javascript, .graphql: true
        case .none, .formData, .urlEncoded, .binary: false
        }
    }

    /// Language used for syntax highlighting, if any.
    var syntax: SyntaxHighlighter.Language? {
        switch self {
        case .json, .graphql: .json
        case .xml, .html: .xml
        case .text, .javascript, .none, .formData, .urlEncoded, .binary: nil
        }
    }

    /// The Content-Type sent when the user has not set one explicitly.
    var defaultContentType: String? {
        switch self {
        case .none, .binary: nil
        case .json, .graphql: "application/json"
        case .xml: "application/xml"
        case .text: "text/plain"
        case .html: "text/html"
        case .javascript: "application/javascript"
        case .formData: "multipart/form-data"
        case .urlEncoded: "application/x-www-form-urlencoded"
        }
    }
}

/// Authorization settings for a request.
///
/// Encoded to `CDRequest.authData` as JSON. Secret material — bearer token,
/// basic password, API key value — is **not** in here: only `secretID`, which
/// addresses the value in the Keychain (REQUIREMENTS.md §6).
nonisolated struct AuthConfiguration: Codable, Equatable, Sendable {

    enum Kind: String, Codable, CaseIterable, Sendable {
        case inherit
        case none
        case bearer
        case basic
        case apiKey

        var displayName: String {
            switch self {
            case .inherit: "Inherit"
            case .none: "No Auth"
            case .bearer: "Bearer Token"
            case .basic: "Basic Auth"
            case .apiKey: "API Key"
            }
        }
    }

    enum APIKeyLocation: String, Codable, CaseIterable, Sendable {
        case header
        case query

        var displayName: String {
            switch self {
            case .header: "Header"
            case .query: "Query Param"
            }
        }
    }

    var kind: Kind = .inherit
    var basicUsername: String = ""
    var apiKeyName: String = ""
    var apiKeyLocation: APIKeyLocation = .header
    /// Keychain address for whichever secret this kind uses.
    var secretID: UUID?

    static let empty = AuthConfiguration()

    // MARK: - Coding

    static func decode(from data: Data?) -> AuthConfiguration {
        guard let data else { return .empty }
        return (try? JSONDecoder().decode(AuthConfiguration.self, from: data)) ?? .empty
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Whether this kind stores a secret at all — `inherit` and `none` do not,
    /// so their Keychain item should be cleared when switching to them.
    var usesSecret: Bool {
        switch kind {
        case .bearer, .basic, .apiKey: true
        case .inherit, .none: false
        }
    }

    var secretFieldLabel: String {
        switch kind {
        case .bearer: "Token"
        case .basic: "Password"
        case .apiKey: "Value"
        case .inherit, .none: ""
        }
    }
}
