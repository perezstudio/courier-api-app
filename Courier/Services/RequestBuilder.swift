import Foundation

/// Turns the editor's working state into a `ResolvedRequest`.
///
/// Kept separate from both the editor and the executor so the assembly rules —
/// which headers are implied, how auth becomes a header, what a body type
/// encodes to — are testable without a network or a UI.
nonisolated enum RequestBuilder {

    struct Input: Sendable {
        var method: String
        var urlTemplate: String
        var headers: [KeyValueRow]
        var queryParams: [KeyValueRow]
        var bodyType: BodyType
        var bodyContent: String
        var auth: AuthConfiguration
        /// Resolved separately: it comes from the Keychain, not the model.
        var authSecret: String?
        var timeout: TimeInterval
        var followRedirects: Bool
    }

    struct Output: Sendable {
        var request: ResolvedRequest
        var unresolved: [String]
    }

    static func build(_ input: Input, context: VariableResolver.Context) -> Output {
        var unresolved: [String] = []
        var seen = Set<String>()

        func resolve(_ text: String) -> String {
            let resolution = VariableResolver.resolve(text, in: context)
            for name in resolution.unresolved where seen.insert(name).inserted {
                unresolved.append(name)
            }
            return resolution.text
        }

        // The URL already carries the enabled query params (the editor keeps
        // them in sync), so composing again here would duplicate them.
        let url = resolve(input.urlTemplate)

        var headers: [(name: String, value: String)] = input.headers
            .filter { $0.isEnabled && !$0.key.isEmpty }
            .map { (name: resolve($0.key), value: resolve($0.value)) }

        let body = encodeBody(input, resolve: resolve)

        // Only supply a Content-Type when the user hasn't set one; overriding
        // an explicit header would be surprising.
        let hasContentType = headers.contains { $0.name.lowercased() == "content-type" }
        if !hasContentType, body != nil, let contentType = input.bodyType.defaultContentType {
            headers.append((name: "Content-Type", value: contentType))
        }

        var finalURL = url
        if let authHeader = authorization(input, resolve: resolve) {
            switch authHeader {
            case .header(let name, let value):
                headers.append((name: name, value: value))
            case .queryItem(let name, let value):
                finalURL = appendQueryItem(to: finalURL, name: name, value: value)
            }
        }

        return Output(
            request: ResolvedRequest(
                method: input.method,
                url: finalURL,
                headers: headers,
                body: body,
                timeout: input.timeout,
                followRedirects: input.followRedirects
            ),
            unresolved: unresolved
        )
    }

    // MARK: - Body

    private static func encodeBody(
        _ input: Input,
        resolve: (String) -> String
    ) -> Data? {
        switch input.bodyType {
        case .none, .binary:
            return nil

        case .formData, .urlEncoded:
            // Both are stored as a query-encoded string. Multipart encoding for
            // form-data with files arrives with the file picker.
            let rows = URLQuerySync.parseQuery(input.bodyContent)
            let encoded = rows
                .filter { $0.isEnabled && !$0.key.isEmpty }
                .map { "\(URLQuerySync.encode(resolve($0.key)))=\(URLQuerySync.encode(resolve($0.value)))" }
                .joined(separator: "&")
            return encoded.isEmpty ? nil : Data(encoded.utf8)

        case .json, .xml, .text, .html, .javascript, .graphql:
            let resolved = resolve(input.bodyContent)
            return resolved.isEmpty ? nil : Data(resolved.utf8)
        }
    }

    // MARK: - Auth

    private enum AuthPlacement {
        case header(name: String, value: String)
        case queryItem(name: String, value: String)
    }

    private static func authorization(
        _ input: Input,
        resolve: (String) -> String
    ) -> AuthPlacement? {
        let secret = input.authSecret.map(resolve) ?? ""

        switch input.auth.kind {
        case .inherit, .none:
            // Folder- and collection-level auth arrives with environments; for
            // now `inherit` sends nothing rather than guessing.
            return nil

        case .bearer:
            guard !secret.isEmpty else { return nil }
            return .header(name: "Authorization", value: "Bearer \(secret)")

        case .basic:
            let username = resolve(input.auth.basicUsername)
            guard !username.isEmpty || !secret.isEmpty else { return nil }
            let encoded = Data("\(username):\(secret)".utf8).base64EncodedString()
            return .header(name: "Authorization", value: "Basic \(encoded)")

        case .apiKey:
            let name = resolve(input.auth.apiKeyName)
            guard !name.isEmpty else { return nil }
            switch input.auth.apiKeyLocation {
            case .header: return .header(name: name, value: secret)
            case .query: return .queryItem(name: name, value: secret)
            }
        }
    }

    private static func appendQueryItem(to url: String, name: String, value: String) -> String {
        let separator = url.contains("?") ? "&" : "?"
        return "\(url)\(separator)\(URLQuerySync.encode(name))=\(URLQuerySync.encode(value))"
    }
}
