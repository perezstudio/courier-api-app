import Foundation

/// Keeps the URL field and the Params table in agreement.
///
/// Editing either one has to update the other, and doing that naively loses
/// information users care about: a disabled row has no place in the URL, a
/// `{{variable}}` is not percent-encodable, and a bare `?flag` is not the same
/// as `?flag=`. Each of those is handled explicitly below.
nonisolated enum URLQuerySync {

    /// Splits a URL into its part before `?` and the parsed query rows.
    static func parse(_ urlString: String) -> (base: String, rows: [KeyValueRow]) {
        guard let markerIndex = urlString.firstIndex(of: "?") else {
            return (urlString, [])
        }

        let base = String(urlString[urlString.startIndex..<markerIndex])
        let query = String(urlString[urlString.index(after: markerIndex)...])
        return (base, parseQuery(query))
    }

    static func parseQuery(_ query: String) -> [KeyValueRow] {
        guard !query.isEmpty else { return [] }

        return query.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = decode(String(parts.first ?? ""))
            // `?flag` (no `=`) and `?flag=` (empty value) both arrive as an
            // empty value here; the distinction is not worth preserving, and
            // servers overwhelmingly treat them alike.
            let value = parts.count > 1 ? decode(String(parts[1])) : ""
            return KeyValueRow(key: key, value: value)
        }
    }

    /// Rebuilds a URL from a base and rows, keeping only enabled, named rows.
    static func compose(base: String, rows: [KeyValueRow]) -> String {
        let usable = rows.filter { $0.isEnabled && !$0.key.isEmpty }
        guard !usable.isEmpty else { return base }

        let query = usable
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")
        return "\(base)?\(query)"
    }

    /// Merges freshly-parsed rows into the existing table.
    ///
    /// Reusing the existing row for a key preserves its id, enabled flag, and
    /// note — otherwise typing in the URL field would silently re-enable rows
    /// the user had switched off and discard their notes.
    static func merge(parsed: [KeyValueRow], into existing: [KeyValueRow]) -> [KeyValueRow] {
        var remaining = existing
        var result: [KeyValueRow] = []

        for row in parsed {
            if let index = remaining.firstIndex(where: { $0.key == row.key }) {
                var kept = remaining.remove(at: index)
                kept.value = row.value
                result.append(kept)
            } else {
                result.append(row)
            }
        }

        // Disabled rows never appear in the URL, so they would look "removed"
        // on every parse. Keep them.
        result.append(contentsOf: remaining.filter { !$0.isEnabled })
        return result
    }

    // MARK: - Encoding

    /// Percent-encodes a component while leaving `{{variable}}` braces intact —
    /// they are resolved before the request is sent, and encoding them here
    /// would make the placeholder unreadable in the URL field.
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?#+")
        allowed.insert(charactersIn: "{}")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }
}
