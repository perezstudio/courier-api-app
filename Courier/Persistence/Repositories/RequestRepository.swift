import CoreData
import Foundation

/// Request detail: URL, method, body, auth, headers, and query params.
@MainActor
final class RequestRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func detail(for id: UUID) throws -> RequestDetail {
        let request = try fetch(id)
        return RequestDetail(
            id: request.id,
            name: request.name,
            method: request.method,
            urlTemplate: request.urlTemplate,
            bodyType: request.bodyType,
            bodyContent: request.bodyContent,
            graphqlVariables: request.graphqlVariables,
            authType: request.authType,
            authData: request.authData,
            followRedirects: request.followRedirects,
            timeout: request.timeout,
            headers: Self.rows(request.headers),
            queryParams: Self.rows(request.queryParams)
        )
    }

    func update(id: UUID, _ mutate: (CDRequest) -> Void) throws {
        let request = try fetch(id)
        mutate(request)
        request.updatedAt = Date()
        try context.save()
    }

    func setURL(_ url: String, for id: UUID) throws {
        try update(id: id) { $0.urlTemplate = url }
    }

    func setMethod(_ method: String, for id: UUID) throws {
        try update(id: id) { $0.method = method }
    }

    func setBody(type: String, content: String?, for id: UUID) throws {
        try update(id: id) {
            $0.bodyType = type
            $0.bodyContent = content
        }
    }

    func setAuth(type: String, data: Data?, for id: UUID) throws {
        try update(id: id) {
            $0.authType = type
            $0.authData = data
        }
    }

    // MARK: - Headers & params

    /// Replaces a request's headers with `rows`, in order. Rewriting wholesale
    /// keeps the table view's model trivially in sync — these collections are
    /// small enough that diffing would cost more than it saves.
    func replaceHeaders(_ rows: [KeyValueRow], for id: UUID) throws {
        let request = try fetch(id)
        for existing in request.headers { context.delete(existing) }
        for (index, row) in rows.enumerated() {
            let header = CDHeader(context: context)
            header.key = row.key
            header.value = row.value
            header.isEnabled = row.isEnabled
            header.note = row.note
            header.sortOrder = Int32(index)
            header.request = request
        }
        request.updatedAt = Date()
        try context.save()
    }

    func replaceQueryParams(_ rows: [KeyValueRow], for id: UUID) throws {
        let request = try fetch(id)
        for existing in request.queryParams { context.delete(existing) }
        for (index, row) in rows.enumerated() {
            let param = CDQueryParam(context: context)
            param.key = row.key
            param.value = row.value
            param.isEnabled = row.isEnabled
            param.note = row.note
            param.sortOrder = Int32(index)
            param.request = request
        }
        request.updatedAt = Date()
        try context.save()
    }

    // MARK: - Helpers

    private func fetch(_ id: UUID) throws -> CDRequest {
        let request = CDRequest.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let result = try context.fetch(request).first else {
            throw LibraryRepository.RepositoryError.notFound
        }
        return result
    }

    private static func rows(_ items: some Collection<some KeyValueEntity>) -> [KeyValueRow] {
        items
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                KeyValueRow(
                    id: $0.id,
                    key: $0.key,
                    value: $0.value,
                    isEnabled: $0.isEnabled,
                    note: $0.note
                )
            }
    }
}
