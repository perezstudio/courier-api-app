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

    // Response
    var statusCode: Int?
    var statusText: String?
    var responseHeaders: Data?
    var responseBody: Data?
    var responseBodyString: String?
    var duration: Double?
    var size: Int?
    var errorMessage: String?

    // Request Snapshot
    var requestMethod: String
    var requestURL: String
    var requestHeaders: Data?
    var requestBody: String?
    var requestBodyType: String?

    // Meta
    var createdAt: Date

    var status: RunStatus {
        get { RunStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var decodedResponseHeaders: [String: String] {
        guard let data = responseHeaders else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    init(
        request: APIRequest,
        method: String,
        url: String,
        headers: Data? = nil,
        body: String? = nil,
        bodyType: String? = nil
    ) {
        self.id = UUID()
        self.request = request
        self.statusRaw = RunStatus.pending.rawValue
        self.isStarred = false
        self.requestMethod = method
        self.requestURL = url
        self.requestHeaders = headers
        self.requestBody = body
        self.requestBodyType = bodyType
        self.createdAt = Date()
    }
}
