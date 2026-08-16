import CoreData
import Foundation

@objc(CDEnvironment)
final class CDEnvironment: NSManagedObject {

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var sortOrder: Int32

    @NSManaged var workspace: CDWorkspace?
    @NSManaged var variables: Set<CDVariable>

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    static func fetchRequest() -> NSFetchRequest<CDEnvironment> {
        NSFetchRequest<CDEnvironment>(entityName: "CDEnvironment")
    }
}

@objc(CDVariable)
final class CDVariable: NSManagedObject {

    @NSManaged var id: UUID
    @NSManaged var key: String
    /// Always empty when `isSecret` is true — the real value lives in the
    /// Keychain, addressed by `id`. See REQUIREMENTS.md §6.
    @NSManaged var value: String
    @NSManaged var isSecret: Bool
    @NSManaged var isEnabled: Bool
    @NSManaged var sortOrder: Int32

    /// Set when the variable is environment-scoped.
    @NSManaged var environment: CDEnvironment?
    /// Set when the variable is collection-scoped (workspace-wide).
    @NSManaged var workspace: CDWorkspace?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    static func fetchRequest() -> NSFetchRequest<CDVariable> {
        NSFetchRequest<CDVariable>(entityName: "CDVariable")
    }
}
