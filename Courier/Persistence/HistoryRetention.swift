import CoreData
import Foundation
import OSLog

/// Prunes run history so the store doesn't grow without bound.
///
/// Run history is the only unbounded growth in a Courier library: every send
/// writes a row plus a response body. The policy keeps the most recent `limit`
/// runs per request, and never deletes a starred run — starring is the user
/// saying "keep this one". See REQUIREMENTS.md §4.3.
enum HistoryRetention {

    static let defaultLimit = 50

    private static let logger = Logger(subsystem: "com.perezstudio.Courier", category: "retention")

    /// Prunes every request's history. Returns how many runs were deleted.
    ///
    /// Deletes objects individually rather than via `NSBatchDeleteRequest` so
    /// cascade rules fire and the external binary files backing response bodies
    /// are reclaimed. A batch delete bypasses the object graph and would leak
    /// those files.
    @discardableResult
    static func prune(in context: NSManagedObjectContext, limit: Int = defaultLimit) throws -> Int {
        let requestFetch = CDRequest.fetchRequest()
        let requests = try context.fetch(requestFetch)

        var deleted = 0
        for request in requests {
            deleted += try prune(request: request, in: context, limit: limit)
        }

        if context.hasChanges {
            try context.save()
        }
        if deleted > 0 {
            logger.info("Pruned \(deleted) run(s) from history")
        }
        return deleted
    }

    /// Prunes a single request's history.
    @discardableResult
    static func prune(
        request: CDRequest,
        in context: NSManagedObjectContext,
        limit: Int = defaultLimit
    ) throws -> Int {
        let ordered = request.runs.sorted { $0.createdAt > $1.createdAt }

        var kept = 0
        var deleted = 0
        for run in ordered {
            if run.isStarred { continue }
            kept += 1
            if kept > limit {
                context.delete(run)
                deleted += 1
            }
        }
        return deleted
    }
}
