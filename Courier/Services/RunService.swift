import AppKit
import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "com.perezstudio.Courier", category: "RunService")

@Observable
@MainActor
final class RunService {
    private let modelContainer: ModelContainer
    private let requestExecutor = RequestExecutor()
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Creates a run, persists it, then executes in the background. Returns the run immediately.
    func executeRun(
        for request: APIRequest,
        method: String,
        urlString: String,
        headers: [(key: String, value: String)],
        bodyType: String?,
        bodyContent: String?,
        context: ModelContext
    ) -> APICallRun {
        // Create lightweight run
        let run = APICallRun(
            request: request,
            method: method,
            url: urlString
        )
        context.insert(run)

        // Create request snapshot (heavy, stored separately)
        let snapshot = APICallRunRequestSnapshot(run: run)
        let headersDict = Dictionary(headers.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        snapshot.requestHeaders = try? JSONEncoder().encode(headersDict)
        snapshot.requestBody = bodyContent
        snapshot.requestBodyType = bodyType
        context.insert(snapshot)
        run.requestSnapshot = snapshot

        try? context.save()

        let runId = run.id
        let requestId = request.id

        logger.info("Run \(runId) created [pending] for \(method) \(urlString)")

        // Mark as running on MainActor
        run.status = .running
        try? context.save()
        logger.info("Run \(runId) status → running")

        let executor = requestExecutor
        let task = Task { [weak self] in
            // 1. Network call — async, does not block main thread
            let networkResult: ResponseResult
            do {
                networkResult = try await executor.execute(
                    method: method,
                    urlString: urlString,
                    headers: headers,
                    bodyType: bodyType,
                    bodyContent: bodyContent
                )
            } catch is CancellationError {
                await MainActor.run {
                    run.errorMessage = "Cancelled"
                    run.status = .failed
                    try? context.save()
                }
                logger.info("Run \(runId) status → failed [cancelled]")
                return
            } catch {
                await MainActor.run {
                    run.errorMessage = error.localizedDescription
                    run.status = .failed
                    try? context.save()
                }
                logger.error("Run \(runId) status → failed: \(error.localizedDescription)")
                return
            }

            // 2. Encode headers off main thread
            let encodedHeaders = try? JSONEncoder().encode(networkResult.headers)

            // 3. SwiftData writes — back on MainActor
            await MainActor.run {
                // Lightweight metadata
                run.statusCode = networkResult.statusCode
                run.statusText = networkResult.statusText
                run.duration = networkResult.duration
                run.size = networkResult.size

                // Heavy response body — separate model
                let responseBodyModel = APICallRunResponseBody(run: run)
                responseBodyModel.rawBody = networkResult.body
                responseBodyModel.bodyString = networkResult.bodyString
                context.insert(responseBodyModel)
                run.responseBody = responseBodyModel

                // Heavy response headers — separate model
                let responseHeadersModel = APICallRunResponseHeaders(run: run)
                responseHeadersModel.headersData = encodedHeaders
                context.insert(responseHeadersModel)
                run.responseHeaders = responseHeadersModel

                run.status = .completed
                try? context.save()
                logger.info("Run \(runId) status → completed [\(networkResult.statusCode)] in \(String(format: "%.0f", networkResult.duration * 1000))ms")

                // Prune old runs
                self?.pruneRuns(for: requestId, in: context)
            }
        }

        activeTasks[runId] = task
        return run
    }

    func cancelRun(_ run: APICallRun) {
        logger.info("Run \(run.id) cancellation requested")
        if let task = activeTasks[run.id] {
            task.cancel()
            activeTasks.removeValue(forKey: run.id)
        }
        run.errorMessage = "Cancelled"
        run.status = .failed
    }

    private func pruneRuns(for requestId: UUID, in context: ModelContext) {
        let descriptor = FetchDescriptor<APICallRun>(
            predicate: #Predicate { $0.request?.id == requestId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let allRuns = try? context.fetch(descriptor) else { return }

        // Keep starred runs + the 50 most recent non-starred
        var nonStarredCount = 0
        var pruned = 0
        for run in allRuns {
            if run.isStarred { continue }
            nonStarredCount += 1
            if nonStarredCount > 50 {
                context.delete(run)
                pruned += 1
            }
        }
        if pruned > 0 {
            logger.info("Pruned \(pruned) old runs for request \(requestId)")
        }
        try? context.save()
    }
}
