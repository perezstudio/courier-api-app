import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var sortOrder: Int
    var isExpanded: Bool
    var workspace: Workspace?
    var parentFolder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Folder.parentFolder) var subFolders: [Folder]
    @Relationship(deleteRule: .cascade, inverse: \APIRequest.folder) var requests: [APIRequest]

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.isExpanded = true
        self.subFolders = []
        self.requests = []
    }
}
