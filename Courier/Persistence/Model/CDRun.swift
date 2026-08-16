import CoreData
import Foundation

enum RunStatus: String, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

@objc(CDRun)
final class CDRun: NSManagedObject {

    @NSManaged var id: UUID
    @NSManaged var statusRaw: String
    @NSManaged var isStarred: Bool

    // Optional scalars are NSNumber-backed: nil genuinely means "no response
    // yet", which a scalar with a sentinel value could not express. The
    // NSNumber awkwardness stays inside Persistence/ — repositories hand out
    // Swift optionals via snapshots.
    @NSManaged var statusCode: NSNumber?
    @NSManaged var duration: NSNumber?
    @NSManaged var size: NSNumber?

    @NSManaged var statusText: String?
    @NSManaged var errorMessage: String?
    @NSManaged var requestMethod: String
    @NSManaged var requestURL: String
    @NSManaged var createdAt: Date
    @NSManaged var timingJSON: String?

    @NSManaged var request: CDRequest?
    @NSManaged var responseBody: CDRunResponseBody?
    @NSManaged var responseHeaders: CDRunResponseHeaders?
    @NSManaged var requestSnapshot: CDRunRequestSnapshot?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date()
    }

    static func fetchRequest() -> NSFetchRequest<CDRun> {
        NSFetchRequest<CDRun>(entityName: "CDRun")
    }

    var status: RunStatus {
        get { RunStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

@objc(CDRunResponseBody)
final class CDRunResponseBody: NSManagedObject {

    @NSManaged var id: UUID
    @NSManaged var data: Data?
    @NSManaged var run: CDRun?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    static func fetchRequest() -> NSFetchRequest<CDRunResponseBody> {
        NSFetchRequest<CDRunResponseBody>(entityName: "CDRunResponseBody")
    }
}

@objc(CDRunResponseHeaders)
final class CDRunResponseHeaders: NSManagedObject {

    @NSManaged var id: UUID
    @NSManaged var json: String
    @NSManaged var run: CDRun?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    static func fetchRequest() -> NSFetchRequest<CDRunResponseHeaders> {
        NSFetchRequest<CDRunResponseHeaders>(entityName: "CDRunResponseHeaders")
    }
}

@objc(CDRunRequestSnapshot)
final class CDRunRequestSnapshot: NSManagedObject {

    @NSManaged var id: UUID
    /// The URL, headers, and body actually sent, with secrets redacted.
    @NSManaged var json: String
    @NSManaged var run: CDRun?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    static func fetchRequest() -> NSFetchRequest<CDRunRequestSnapshot> {
        NSFetchRequest<CDRunRequestSnapshot>(entityName: "CDRunRequestSnapshot")
    }
}

@objc(CDUIState)
final class CDUIState: NSManagedObject {

    @NSManaged var key: String
    @NSManaged var json: String

    static func fetchRequest() -> NSFetchRequest<CDUIState> {
        NSFetchRequest<CDUIState>(entityName: "CDUIState")
    }
}
