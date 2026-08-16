import CoreData
import Foundation

@objc(CDFolder)
final class CDFolder: NSManagedObject {

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var sortOrder: Int32
    @NSManaged var isExpanded: Bool

    @NSManaged var workspace: CDWorkspace?
    @NSManaged var parentFolder: CDFolder?
    @NSManaged var subfolders: Set<CDFolder>
    @NSManaged var requests: Set<CDRequest>

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    static func fetchRequest() -> NSFetchRequest<CDFolder> {
        NSFetchRequest<CDFolder>(entityName: "CDFolder")
    }

    /// The workspace this folder belongs to, walking up through any parents.
    /// Only root folders carry the `workspace` relationship directly.
    var owningWorkspace: CDWorkspace? {
        var node: CDFolder? = self
        while let current = node {
            if let workspace = current.workspace { return workspace }
            node = current.parentFolder
        }
        return nil
    }
}
