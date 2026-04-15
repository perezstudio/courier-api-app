import Foundation
import SwiftData

enum RunStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
}

@Model
final class APICallRun {
    var id: UUID
    var request: APIRequest?

    // Status
    var statusRaw: String
    var isStarred: Bool

    // Response metadata (lightweight)
    var statusCode: Int?
    var statusText: String?
    var duration: Double?
    var size: Int?
    var errorMessage: String?

    // Request snapshot (lightweight)
    var requestMethod: String
    var requestURL: String

    // Meta
    var createdAt: Date

    // Heavy data — separate models, faulted in only on access
    @Relationship(deleteRule: .cascade, inverse: \APICallRunResponseBody.run)
    var responseBody: APICallRunResponseBody?

    @Relationship(deleteRule: .cascade, inverse: \APICallRunResponseHeaders.run)
    var responseHeaders: APICallRunResponseHeaders?

    @Relationship(deleteRule: .cascade, inverse: \APICallRunRequestSnapshot.run)
    var requestSnapshot: APICallRunRequestSnapshot?

    var status: RunStatus {
        get { RunStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        request: APIRequest,
        method: String,
        url: String
    ) {
        self.id = UUID()
        self.request = request
        self.statusRaw = RunStatus.pending.rawValue
        self.isStarred = false
        self.requestMethod = method
        self.requestURL = url
        self.createdAt = Date()
    }
}
