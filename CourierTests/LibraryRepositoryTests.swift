import CoreData
import Foundation
import Testing

@testable import Courier

@MainActor
@Suite("Library CRUD")
struct LibraryRepositoryTests {

    @Test("Model loads and every entity is present")
    func modelLoads() throws {
        let stack = try CoreDataStack(location: .inMemory)
        let entities = Set(stack.container.managedObjectModel.entities.compactMap(\.name))
        let expected: Set = [
            "CDWorkspace", "CDFolder", "CDRequest", "CDHeader", "CDQueryParam",
            "CDEnvironment", "CDVariable", "CDRun", "CDRunResponseBody",
            "CDRunResponseHeaders", "CDRunRequestSnapshot", "CDUIState",
        ]
        #expect(entities.isSuperset(of: expected))
    }

    @Test("Every relationship has an inverse")
    func relationshipsHaveInverses() throws {
        let stack = try CoreDataStack(location: .inMemory)
        for entity in stack.container.managedObjectModel.entities {
            for (name, relationship) in entity.relationshipsByName {
                #expect(
                    relationship.inverseRelationship != nil,
                    "\(entity.name ?? "?").\(name) has no inverse"
                )
            }
        }
    }

    @Test("Workspaces are created and listed in order")
    func createsWorkspaces() throws {
        let s = try TestStack()
        try s.library.createWorkspace(name: "Alpha")
        try s.library.createWorkspace(name: "Beta")

        let workspaces = try s.library.workspaces()
        #expect(workspaces.map(\.name) == ["Alpha", "Beta"])
        #expect(workspaces.map(\.sortOrder) == [0, 1])
    }

    @Test("Requests can live at the workspace root or in a folder")
    func requestsAtBothLevels() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let folder = try s.library.createFolder(name: "Users", in: .workspaceRoot(workspace))

        try s.library.createRequest(name: "Root Request", in: .workspaceRoot(workspace))
        try s.library.createRequest(name: "Nested", in: .folder(folder.id))

        let tree = try s.library.tree(forWorkspace: workspace)
        // Folders sort before requests at each level.
        #expect(s.names(tree) == ["Users", "Root Request"])

        let children = try s.children(ofFolder: folder.id, inWorkspace: workspace)
        #expect(s.names(children) == ["Nested"])
    }

    @Test("Request count includes nested folders")
    func requestCountIsRecursive() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let outer = try s.library.createFolder(name: "Outer", in: .workspaceRoot(workspace))
        let inner = try s.library.createFolder(name: "Inner", in: .folder(outer.id))

        try s.library.createRequest(name: "A", in: .workspaceRoot(workspace))
        try s.library.createRequest(name: "B", in: .folder(outer.id))
        try s.library.createRequest(name: "C", in: .folder(inner.id))

        let snapshot = try #require(try s.library.workspaces().first)
        #expect(snapshot.requestCount == 3)
    }

    @Test("Renaming works for all three levels")
    func renames() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace("Before")
        let folder = try s.library.createFolder(name: "Before", in: .workspaceRoot(workspace))
        let request = try s.library.createRequest(name: "Before", in: .folder(folder.id))

        try s.library.renameWorkspace(id: workspace, to: "After")
        try s.library.renameFolder(id: folder.id, to: "After")
        try s.library.renameRequest(id: request.id, to: "After")

        #expect(try s.library.workspaces().first?.name == "After")
        let tree = try s.library.tree(forWorkspace: workspace)
        #expect(s.names(tree) == ["After"])
        #expect(s.names(try s.children(ofFolder: folder.id, inWorkspace: workspace)) == ["After"])
    }

    @Test("Duplicating a request copies headers and params but not run history")
    func duplicateRequest() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let original = try s.library.createRequest(name: "Get User", in: .workspaceRoot(workspace))

        try s.requests.replaceHeaders(
            [KeyValueRow(key: "Accept", value: "application/json")],
            for: original.id
        )
        try s.requests.replaceQueryParams(
            [KeyValueRow(key: "page", value: "1", isEnabled: false)],
            for: original.id
        )
        try s.runs.createRun(forRequest: original.id, method: "GET", url: "https://example.com")

        let copy = try s.library.duplicateRequest(id: original.id)
        #expect(copy.name == "Get User copy")

        let detail = try s.requests.detail(for: copy.id)
        #expect(detail.headers.map(\.key) == ["Accept"])
        #expect(detail.queryParams.first?.isEnabled == false)
        #expect(try s.runs.runs(forRequest: copy.id).isEmpty)
        // The original keeps its history.
        #expect(try s.runs.runs(forRequest: original.id).count == 1)
    }

    @Test("Deleting a folder cascades to its whole subtree")
    func deleteCascades() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let outer = try s.library.createFolder(name: "Outer", in: .workspaceRoot(workspace))
        let inner = try s.library.createFolder(name: "Inner", in: .folder(outer.id))
        let request = try s.library.createRequest(name: "Doomed", in: .folder(inner.id))

        try s.requests.replaceHeaders([KeyValueRow(key: "X", value: "1")], for: request.id)

        try s.library.deleteFolder(id: outer.id)

        #expect(try s.library.tree(forWorkspace: workspace).isEmpty)
        // Headers hang off the request, which hung off the deleted subtree.
        let headerCount = try s.context.count(for: CDHeader.fetchRequest())
        #expect(headerCount == 0)
        let requestCount = try s.context.count(for: CDRequest.fetchRequest())
        #expect(requestCount == 0)
    }

    @Test("Deleting a workspace cascades to everything it owns")
    func deleteWorkspaceCascades() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let folder = try s.library.createFolder(name: "F", in: .workspaceRoot(workspace))
        try s.library.createRequest(name: "R", in: .folder(folder.id))
        try s.environments.createEnvironment(name: "Prod", inWorkspace: workspace)

        try s.library.deleteWorkspace(id: workspace)

        #expect(try s.context.count(for: CDFolder.fetchRequest()) == 0)
        #expect(try s.context.count(for: CDRequest.fetchRequest()) == 0)
        #expect(try s.context.count(for: CDEnvironment.fetchRequest()) == 0)
    }
}
