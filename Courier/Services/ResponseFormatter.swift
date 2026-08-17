import Foundation

/// Decides how a response body should be shown and prepares the text for it.
nonisolated enum ResponseFormatter {

    /// How the Body tab should render a payload.
    enum Presentation: Equatable {
        case json
        case xml
        case html
        case text
        case image
        /// Not decodable as text — falls back to the hex dump.
        case binary
    }

    /// Bodies larger than this are shown raw with a warning rather than
    /// pretty-printed or highlighted; formatting a 50MB payload would stall the
    /// main thread (REQUIREMENTS.md §11).
    static let largeBodyThreshold = 2_000_000

    // MARK: - Content type

    static func presentation(contentType: String?, body: Data) -> Presentation {
        let type = (contentType ?? "").lowercased()

        if type.contains("json") { return .json }
        if type.contains("xml") { return .xml }
        if type.contains("html") { return .html }
        if type.hasPrefix("image/") { return .image }
        if type.hasPrefix("text/") { return .text }

        // No usable Content-Type: sniff. Servers mislabel more often than is
        // comfortable, so a JSON-shaped body wins over a vague header.
        if looksLikeJSON(body) { return .json }
        if looksLikeXML(body) { return .xml }
        return looksBinary(body) ? .binary : .text
    }

    /// Whether a payload should be shown as hex rather than text.
    ///
    /// Decided by content, not by whether decoding succeeds: `decodeText` falls
    /// back to ISO-8859-1, which maps every possible byte, so a
    /// decode-failure test would never classify anything as binary.
    static func looksBinary(_ data: Data) -> Bool {
        let sample = data.prefix(1024)
        guard !sample.isEmpty else { return false }

        // A NUL byte early in the payload is the classic signal — the same
        // heuristic git uses to decide a file is not text.
        if sample.contains(0) { return true }

        let control = sample.count { byte in
            byte < 0x09 || (byte > 0x0D && byte < 0x20) || byte == 0x7F
        }
        return Double(control) / Double(sample.count) > 0.3
    }

    static func charset(from contentType: String?) -> String.Encoding {
        guard
            let contentType,
            let range = contentType.range(of: "charset=", options: .caseInsensitive)
        else { return .utf8 }

        let raw = contentType[range.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
            .lowercased()

        switch raw {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1": return .isoLatin1
        case "utf-16": return .utf16
        case "ascii", "us-ascii": return .ascii
        default: return .utf8
        }
    }

    // MARK: - Text

    /// Decodes a body to text, falling back through a couple of encodings
    /// before giving up — a mislabeled charset should not force the hex view.
    static func decodeText(_ data: Data, encoding: String.Encoding = .utf8) -> String? {
        if let text = String(data: data, encoding: encoding) { return text }
        if encoding != .utf8, let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Pretty-prints when the payload is a structured type and small enough.
    static func prettyPrinted(_ data: Data, presentation: Presentation) -> String? {
        guard data.count <= largeBodyThreshold else { return nil }

        switch presentation {
        case .json:
            guard
                let object = try? JSONSerialization.jsonObject(
                    with: data,
                    options: [.fragmentsAllowed]
                ),
                let pretty = try? JSONSerialization.data(
                    withJSONObject: object,
                    options: [.prettyPrinted, .withoutEscapingSlashes]
                )
            else { return nil }
            return String(data: pretty, encoding: .utf8)

        case .xml, .html:
            return decodeText(data).map(indentXML)

        case .text, .image, .binary:
            return nil
        }
    }

    /// Minimal XML re-indenting. Deliberately not a parser: it must never throw
    /// away bytes from a malformed document the user is trying to debug.
    static func indentXML(_ text: String) -> String {
        var output: [String] = []
        var depth = 0

        let normalized = text
            .replacingOccurrences(of: ">\\s*<", with: ">\n<", options: .regularExpression)

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let isClosing = line.hasPrefix("</")
            if isClosing { depth = max(0, depth - 1) }

            output.append(String(repeating: "  ", count: depth) + line)

            let isSelfClosing = line.hasSuffix("/>")
            let isDeclaration = line.hasPrefix("<?") || line.hasPrefix("<!")
            let hasInlineClose = line.contains("</")
            if !isClosing, !isSelfClosing, !isDeclaration, !hasInlineClose, line.hasPrefix("<") {
                depth += 1
            }
        }
        return output.joined(separator: "\n")
    }

    // MARK: - Sniffing

    private static func looksLikeJSON(_ data: Data) -> Bool {
        guard let first = firstNonWhitespaceByte(data) else { return false }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }

    private static func looksLikeXML(_ data: Data) -> Bool {
        firstNonWhitespaceByte(data) == UInt8(ascii: "<")
    }

    private static func firstNonWhitespaceByte(_ data: Data) -> UInt8? {
        // Only the head matters, and reading all of a large body to find one
        // byte would be wasteful.
        for byte in data.prefix(64) where !(byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) {
            return byte
        }
        return nil
    }

    // MARK: - Cookies

    nonisolated struct Cookie: Sendable, Equatable {
        var name: String
        var value: String
        var domain: String
        var path: String
        var expires: String
        var isSecure: Bool
        var isHTTPOnly: Bool
    }

    /// Parses `Set-Cookie` headers.
    ///
    /// `HTTPCookie.cookies(withResponseHeaderFields:for:)` drops cookies whose
    /// domain doesn't match the URL, which is exactly the case a developer
    /// wants to *see*. So this parses the header text directly.
    static func parseCookies(from headers: [(name: String, value: String)]) -> [Cookie] {
        headers
            .filter { $0.name.lowercased() == "set-cookie" }
            .compactMap { parseCookie($0.value) }
    }

    private static func parseCookie(_ header: String) -> Cookie? {
        let parts = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let pair = parts.first else { return nil }

        let nameValue = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let name = nameValue.first, !name.isEmpty else { return nil }

        var cookie = Cookie(
            name: String(name),
            value: nameValue.count > 1 ? String(nameValue[1]) : "",
            domain: "",
            path: "",
            expires: "",
            isSecure: false,
            isHTTPOnly: false
        )

        for attribute in parts.dropFirst() {
            let split = attribute.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = split[0].lowercased()
            let value = split.count > 1 ? String(split[1]) : ""

            switch key {
            case "domain": cookie.domain = value
            case "path": cookie.path = value
            case "expires": cookie.expires = value
            case "max-age": if cookie.expires.isEmpty { cookie.expires = "\(value)s" }
            case "secure": cookie.isSecure = true
            case "httponly": cookie.isHTTPOnly = true
            default: break
            }
        }
        return cookie
    }

    // MARK: - Hex

    /// Classic offset / hex / ASCII dump.
    static func hexDump(_ data: Data, maxBytes: Int = 64_000) -> String {
        let slice = data.prefix(maxBytes)
        var lines: [String] = []
        var offset = 0

        for chunk in slice.chunked(into: 16) {
            let hex = chunk
                .map { String(format: "%02x", $0) }
                .joined(separator: " ")
                .padding(toLength: 47, withPad: " ", startingAt: 0)
            let ascii = chunk
                .map { $0 >= 32 && $0 < 127 ? String(UnicodeScalar($0)) : "." }
                .joined()
            lines.append(String(format: "%08x  %@  |%@|", offset, hex, ascii))
            offset += chunk.count
        }

        if data.count > maxBytes {
            lines.append("… \(data.count - maxBytes) more bytes")
        }
        return lines.joined(separator: "\n")
    }
}

extension Collection {
    nonisolated func chunked(into size: Int) -> [[Element]] {
        var chunks: [[Element]] = []
        var current: [Element] = []
        current.reserveCapacity(size)

        for element in self {
            current.append(element)
            if current.count == size {
                chunks.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
