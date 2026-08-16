import CoreData
import Foundation

@objc(CDRequest)
final class CDRequest: NSManagedObject {

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var sortOrder: Int32
    @NSManaged var method: String
    @NSManaged var urlTemplate: String

    @NSManaged var bodyType: String
    @NSManaged var bodyContent: String?
    @NSManaged var binaryBookmark: Data?
    @NSManaged var graphqlVariables: String?

    @NSManaged var authType: String
    @NSManaged var authData: Data?

    @NSManaged var followRedirects: Bool
    @NSManaged var timeout: Double

    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    @NSManaged var folder: CDFolder?
    @NSManaged var workspace: CDWorkspace?
    @NSManaged var headers: Set<CDHeader>
    @NSManaged var queryParams: Set<CDQueryParam>
    @NSManaged var runs: Set<CDRun>

    override func awakeFromInsert() {
        super.awakeFromInsert()
        let now = Date()
        id = UUID()
        createdAt = now
        updatedAt = now
    }

    static func fetchRequest() -> NSFetchRequest<CDRequest> {
        NSFetchRequest<CDRequest>(entityName: "CDRequest")
    }

    /// Exactly one of `folder` / `workspace` is set: a request either lives in a
    /// folder or at the workspace root.
    var owningWorkspace: CDWorkspace? {
        workspace ?? folder?.owningWorkspace
    }
}
