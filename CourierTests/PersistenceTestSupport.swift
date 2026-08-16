import CoreData
import Foundation
import Testing

@testable import Courier

/// A fresh in-memory stack per test, with repositories wired up.
///
/// Nothing here touches the disk or the developer's Keychain — the secret store
/// is the in-memory double.
@MainActor
struct TestStack {
    let stack: CoreDataStack
    let secrets: InMemorySecretStore
    let library: LibraryRepository
    let requests: RequestRepository
    let environments: EnvironmentRepository
    let runs: RunRepository

    init() throws {
        stack = try CoreDataStack(location: .inMemory)
        secrets = InMemorySecretStore()
        library = LibraryRepository(context: stack.viewContext)
        requests = RequestRepository(context: stack.viewContext)
        environments = EnvironmentRepository(context: stack.viewContext, secretStore: secrets)
        runs = RunRepository(context: stack.viewContext)
    }

    var context: NSManagedObjectContext { stack.viewContext }

    /// Creates a workspace and returns its id.
    @discardableResult
    func makeWorkspace(_ name: String = "Test") throws -> UUID {
        try library.createWorkspace(name: name).id
    }

    /// The display-ordered names at one level of the tree.
    func names(_ nodes: [TreeNode]) -> [String] {
        nodes.map(\.name)
    }

    /// Fetches the children of a folder from a freshly-read tree.
    func children(ofFolder folderID: UUID, inWorkspace workspaceID: UUID) throws -> [TreeNode] {
        let tree = try library.tree(forWorkspace: workspaceID)
        return Self.findFolder(folderID, in: tree)?.children ?? []
    }

    static func findFolder(_ id: UUID, in nodes: [TreeNode]) -> FolderSnapshot? {
        for node in nodes {
            guard case .folder(let folder) = node else { continue }
            if folder.id == id { return folder }
            if let found = findFolder(id, in: folder.children) { return found }
        }
        return nil
    }
}
