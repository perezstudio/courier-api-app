import CoreData
import Foundation

/// Shared shape for the two key-value entities. Headers and query params carry
/// identical data but stay distinct entities so a request's two collections can
/// be fetched and cascaded independently.
///
/// Explicitly `nonisolated`: the target defaults to MainActor isolation, but
/// managed objects are touched from `awakeFromInsert()` and background contexts,
/// neither of which is on the main actor.
nonisolated protocol KeyValueEntity: NSManagedObject {
    var id: UUID { get set }
    var key: String { get set }
    var value: String { get set }
    var isEnabled: Bool { get set }
    var sortOrder: Int32 { get set }
    var note: String? { get set }
    var request: CDRequest? { get set }
}

@objc(CDHeader)
final class CDHeader: NSManagedObject, KeyValueEntity {

    @NSManaged var id: UUID
    @NSManaged var key: String
    @NSManaged var value: String
    @NSManaged var isEnabled: Bool
    @NSManaged var sortOrder: Int32
    @NSManaged var note: String?
    @NSManaged var request: CDRequest?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    static func fetchRequest() -> NSFetchRequest<CDHeader> {
        NSFetchRequest<CDHeader>(entityName: "CDHeader")
    }
}

@objc(CDQueryParam)
final class CDQueryParam: NSManagedObject, KeyValueEntity {

    @NSManaged var id: UUID
    @NSManaged var key: String
    @NSManaged var value: String
    @NSManaged var isEnabled: Bool
    @NSManaged var sortOrder: Int32
    @NSManaged var note: String?
    @NSManaged var request: CDRequest?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    static func fetchRequest() -> NSFetchRequest<CDQueryParam> {
        NSFetchRequest<CDQueryParam>(entityName: "CDQueryParam")
    }
}
