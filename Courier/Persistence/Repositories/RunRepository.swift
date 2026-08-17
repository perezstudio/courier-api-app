import CoreData
import Foundation

/// Run history. Heavy payloads (body, headers, request snapshot) live in
/// separate entities so listing runs never faults in megabytes of response data.
@MainActor
final class RunRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Runs for a request, newest first.
    func runs(forRequest requestID: UUID, limit: Int? = nil) throws -> [RunSummary] {
        let request = CDRun.fetchRequest()
        request.predicate = NSPredicate(format: "request.id == %@", requestID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        if let limit { request.fetchLimit = limit }
        return try context.fetch(request).map(Self.summary(of:))
    }

    func run(id: UUID) throws -> RunSummary? {
        try fetchRun(id).map(Self.summary(of:))
    }

    /// Creates a run in `.pending`, before the request goes out.
    @discardableResult
    func createRun(forRequest requestID: UUID, method: String, url: String) throws -> RunSummary {
        let requestFetch = CDRequest.fetchRequest()
        requestFetch.predicate = NSPredicate(format: "id == %@", requestID as CVarArg)
        requestFetch.fetchLimit = 1
        guard let apiRequest = try context.fetch(requestFetch).first else {
            throw LibraryRepository.RepositoryError.notFound
        }

        let run = CDRun(context: context)
        run.request = apiRequest
        run.requestMethod = method
        run.requestURL = url
        run.status = .pending
        try context.save()
        return Self.summary(of: run)
    }

    func setStatus(_ status: RunStatus, forRun id: UUID) throws {
        guard let run = try fetchRun(id) else { throw LibraryRepository.RepositoryError.notFound }
        run.status = status
        try context.save()
    }

    /// Records a completed response and its payloads in one save.
    func complete(
        runID: UUID,
        statusCode: Int,
        statusText: String,
        duration: TimeInterval,
        body: Data,
        headersJSON: String,
        requestSnapshotJSON: String,
        timingJSON: String?
    ) throws {
        guard let run = try fetchRun(runID) else { throw LibraryRepository.RepositoryError.notFound }

        run.status = .completed
        run.statusCode = NSNumber(value: statusCode)
        run.statusText = statusText
        run.duration = NSNumber(value: duration)
        run.size = NSNumber(value: body.count)
        run.timingJSON = timingJSON

        let bodyEntity = run.responseBody ?? CDRunResponseBody(context: context)
        bodyEntity.data = body
        bodyEntity.run = run

        let headersEntity = run.responseHeaders ?? CDRunResponseHeaders(context: context)
        headersEntity.json = headersJSON
        headersEntity.run = run

        let snapshotEntity = run.requestSnapshot ?? CDRunRequestSnapshot(context: context)
        snapshotEntity.json = requestSnapshotJSON
        snapshotEntity.run = run

        try context.save()
    }

    func fail(runID: UUID, message: String, duration: TimeInterval?) throws {
        guard let run = try fetchRun(runID) else { throw LibraryRepository.RepositoryError.notFound }
        run.status = .failed
        run.errorMessage = message
        if let duration { run.duration = NSNumber(value: duration) }
        try context.save()
    }

    func setStarred(_ isStarred: Bool, forRun id: UUID) throws {
        guard let run = try fetchRun(id) else { throw LibraryRepository.RepositoryError.notFound }
        run.isStarred = isStarred
        try context.save()
    }

    /// Faults in the response body only when something actually needs it.
    func responseBody(forRun id: UUID) throws -> Data? {
        try fetchRun(id)?.responseBody?.data
    }

    func responseHeadersJSON(forRun id: UUID) throws -> String? {
        try fetchRun(id)?.responseHeaders?.json
    }

    func requestSnapshotJSON(forRun id: UUID) throws -> String? {
        try fetchRun(id)?.requestSnapshot?.json
    }

    /// Timing lives on the run itself rather than in a payload entity, since
    /// it is small enough not to be worth faulting separately.
    func timingJSON(forRun id: UUID) throws -> String? {
        try fetchRun(id)?.timingJSON
    }

    func deleteRun(id: UUID) throws {
        guard let run = try fetchRun(id) else { return }
        context.delete(run)
        try context.save()
    }

    private func fetchRun(_ id: UUID) throws -> CDRun? {
        let request = CDRun.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func summary(of run: CDRun) -> RunSummary {
        RunSummary(
            id: run.id,
            requestID: run.request?.id,
            status: run.status,
            isStarred: run.isStarred,
            statusCode: run.statusCode?.intValue,
            statusText: run.statusText,
            duration: run.duration?.doubleValue,
            size: run.size?.intValue,
            errorMessage: run.errorMessage,
            method: run.requestMethod,
            url: run.requestURL,
            createdAt: run.createdAt
        )
    }
}
