import Foundation
import Testing

@testable import Courier

@Suite("Variable resolution")
struct VariableResolverTests {

    private func context(_ pairs: [(VariableResolver.Scope, [String: String])]) -> VariableResolver.Context {
        VariableResolver.Context.build(pairs)
    }

    @Test("Placeholders are substituted")
    func substitutes() {
        let ctx = context([(.environment, ["host": "api.example.com"])])
        let result = VariableResolver.resolve("https://{{host}}/users", in: ctx)

        #expect(result.text == "https://api.example.com/users")
        #expect(!result.hasUnresolved)
    }

    @Test("Higher-priority scopes win")
    func respectsPrecedence() {
        let ctx = context([
            (.global, ["host": "global.example.com"]),
            (.collection, ["host": "collection.example.com"]),
            (.environment, ["host": "env.example.com"]),
        ])
        // request → environment → collection → global.
        #expect(VariableResolver.resolve("{{host}}", in: ctx).text == "env.example.com")
        #expect(ctx.binding(for: "host")?.scope == .environment)
    }

    @Test("Lower-priority scopes still supply names higher ones lack")
    func fallsBackAcrossScopes() {
        let ctx = context([
            (.global, ["version": "v1"]),
            (.environment, ["host": "api.example.com"]),
        ])
        let result = VariableResolver.resolve("https://{{host}}/{{version}}", in: ctx)
        #expect(result.text == "https://api.example.com/v1")
    }

    @Test("Unresolved placeholders are left as written and reported")
    func reportsUnresolved() {
        let result = VariableResolver.resolve("/users/{{id}}", in: VariableResolver.Context())

        // Substituting an empty string would silently hit /users/ — a different
        // endpoint — so the braces stay put and the problem stays visible.
        #expect(result.text == "/users/{{id}}")
        #expect(result.unresolved == ["id"])
    }

    @Test("A repeated unresolved name is reported once")
    func deduplicatesUnresolved() {
        let result = VariableResolver.resolve("{{a}}/{{a}}/{{b}}", in: VariableResolver.Context())
        #expect(result.unresolved == ["a", "b"])
    }

    @Test("Several placeholders in one string all resolve")
    func handlesMultiple() {
        let ctx = context([(.environment, ["a": "1", "b": "2"])])
        #expect(VariableResolver.resolve("{{a}}-{{b}}-{{a}}", in: ctx).text == "1-2-1")
    }

    @Test("Text with no placeholders is returned unchanged")
    func passesThroughPlainText() {
        let result = VariableResolver.resolve("https://example.com", in: VariableResolver.Context())
        #expect(result.text == "https://example.com")
        #expect(!result.hasUnresolved)
    }

    @Test("resolveAll accumulates the union of unresolved names")
    func resolvesMany() {
        let ctx = context([(.environment, ["host": "example.com"])])
        let result = VariableResolver.resolveAll(
            ["{{host}}", "{{missing}}", "{{host}}/{{other}}"],
            in: ctx
        )
        #expect(result.texts[0] == "example.com")
        #expect(result.unresolved == ["missing", "other"])
    }
}

@Suite("Request building")
struct RequestBuilderTests {

    private func input(
        method: String = "GET",
        url: String = "https://example.com",
        headers: [KeyValueRow] = [],
        bodyType: BodyType = .none,
        body: String = "",
        auth: AuthConfiguration = .empty,
        secret: String? = nil
    ) -> RequestBuilder.Input {
        RequestBuilder.Input(
            method: method,
            urlTemplate: url,
            headers: headers,
            queryParams: [],
            bodyType: bodyType,
            bodyContent: body,
            auth: auth,
            authSecret: secret,
            timeout: 30,
            followRedirects: true
        )
    }

    @Test("Disabled and unnamed headers are dropped")
    func filtersHeaders() {
        let output = RequestBuilder.build(
            input(headers: [
                KeyValueRow(key: "Accept", value: "application/json"),
                KeyValueRow(key: "X-Off", value: "1", isEnabled: false),
                KeyValueRow(key: "", value: "orphan"),
            ]),
            context: VariableResolver.Context()
        )
        #expect(output.request.headers.map(\.name) == ["Accept"])
    }

    @Test("A default Content-Type is supplied for a body")
    func addsContentType() {
        let output = RequestBuilder.build(
            input(method: "POST", bodyType: .json, body: #"{"a":1}"#),
            context: VariableResolver.Context()
        )
        let contentType = output.request.headers.first { $0.name == "Content-Type" }
        #expect(contentType?.value == "application/json")
    }

    @Test("An explicit Content-Type is not overridden")
    func respectsExplicitContentType() {
        let output = RequestBuilder.build(
            input(
                method: "POST",
                headers: [KeyValueRow(key: "Content-Type", value: "application/vnd.api+json")],
                bodyType: .json,
                body: "{}"
            ),
            context: VariableResolver.Context()
        )
        let contentTypes = output.request.headers.filter { $0.name.lowercased() == "content-type" }
        #expect(contentTypes.count == 1)
        #expect(contentTypes.first?.value == "application/vnd.api+json")
    }

    @Test("No body means no Content-Type")
    func skipsContentTypeWithoutBody() {
        let output = RequestBuilder.build(input(), context: VariableResolver.Context())
        #expect(!output.request.headers.contains { $0.name == "Content-Type" })
        #expect(output.request.body == nil)
    }

    @Test("Bearer auth becomes an Authorization header")
    func buildsBearer() {
        var auth = AuthConfiguration()
        auth.kind = .bearer

        let output = RequestBuilder.build(
            input(auth: auth, secret: "abc123"),
            context: VariableResolver.Context()
        )
        let header = output.request.headers.first { $0.name == "Authorization" }
        #expect(header?.value == "Bearer abc123")
    }

    @Test("Basic auth is base64 encoded")
    func buildsBasic() throws {
        var auth = AuthConfiguration()
        auth.kind = .basic
        auth.basicUsername = "user"

        let output = RequestBuilder.build(
            input(auth: auth, secret: "pass"),
            context: VariableResolver.Context()
        )
        let header = try #require(output.request.headers.first { $0.name == "Authorization" })
        #expect(header.value == "Basic \(Data("user:pass".utf8).base64EncodedString())")
    }

    @Test("An API key can go in a header or the query string")
    func buildsAPIKey() {
        var auth = AuthConfiguration()
        auth.kind = .apiKey
        auth.apiKeyName = "X-Api-Key"

        let headerOutput = RequestBuilder.build(
            input(auth: auth, secret: "k"),
            context: VariableResolver.Context()
        )
        #expect(headerOutput.request.headers.contains { $0.name == "X-Api-Key" && $0.value == "k" })

        auth.apiKeyLocation = .query
        let queryOutput = RequestBuilder.build(
            input(auth: auth, secret: "k"),
            context: VariableResolver.Context()
        )
        #expect(queryOutput.request.url == "https://example.com?X-Api-Key=k")
    }

    @Test("A query-placed API key appends to an existing query string")
    func appendsToExistingQuery() {
        var auth = AuthConfiguration()
        auth.kind = .apiKey
        auth.apiKeyName = "key"
        auth.apiKeyLocation = .query

        let output = RequestBuilder.build(
            input(url: "https://example.com?page=1", auth: auth, secret: "v"),
            context: VariableResolver.Context()
        )
        #expect(output.request.url == "https://example.com?page=1&key=v")
    }

    @Test("Inherit and none send no Authorization header")
    func skipsAuthWhenNotConfigured() {
        for kind in [AuthConfiguration.Kind.inherit, .none] {
            var auth = AuthConfiguration()
            auth.kind = kind
            let output = RequestBuilder.build(
                input(auth: auth, secret: "unused"),
                context: VariableResolver.Context()
            )
            #expect(!output.request.headers.contains { $0.name == "Authorization" })
        }
    }

    @Test("Variables resolve in the URL, headers, and body")
    func resolvesEverywhere() {
        let ctx = VariableResolver.Context.build([
            (.environment, ["host": "api.example.com", "token": "t0ken", "name": "courier"]),
        ])
        let output = RequestBuilder.build(
            input(
                method: "POST",
                url: "https://{{host}}/x",
                headers: [KeyValueRow(key: "X-Token", value: "{{token}}")],
                bodyType: .json,
                body: #"{"name":"{{name}}"}"#
            ),
            context: ctx
        )

        #expect(output.request.url == "https://api.example.com/x")
        #expect(output.request.headers.contains { $0.name == "X-Token" && $0.value == "t0ken" })
        #expect(output.request.body == Data(#"{"name":"courier"}"#.utf8))
        #expect(output.unresolved.isEmpty)
    }

    @Test("Unresolved names are reported from every part of the request")
    func reportsUnresolvedFromAllParts() {
        let output = RequestBuilder.build(
            input(
                url: "https://{{host}}/x",
                headers: [KeyValueRow(key: "X-A", value: "{{headerVar}}")],
                bodyType: .json,
                body: "{{bodyVar}}"
            ),
            context: VariableResolver.Context()
        )
        #expect(Set(output.unresolved) == ["host", "headerVar", "bodyVar"])
    }

    @Test("Form-encoded bodies encode their rows")
    func encodesFormBody() throws {
        let output = RequestBuilder.build(
            input(method: "POST", bodyType: .urlEncoded, body: "a=1&b=hello world"),
            context: VariableResolver.Context()
        )
        let body = try #require(output.request.body)
        #expect(String(data: body, encoding: .utf8) == "a=1&b=hello%20world")
    }

    @Test("The redacted snapshot hides credential headers")
    func redactsSnapshot() {
        var auth = AuthConfiguration()
        auth.kind = .bearer

        let output = RequestBuilder.build(
            input(
                headers: [KeyValueRow(key: "X-Api-Key", value: "supersecret")],
                auth: auth,
                secret: "tokenvalue"
            ),
            context: VariableResolver.Context()
        )
        let json = output.request.redactedJSON()

        // The snapshot is stored in the library, so §6 keeps secrets out of it.
        #expect(!json.contains("supersecret"))
        #expect(!json.contains("tokenvalue"))
        #expect(json.contains("<redacted>"))
    }
}

@Suite("Response formatting")
struct ResponseFormatterTests {

    @Test("Content-Type selects the presentation")
    func detectsByContentType() {
        let body = Data("x".utf8)
        #expect(ResponseFormatter.presentation(contentType: "application/json", body: body) == .json)
        #expect(ResponseFormatter.presentation(contentType: "text/html", body: body) == .html)
        #expect(ResponseFormatter.presentation(contentType: "image/png", body: body) == .image)
        #expect(ResponseFormatter.presentation(contentType: "text/plain", body: body) == .text)
    }

    @Test("A missing Content-Type falls back to sniffing")
    func sniffsWithoutContentType() {
        // Servers mislabel often enough that shape beats a vague header.
        #expect(ResponseFormatter.presentation(contentType: nil, body: Data(#"{"a":1}"#.utf8)) == .json)
        #expect(ResponseFormatter.presentation(contentType: nil, body: Data("  [1,2]".utf8)) == .json)
        #expect(ResponseFormatter.presentation(contentType: nil, body: Data("<html>".utf8)) == .xml)
        #expect(ResponseFormatter.presentation(contentType: nil, body: Data("plain".utf8)) == .text)
    }

    @Test("Undecodable bytes fall back to binary")
    func detectsBinary() {
        let body = Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81])
        #expect(ResponseFormatter.presentation(contentType: nil, body: body) == .binary)
    }

    @Test("Charset is read from the Content-Type")
    func parsesCharset() {
        #expect(ResponseFormatter.charset(from: "text/plain; charset=utf-8") == .utf8)
        #expect(ResponseFormatter.charset(from: "text/plain; charset=ISO-8859-1") == .isoLatin1)
        #expect(ResponseFormatter.charset(from: "text/plain") == .utf8)
        #expect(ResponseFormatter.charset(from: nil) == .utf8)
    }

    @Test("JSON is pretty-printed")
    func prettyPrintsJSON() throws {
        let pretty = try #require(
            ResponseFormatter.prettyPrinted(Data(#"{"b":2,"a":1}"#.utf8), presentation: .json)
        )
        #expect(pretty.contains("\n"))
        #expect(pretty.contains("\"a\""))
    }

    @Test("Invalid JSON is not pretty-printed")
    func leavesInvalidJSONAlone() {
        #expect(ResponseFormatter.prettyPrinted(Data("{not json".utf8), presentation: .json) == nil)
    }

    @Test("XML is re-indented without losing content")
    func indentsXML() {
        let indented = ResponseFormatter.indentXML("<a><b>text</b></a>")
        #expect(indented.contains("<a>"))
        #expect(indented.contains("<b>text</b>"))
        // Never a parser: malformed input must keep its bytes.
        #expect(ResponseFormatter.indentXML("<unclosed").contains("<unclosed"))
    }

    @Test("Set-Cookie headers are parsed with their attributes")
    func parsesCookies() throws {
        let headers = [
            (name: "Set-Cookie", value: "session=abc; Path=/; Secure; HttpOnly"),
            (name: "Set-Cookie", value: "theme=dark; Domain=example.com; Expires=Wed, 21 Oct 2026 07:28:00 GMT"),
            (name: "Content-Type", value: "text/html"),
        ]
        let cookies = ResponseFormatter.parseCookies(from: headers)

        #expect(cookies.count == 2)
        let session = try #require(cookies.first)
        #expect(session.name == "session")
        #expect(session.value == "abc")
        #expect(session.isSecure)
        #expect(session.isHTTPOnly)
        #expect(cookies[1].domain == "example.com")
        #expect(!cookies[1].isSecure)
    }

    @Test("A cookie whose domain does not match is still shown")
    func keepsMismatchedDomainCookies() {
        // HTTPCookie's own parser drops these, which is exactly the case a
        // developer needs to see.
        let cookies = ResponseFormatter.parseCookies(from: [
            (name: "Set-Cookie", value: "a=1; Domain=other-site.example")
        ])
        #expect(cookies.count == 1)
        #expect(cookies[0].domain == "other-site.example")
    }

    @Test("Hex dump has offsets, hex, and ASCII")
    func producesHexDump() {
        let dump = ResponseFormatter.hexDump(Data("AB".utf8))
        #expect(dump.hasPrefix("00000000"))
        #expect(dump.contains("41 42"))
        #expect(dump.contains("|AB|"))
    }

    @Test("Hex dump truncates and says so")
    func truncatesHexDump() {
        let dump = ResponseFormatter.hexDump(Data(repeating: 0, count: 100), maxBytes: 32)
        #expect(dump.contains("68 more bytes"))
    }
}

@Suite("Timing breakdown")
struct TimingBreakdownTests {

    @Test("Total is the sum of the phases")
    func sumsPhases() {
        var timing = TimingBreakdown()
        timing.dns = 0.01
        timing.connect = 0.02
        timing.waiting = 0.1
        #expect(abs(timing.total - 0.13) < 0.0001)
    }

    @Test("Zero-length phases are omitted from the chart")
    func omitsEmptyPhases() {
        var timing = TimingBreakdown()
        timing.dns = 0.01
        timing.waiting = 0.1
        // No TLS on plain HTTP, no DNS on a reused connection — showing empty
        // bars for those would be noise.
        #expect(timing.phases.map(\.name) == ["DNS", "Waiting"])
    }

    @Test("Round-trips through JSON")
    func roundTrips() throws {
        var timing = TimingBreakdown()
        timing.dns = 0.005
        timing.download = 0.25

        let decoded = try #require(TimingBreakdown.decode(from: timing.encodedJSON()))
        #expect(decoded == timing)
    }

    @Test("Missing or corrupt timing decodes to nil")
    func decodesMissing() {
        #expect(TimingBreakdown.decode(from: nil) == nil)
        #expect(TimingBreakdown.decode(from: "not json") == nil)
    }
}

@Suite("Execution result")
struct ExecutionResultTests {

    @Test("Headers round-trip through JSON")
    func roundTripsHeaders() {
        let result = ExecutionResult(
            statusCode: 200,
            statusText: "OK",
            headers: [(name: "Content-Type", value: "application/json")],
            body: Data(),
            duration: 0.1,
            timing: nil
        )
        let decoded = ExecutionResult.decodeHeaders(from: result.headersJSON)
        #expect(decoded.count == 1)
        #expect(decoded[0].name == "Content-Type")
        #expect(decoded[0].value == "application/json")
    }

    @Test("Corrupt header JSON decodes to nothing")
    func handlesCorruptHeaders() {
        #expect(ExecutionResult.decodeHeaders(from: "garbage").isEmpty)
        #expect(ExecutionResult.decodeHeaders(from: nil).isEmpty)
    }
}
