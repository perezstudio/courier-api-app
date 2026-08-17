import Foundation
import OSLog

/// Runs requests and records the results.
///
/// Holds the in-flight `Task` so Send can become Cancel: cancelling the task
/// cancels the underlying `URLSession` task, which is why the executor needs no
/// cancellation plumbing of its own.
@MainActor
final class ResponseController {

    enum State {
        case idle
        case sending
        case finished(ExecutionResult)
        case failed(String)
    }

    private static let logger = Logger(subsystem: "com.perezstudio.Courier", category: "http")

    private let libraryController: LibraryController
    private let executor: RequestExecutor

    private(set) var state: State = .idle
    private var inFlight: Task<Void, Never>?

    var onStateChange: ((State) -> Void)?
    var onHistoryChange: (() -> Void)?

    var isSending: Bool {
        if case .sending = state { return true }
        return false
    }

    init(libraryController: LibraryController, executor: RequestExecutor = RequestExecutor()) {
        self.libraryController = libraryController
        self.executor = executor
    }

    // MARK: - Sending

    func send(input: RequestBuilder.Input, requestID: UUID, context: VariableResolver.Context) {
        cancel()

        let built = RequestBuilder.build(input, context: context)
        if !built.unresolved.isEmpty {
            // Unresolved placeholders are surfaced, not fatal — the request
            // still goes out with the braces intact so the failure is visible
            // in the response rather than silently hitting a wrong URL.
            Self.logger.info("Sending with unresolved variables: \(built.unresolved.joined(separator: ", "))")
        }

        setState(.sending)

        let runSummary = try? libraryController.runs.createRun(
            forRequest: requestID,
            method: built.request.method,
            url: built.request.url
        )

        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await executor.execute(built.request)
                guard !Task.isCancelled else { return }
                self.finish(result, runID: runSummary?.id, request: built.request)
            } catch {
                guard !Task.isCancelled else { return }
                self.fail(error, runID: runSummary?.id)
            }
        }
    }

    func cancel() {
        guard let task = inFlight else { return }
        task.cancel()
        inFlight = nil
        if isSending {
            setState(.failed("Cancelled."))
        }
    }

    // MARK: - Completion

    private func finish(_ result: ExecutionResult, runID: UUID?, request: ResolvedRequest) {
        inFlight = nil

        if let runID {
            try? libraryController.runs.complete(
                runID: runID,
                statusCode: result.statusCode,
                statusText: result.statusText,
                duration: result.duration,
                body: result.body,
                headersJSON: result.headersJSON,
                requestSnapshotJSON: request.redactedJSON(),
                timingJSON: result.timing?.encodedJSON()
            )
            onHistoryChange?()
        }
        setState(.finished(result))
    }

    private func fail(_ error: Error, runID: UUID?) {
        inFlight = nil

        let message = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription

        if let runID {
            try? libraryController.runs.fail(runID: runID, message: message, duration: nil)
            onHistoryChange?()
        }
        setState(.failed(message))
    }

    private func setState(_ newState: State) {
        state = newState
        onStateChange?(newState)
    }

    // MARK: - History

    func runs(forRequest requestID: UUID) -> [RunSummary] {
        (try? libraryController.runs.runs(forRequest: requestID, limit: 100)) ?? []
    }

    func storedRun(id: UUID) -> (summary: RunSummary, body: Data?, headers: String?, timing: String?)? {
        guard let summary = try? libraryController.runs.run(id: id) else { return nil }
        return (
            summary,
            try? libraryController.runs.responseBody(forRun: id),
            try? libraryController.runs.responseHeadersJSON(forRun: id),
            nil
        )
    }

    func setStarred(_ isStarred: Bool, runID: UUID) {
        try? libraryController.runs.setStarred(isStarred, forRun: runID)
        onHistoryChange?()
    }
}
