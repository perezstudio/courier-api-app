import Foundation
import SwiftData

@Model
final class APIRequest {
    var id: UUID
    var name: String
    var sortOrder: Int
    var method: String
    var urlTemplate: String
    var folder: Folder?
    /// Set when the request lives at the workspace root (no parent folder).
    /// Exactly one of `folder` or `workspace` should be non-nil.
    var workspace: Workspace?
    @Relationship(deleteRule: .cascade, inverse: \Header.request) var headers: [Header]
    @Relationship(deleteRule: .cascade, inverse: \QueryParam.request) var queryParams: [QueryParam]
    @Relationship(deleteRule: .cascade, inverse: \APICallRun.request) var runs: [APICallRun]
    var bodyType: String?
    var bodyContent: String?
    var authType: String?
    var authData: String?
    var preRequestScript: String?
    var postResponseScript: String?
    var createdAt: Date
    var updatedAt: Date

    init(name: String, method: String = "GET", urlTemplate: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.method = method
        self.urlTemplate = urlTemplate
        self.headers = []
        self.queryParams = []
        self.runs = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
