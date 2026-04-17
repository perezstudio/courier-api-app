import Foundation
import SwiftData

@Model
final class Workspace {
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    /// SF Symbol name shown in the workspace tab and in the footer's active-dot slot.
    var iconSymbolName: String = "folder.fill"
    @Relationship(deleteRule: .cascade, inverse: \Folder.workspace) var folders: [Folder]
    /// Requests that live at the workspace root (not inside any folder).
    @Relationship(deleteRule: .cascade, inverse: \APIRequest.workspace) var requests: [APIRequest] = []
    @Relationship(deleteRule: .cascade, inverse: \Environment.workspace) var environments: [Environment]
    var activeEnvironmentId: UUID?

    init(name: String, sortOrder: Int = 0, iconSymbolName: String = "folder.fill") {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.iconSymbolName = iconSymbolName
        self.folders = []
        self.environments = []
    }
}
