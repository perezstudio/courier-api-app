import Foundation
import SwiftData

@Model
final class Workspace {
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Folder.workspace) var folders: [Folder]
    @Relationship(deleteRule: .cascade, inverse: \Environment.workspace) var environments: [Environment]
    var activeEnvironmentId: UUID?

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.folders = []
        self.environments = []
    }
}
