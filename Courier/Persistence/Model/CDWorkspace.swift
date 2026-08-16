import CoreData
import Foundation

@objc(CDWorkspace)
final class CDWorkspace: NSManagedObject {

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var sortOrder: Int32
    @NSManaged var iconSymbolName: String
    @NSManaged var createdAt: Date
    @NSManaged var activeEnvironmentID: UUID?

    @NSManaged var folders: Set<CDFolder>
    @NSManaged var requests: Set<CDRequest>
    @NSManaged var environments: Set<CDEnvironment>
    @NSManaged var variables: Set<CDVariable>

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date()
    }

    static func fetchRequest() -> NSFetchRequest<CDWorkspace> {
        NSFetchRequest<CDWorkspace>(entityName: "CDWorkspace")
    }
}
