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
        // Snapshot headers as JSON
        let headersDict = Dictionary(headers.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let headersData = try? JSONEncoder().encode(headersDict)

        // Create the run with request snapshot
        let run = APICallRun(
            request: request,
            method: method,
            url: urlString,
            headers: headersData,
            body: bodyContent,
            bodyType: bodyType
        )
        context.insert(run)
        try? context.save()

        let runId = run.id
        let requestId = request.id

        logger.info("Run \(runId) created [pending] for \(method) \(urlString)")

        // Execute async — network call is non-blocking, SwiftData updates stay on main context
        let task = Task { [weak self] in
            run.status = .running
            try? context.save()
            logger.info("Run \(runId) status → running")

            do {
                let result = try await self?.requestExecutor.execute(
                    method: method,
                    urlString: urlString,
                    headers: headers,
                    bodyType: bodyType,
                    bodyContent: bodyContent
                )

                guard let result else {
                    run.errorMessage = "Service deallocated"
                    run.status = .failed
                    logger.error("Run \(runId) status → failed [service deallocated]")
                    try? context.save()
                    return
                }

                run.statusCode = result.statusCode
                run.statusText = result.statusText
                run.responseHeaders = try? JSONEncoder().encode(result.headers)
                run.responseBody = result.body
                run.responseBodyString = result.bodyString
                run.duration = result.duration
                run.size = result.size
                run.status = .completed
                logger.info("Run \(runId) status → completed [\(result.statusCode)] in \(String(format: "%.0f", result.duration * 1000))ms")
            } catch is CancellationError {
                run.errorMessage = "Cancelled"
                run.status = .failed
                logger.info("Run \(runId) status → failed [cancelled]")
            } catch {
                run.errorMessage = error.localizedDescription
                run.status = .failed
                logger.error("Run \(runId) status → failed: \(error.localizedDescription)")
            }

            try? context.save()
            logger.debug("Run \(runId) saved to SwiftData")

            // Prune old runs
            self?.pruneRuns(for: requestId, in: context)
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
