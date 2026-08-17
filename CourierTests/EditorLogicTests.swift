import Foundation
import Testing

@testable import Courier

@Suite("URL and params sync")
struct URLQuerySyncTests {

    @Test("A URL without a query parses to no rows")
    func noQuery() {
        let result = URLQuerySync.parse("https://api.example.com/users")
        #expect(result.base == "https://api.example.com/users")
        #expect(result.rows.isEmpty)
    }

    @Test("Query pairs parse into rows")
    func parsesPairs() {
        let result = URLQuerySync.parse("https://api.example.com/users?page=2&limit=10")
        #expect(result.base == "https://api.example.com/users")
        #expect(result.rows.map(\.key) == ["page", "limit"])
        #expect(result.rows.map(\.value) == ["2", "10"])
    }

    @Test("A key with no value parses to an empty value")
    func parsesValuelessKey() {
        let result = URLQuerySync.parse("https://example.com?flag")
        #expect(result.rows.count == 1)
        #expect(result.rows.first?.key == "flag")
        #expect(result.rows.first?.value.isEmpty == true)
    }

    @Test("Percent-encoding and plus signs decode")
    func decodesEncodedValues() {
        let result = URLQuerySync.parse("https://example.com?q=hello%20world&name=a+b")
        #expect(result.rows.map(\.value) == ["hello world", "a b"])
    }

    @Test("Composing skips disabled and unnamed rows")
    func composeSkipsRows() {
        let rows = [
            KeyValueRow(key: "page", value: "2"),
            KeyValueRow(key: "off", value: "x", isEnabled: false),
            KeyValueRow(key: "", value: "orphan"),
        ]
        let url = URLQuerySync.compose(base: "https://example.com", rows: rows)
        #expect(url == "https://example.com?page=2")
    }

    @Test("Composing with no usable rows leaves the base alone")
    func composeWithoutRows() {
        let url = URLQuerySync.compose(base: "https://example.com", rows: [])
        #expect(url == "https://example.com")
    }

    @Test("Variable braces survive encoding")
    func preservesVariableBraces() {
        let rows = [KeyValueRow(key: "id", value: "{{userID}}")]
        let url = URLQuerySync.compose(base: "https://example.com", rows: rows)
        // Percent-encoding the braces would make the placeholder unreadable in
        // the URL field and unrecognizable to the resolver.
        #expect(url == "https://example.com?id={{userID}}")
    }

    @Test("Spaces and ampersands in values are encoded")
    func encodesSeparators() {
        let rows = [KeyValueRow(key: "q", value: "a b&c")]
        let url = URLQuerySync.compose(base: "https://example.com", rows: rows)
        #expect(url == "https://example.com?q=a%20b%26c")
    }

    @Test("A round trip through parse and compose is stable")
    func roundTrips() {
        let original = "https://example.com/path?page=2&q=hello%20world"
        let parsed = URLQuerySync.parse(original)
        let rebuilt = URLQuerySync.compose(base: parsed.base, rows: parsed.rows)
        #expect(rebuilt == original)
    }

    @Test("Merging preserves the enabled flag, note, and id of existing rows")
    func mergePreservesRowState() {
        let existing = [
            KeyValueRow(key: "page", value: "1", isEnabled: true, note: "which page"),
        ]
        let parsed = [KeyValueRow(key: "page", value: "5")]

        let merged = URLQuerySync.merge(parsed: parsed, into: existing)

        #expect(merged.count == 1)
        #expect(merged[0].value == "5")
        #expect(merged[0].note == "which page")
        #expect(merged[0].id == existing[0].id)
    }

    @Test("Merging keeps disabled rows that the URL cannot represent")
    func mergeKeepsDisabledRows() {
        let existing = [
            KeyValueRow(key: "page", value: "1"),
            KeyValueRow(key: "debug", value: "true", isEnabled: false),
        ]
        let parsed = [KeyValueRow(key: "page", value: "2")]

        let merged = URLQuerySync.merge(parsed: parsed, into: existing)

        // A disabled row never appears in the URL, so a naive merge would treat
        // it as deleted every time the user typed.
        #expect(merged.count == 2)
        #expect(merged.contains { $0.key == "debug" && !$0.isEnabled })
    }
}

@Suite("Variable tokenizer")
struct VariableTokenizerTests {

    @Test("Placeholders are found in order")
    func findsTokens() {
        let names = VariableTokenizer.names(in: "{{base}}/users/{{id}}")
        #expect(names == ["base", "id"])
    }

    @Test("Names are trimmed")
    func trimsNames() {
        let names = VariableTokenizer.names(in: "{{ spaced }}")
        #expect(names == ["spaced"])
    }

    @Test("Repeated names are deduplicated but keep first-seen order")
    func deduplicates() {
        let names = VariableTokenizer.names(in: "{{b}}/{{a}}/{{b}}")
        #expect(names == ["b", "a"])
    }

    @Test("An unclosed placeholder is ignored")
    func ignoresUnclosed() {
        // A half-typed placeholder should not highlight the rest of the field.
        #expect(VariableTokenizer.names(in: "https://example.com/{{id").isEmpty)
    }

    @Test("Text with no placeholders yields nothing")
    func handlesPlainText() {
        #expect(VariableTokenizer.tokens(in: "https://example.com/users").isEmpty)
    }

    @Test("Empty placeholders are tokenized but not named")
    func ignoresEmptyNames() {
        #expect(VariableTokenizer.tokens(in: "{{}}").count == 1)
        #expect(VariableTokenizer.names(in: "{{}}").isEmpty)
    }

    @Test("Ranges map onto the original string")
    func producesUsableRanges() {
        let text = "GET {{host}}/x"
        let ranges = VariableTokenizer.nsRanges(in: text)
        #expect(ranges.count == 1)
        #expect((text as NSString).substring(with: ranges[0]) == "{{host}}")
    }
}

@Suite("Syntax highlighting")
struct SyntaxHighlighterTests {

    @Test("JSON keys and string values are distinguished")
    func separatesKeysFromValues() {
        let highlighter = SyntaxHighlighter(language: .json)
        let tokens = highlighter.tokens(in: #"{"name":"courier"}"#)

        let keys = tokens.filter { $0.kind == .key }
        let strings = tokens.filter { $0.kind == .string }
        // A regex over quoted runs cannot tell these apart; the scanner looks
        // ahead for the colon.
        #expect(keys.count == 1)
        #expect(strings.count == 1)
    }

    @Test("JSON numbers and literals are tokenized")
    func tokenizesNumbersAndLiterals() {
        let highlighter = SyntaxHighlighter(language: .json)
        let tokens = highlighter.tokens(in: #"{"n":-1.5e3,"ok":true,"missing":null}"#)

        #expect(tokens.contains { $0.kind == .number })
        #expect(tokens.filter { $0.kind == .literal }.count == 2)
    }

    @Test("Escaped quotes do not end a JSON string early")
    func handlesEscapedQuotes() {
        let highlighter = SyntaxHighlighter(language: .json)
        let text = #"{"quote":"say \"hi\" now"}"#
        let tokens = highlighter.tokens(in: text)

        let strings = tokens.filter { $0.kind == .string }
        #expect(strings.count == 1)
        // The whole value, escapes included, is one token.
        #expect(strings.first.map { NSMaxRange($0.range) } == text.utf16.count - 1)
    }

    @Test("XML tags and attributes are tokenized")
    func tokenizesXML() {
        let highlighter = SyntaxHighlighter(language: .xml)
        let tokens = highlighter.tokens(in: #"<user id="7"><name>A</name></user>"#)

        #expect(tokens.filter { $0.kind == .tag }.count == 4)
        #expect(tokens.contains { $0.kind == .attribute })
        #expect(tokens.contains { $0.kind == .string })
    }

    @Test("XML comments swallow their contents")
    func handlesXMLComments() {
        let highlighter = SyntaxHighlighter(language: .xml)
        let tokens = highlighter.tokens(in: "<!-- <fake attr=\"x\"> --><real/>")

        #expect(tokens.contains { $0.kind == .comment })
        // The tag inside the comment must not be tokenized as markup.
        #expect(tokens.filter { $0.kind == .tag }.count == 1)
    }

    @Test("Token ranges stay inside the string")
    func rangesAreInBounds() {
        let text = #"{"a":[1,2,{"b":"c"}],"d":true}"#
        let tokens = SyntaxHighlighter(language: .json).tokens(in: text)
        let length = text.utf16.count

        for token in tokens {
            #expect(token.range.location >= 0)
            #expect(NSMaxRange(token.range) <= length)
        }
    }

    @Test("Malformed input does not hang or overrun")
    func survivesMalformedInput() {
        let json = SyntaxHighlighter(language: .json)
        _ = json.tokens(in: #"{"unterminated: "#)
        _ = json.tokens(in: "{{{[[[")

        let xml = SyntaxHighlighter(language: .xml)
        _ = xml.tokens(in: "<open attr=\"unclosed")
        _ = xml.tokens(in: "<!-- never closed")
    }
}

@Suite("Auth configuration")
struct AuthConfigurationTests {

    @Test("Round-trips through JSON")
    func roundTrips() {
        var configuration = AuthConfiguration()
        configuration.kind = .apiKey
        configuration.apiKeyName = "X-Api-Key"
        configuration.apiKeyLocation = .query
        configuration.secretID = UUID()

        let decoded = AuthConfiguration.decode(from: configuration.encoded())
        #expect(decoded == configuration)
    }

    @Test("Missing or corrupt data decodes to the empty configuration")
    func decodesMissingData() {
        #expect(AuthConfiguration.decode(from: nil) == .empty)
        #expect(AuthConfiguration.decode(from: Data("not json".utf8)) == .empty)
    }

    @Test("Only credential-bearing kinds use a secret")
    func secretUsage() {
        for kind in [AuthConfiguration.Kind.bearer, .basic, .apiKey] {
            var configuration = AuthConfiguration()
            configuration.kind = kind
            #expect(configuration.usesSecret)
        }
        for kind in [AuthConfiguration.Kind.inherit, .none] {
            var configuration = AuthConfiguration()
            configuration.kind = kind
            #expect(!configuration.usesSecret)
        }
    }

    @Test("An encoded configuration never contains secret material")
    func encodingOmitsSecrets() throws {
        var configuration = AuthConfiguration()
        configuration.kind = .bearer
        configuration.secretID = UUID()

        let data = try #require(configuration.encoded())
        let json = try #require(String(data: data, encoding: .utf8))

        // The token itself lives in the Keychain; only its address is stored.
        #expect(json.contains("secretID"))
        #expect(!json.lowercased().contains("token\":\""))
    }
}

@Suite("Body types")
struct BodyTypeTests {

    @Test("Textual types get an editor, structured ones do not")
    func classifiesTextualTypes() {
        #expect(BodyType.json.isTextual)
        #expect(BodyType.xml.isTextual)
        #expect(!BodyType.formData.isTextual)
        #expect(!BodyType.binary.isTextual)
        #expect(!BodyType.none.isTextual)
    }

    @Test("Only highlightable types report a language")
    func mapsSyntax() {
        #expect(BodyType.json.syntax == .json)
        #expect(BodyType.html.syntax == .xml)
        #expect(BodyType.text.syntax == nil)
        #expect(BodyType.formData.syntax == nil)
    }

    @Test("Default content types are set for body-bearing kinds")
    func mapsContentTypes() {
        #expect(BodyType.json.defaultContentType == "application/json")
        #expect(BodyType.urlEncoded.defaultContentType == "application/x-www-form-urlencoded")
        #expect(BodyType.none.defaultContentType == nil)
    }

    @Test("Every case round-trips through its raw value")
    func rawValuesRoundTrip() {
        for type in BodyType.allCases {
            #expect(BodyType(rawValue: type.rawValue) == type)
        }
    }
}
