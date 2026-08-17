import Foundation

/// A request with every placeholder already substituted — what actually goes
/// out on the wire.
nonisolated struct ResolvedRequest: Sendable {
    var method: String
    var url: String
    var headers: [(name: String, value: String)]
    var body: Data?
    var timeout: TimeInterval
    var followRedirects: Bool

    /// A redacted form for the run snapshot. Anything that could carry a
    /// credential is masked — the snapshot is stored in the library, and §6
    /// keeps secrets out of it.
    func redactedJSON() -> String {
        let sensitive: Set<String> = ["authorization", "cookie", "proxy-authorization", "x-api-key"]
        let headerPairs = headers.map { pair -> [String: String] in
            let isSensitive = sensitive.contains(pair.name.lowercased())
            return ["name": pair.name, "value": isSensitive ? "<redacted>" : pair.value]
        }

        let payload: [String: Any] = [
            "method": method,
            "url": url,
            "headers": headerPairs,
            "bodySize": body?.count ?? 0,
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
}

/// The phase breakdown shown in the Timeline tab.
nonisolated struct TimingBreakdown: Codable, Sendable, Equatable {
    var dns: TimeInterval = 0
    var connect: TimeInterval = 0
    var tls: TimeInterval = 0
    var request: TimeInterval = 0
    var waiting: TimeInterval = 0
    var download: TimeInterval = 0

    var total: TimeInterval { dns + connect + tls + request + waiting + download }

    /// Ordered phases for the chart, dropping ones that did not happen (no TLS
    /// on plain HTTP, no DNS on a reused connection).
    var phases: [(name: String, duration: TimeInterval)] {
        [
            ("DNS", dns), ("Connect", connect), ("TLS", tls),
            ("Request", request), ("Waiting", waiting), ("Download", download),
        ].filter { $0.1 > 0 }
    }

    static func from(_ metrics: URLSessionTaskMetrics) -> TimingBreakdown {
        var breakdown = TimingBreakdown()
        // The last transaction is the one that produced the response; earlier
        // ones are redirects and are reported separately by duration.
        guard let transaction = metrics.transactionMetrics.last else { return breakdown }

        func interval(_ start: Date?, _ end: Date?) -> TimeInterval {
            guard let start, let end else { return 0 }
            return max(0, end.timeIntervalSince(start))
        }

        breakdown.dns = interval(transaction.domainLookupStartDate, transaction.domainLookupEndDate)
        breakdown.connect = interval(transaction.connectStartDate, transaction.secureConnectionStartDate)
            + interval(transaction.secureConnectionEndDate, transaction.connectEndDate)
        breakdown.tls = interval(
            transaction.secureConnectionStartDate,
            transaction.secureConnectionEndDate
        )
        breakdown.request = interval(transaction.requestStartDate, transaction.requestEndDate)
        breakdown.waiting = interval(transaction.requestEndDate, transaction.responseStartDate)
        breakdown.download = interval(transaction.responseStartDate, transaction.responseEndDate)
        return breakdown
    }

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from json: String?) -> TimingBreakdown? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TimingBreakdown.self, from: data)
    }
}

nonisolated struct ExecutionResult: Sendable {
    let statusCode: Int
    let statusText: String
    let headers: [(name: String, value: String)]
    let body: Data
    let duration: TimeInterval
    let timing: TimingBreakdown?

    var headersJSON: String {
        let pairs = headers.map { ["name": $0.name, "value": $0.value] }
        guard
            let data = try? JSONSerialization.data(withJSONObject: pairs, options: [.prettyPrinted]),
            let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }

    static func decodeHeaders(from json: String?) -> [(name: String, value: String)] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let pairs = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }
        return pairs.compactMap { pair in
            guard let name = pair["name"], let value = pair["value"] else { return nil }
            return (name, value)
        }
    }
}

enum ExecutionError: Error, LocalizedError {
    case invalidURL(String)
    case cancelled
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            "“\(url)” is not a valid URL."
        case .cancelled:
            "The request was cancelled."
        case .transport(let message):
            message
        }
    }
}

/// Sends requests over `URLSession`.
nonisolated final class RequestExecutor: Sendable {

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpShouldSetCookies = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Sends `request`, returning status, headers, body, and timing.
    ///
    /// Cancellation comes from the enclosing `Task`: `URLSession`'s async API
    /// cancels the underlying task when the Swift task is cancelled, so the
    /// caller only has to hold the handle.
    func execute(_ request: ResolvedRequest) async throws -> ExecutionResult {
        guard
            let url = URL(string: request.url),
            url.scheme != nil,
            url.host != nil
        else {
            throw ExecutionError.invalidURL(request.url)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout
        urlRequest.httpBody = request.body
        for header in request.headers {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let collector = TaskObserver(followRedirects: request.followRedirects)
        let started = ContinuousClock.now

        do {
            let (data, response) = try await session.data(for: urlRequest, delegate: collector)
            let elapsed = started.duration(to: .now)
            let duration = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ExecutionError.transport("The server did not return an HTTP response.")
            }

            let headers = httpResponse.allHeaderFields.compactMap { key, value -> (String, String)? in
                guard let name = key as? String else { return nil }
                return (name, String(describing: value))
            }.sorted { $0.0.lowercased() < $1.0.lowercased() }

            return ExecutionResult(
                statusCode: httpResponse.statusCode,
                statusText: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                headers: headers.map { (name: $0.0, value: $0.1) },
                body: data,
                duration: duration,
                timing: collector.collectedMetrics.map(TimingBreakdown.from)
            )
        } catch is CancellationError {
            throw ExecutionError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw ExecutionError.cancelled
        } catch let error as URLError {
            throw ExecutionError.transport(Self.message(for: error))
        }
    }

    /// Plain-language messages; `URLError`'s own descriptions are vague about
    /// the cases an API client hits most.
    private static func message(for error: URLError) -> String {
        switch error.code {
        case .timedOut: "The request timed out."
        case .cannotFindHost: "Could not find that host."
        case .cannotConnectToHost: "Could not connect to that host."
        case .notConnectedToInternet: "No internet connection."
        case .networkConnectionLost: "The network connection was lost."
        case .secureConnectionFailed: "The secure connection failed."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            "The server's certificate could not be trusted."
        case .unsupportedURL: "That URL scheme isn't supported."
        default: error.localizedDescription
        }
    }
}

/// Collects metrics and enforces the redirect policy for one task.
private final class TaskObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    private let followRedirects: Bool
    private let lock = NSLock()
    private var metrics: URLSessionTaskMetrics?

    var collectedMetrics: URLSessionTaskMetrics? {
        lock.withLock { metrics }
    }

    init(followRedirects: Bool) {
        self.followRedirects = followRedirects
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        lock.withLock { self.metrics = metrics }
    }

    /// Passing nil stops the redirect and hands back the 3xx itself, which is
    /// what an API client user who turned redirects off wants to see.
    ///
    /// Uses the completion-handler form rather than the `async` one: Swift
    /// 6.4's frontend crashes emitting the ObjC thunk for the async variant of
    /// this specific delegate method (`swift-frontend` segfaults in
    /// `emitNativeToForeignThunk`). Behavior is identical.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(followRedirects ? request : nil)
    }
}
