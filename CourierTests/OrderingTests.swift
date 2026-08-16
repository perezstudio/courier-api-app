import Foundation
import Testing

@testable import Courier

/// Ordering and reparenting. These run before any UI exists deliberately —
/// REQUIREMENTS.md §11 calls the outline-view/Core-Data/drag-reorder
/// combination the most bug-prone part of the app, and a tree that reorders
/// wrongly is very hard to debug through a view.
@MainActor
@Suite("Ordering and moves")
struct OrderingTests {

    @Test("New siblings append in creation order")
    func appendsInOrder() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        for name in ["A", "B", "C"] {
            try s.library.createRequest(name: name, in: .workspaceRoot(workspace))
        }
        #expect(s.names(try s.library.tree(forWorkspace: workspace)) == ["A", "B", "C"])
    }

    @Test("Moving within a parent reorders and renumbers densely")
    func reordersWithinParent() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        var ids: [UUID] = []
        for name in ["A", "B", "C", "D"] {
            ids.append(try s.library.createRequest(name: name, in: .workspaceRoot(workspace)).id)
        }

        // Move D to the front.
        try s.library.move(nodeID: ids[3], to: .workspaceRoot(workspace), at: 0)

        let tree = try s.library.tree(forWorkspace: workspace)
        #expect(s.names(tree) == ["D", "A", "B", "C"])
        // Dense, gap-free renumbering is what keeps later inserts predictable.
        #expect(tree.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("Moving to the middle lands at the requested index")
    func movesToMiddle() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        var ids: [UUID] = []
        for name in ["A", "B", "C", "D"] {
            ids.append(try s.library.createRequest(name: name, in: .workspaceRoot(workspace)).id)
        }

        try s.library.move(nodeID: ids[0], to: .workspaceRoot(workspace), at: 2)
        #expect(s.names(try s.library.tree(forWorkspace: workspace)) == ["B", "C", "A", "D"])
    }

    @Test("Moving with no index appends")
    func moveWithoutIndexAppends() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        var ids: [UUID] = []
        for name in ["A", "B", "C"] {
            ids.append(try s.library.createRequest(name: name, in: .workspaceRoot(workspace)).id)
        }

        try s.library.move(nodeID: ids[0], to: .workspaceRoot(workspace))
        #expect(s.names(try s.library.tree(forWorkspace: workspace)) == ["B", "C", "A"])
    }

    @Test("Moving a request into a folder renumbers both parents")
    func reparentsRequest() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let folder = try s.library.createFolder(name: "Folder", in: .workspaceRoot(workspace))

        var ids: [UUID] = []
        for name in ["A", "B", "C"] {
            ids.append(try s.library.createRequest(name: name, in: .workspaceRoot(workspace)).id)
        }

        try s.library.move(nodeID: ids[1], to: .folder(folder.id), at: 0)

        let root = try s.library.tree(forWorkspace: workspace)
        #expect(s.names(root) == ["Folder", "A", "C"])
        // The source parent renumbers too — otherwise B's vacated slot leaves a
        // gap and the next insert lands in the wrong place. Folders and requests
        // share one sequence, so this is dense across both.
        #expect(root.map(\.sortOrder) == [0, 1, 2])

        #expect(s.names(try s.children(ofFolder: folder.id, inWorkspace: workspace)) == ["B"])
    }

    @Test("Moving a request back out to the workspace root clears its folder")
    func reparentsToRoot() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let folder = try s.library.createFolder(name: "Folder", in: .workspaceRoot(workspace))
        let request = try s.library.createRequest(name: "R", in: .folder(folder.id))

        try s.library.move(nodeID: request.id, to: .workspaceRoot(workspace), at: 0)

        let root = try s.library.tree(forWorkspace: workspace)
        // The drop index is honored literally: a request dropped above a folder
        // stays above it. Folders carry no implicit display priority.
        #expect(s.names(root) == ["R", "Folder"])
        #expect(try s.children(ofFolder: folder.id, inWorkspace: workspace).isEmpty)
    }

    @Test("Nesting a folder inside another folder works")
    func reparentsFolder() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let outer = try s.library.createFolder(name: "Outer", in: .workspaceRoot(workspace))
        let mover = try s.library.createFolder(name: "Mover", in: .workspaceRoot(workspace))

        try s.library.move(nodeID: mover.id, to: .folder(outer.id))

        #expect(s.names(try s.library.tree(forWorkspace: workspace)) == ["Outer"])
        #expect(s.names(try s.children(ofFolder: outer.id, inWorkspace: workspace)) == ["Mover"])
    }

    @Test("A folder cannot be moved into itself")
    func rejectsSelfMove() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let folder = try s.library.createFolder(name: "F", in: .workspaceRoot(workspace))

        #expect(throws: LibraryRepository.RepositoryError.self) {
            try s.library.move(nodeID: folder.id, to: .folder(folder.id))
        }
    }

    @Test("A folder cannot be moved into its own descendant")
    func rejectsDescendantMove() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let outer = try s.library.createFolder(name: "Outer", in: .workspaceRoot(workspace))
        let inner = try s.library.createFolder(name: "Inner", in: .folder(outer.id))
        let deepest = try s.library.createFolder(name: "Deepest", in: .folder(inner.id))

        // Without this guard the subtree detaches from the workspace entirely
        // and becomes unreachable — invisible data loss.
        #expect(throws: LibraryRepository.RepositoryError.self) {
            try s.library.move(nodeID: outer.id, to: .folder(deepest.id))
        }

        #expect(s.names(try s.library.tree(forWorkspace: workspace)) == ["Outer"])
    }

    @Test("Deleting from the middle renumbers the survivors")
    func deleteRenumbers() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        var ids: [UUID] = []
        for name in ["A", "B", "C"] {
            ids.append(try s.library.createRequest(name: name, in: .workspaceRoot(workspace)).id)
        }

        try s.library.deleteRequest(id: ids[1])

        let tree = try s.library.tree(forWorkspace: workspace)
        #expect(s.names(tree) == ["A", "C"])
        #expect(tree.map(\.sortOrder) == [0, 1])
    }

    @Test("An out-of-range index clamps instead of throwing")
    func clampsIndex() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        var ids: [UUID] = []
        for name in ["A", "B"] {
            ids.append(try s.library.createRequest(name: name, in: .workspaceRoot(workspace)).id)
        }

        try s.library.move(nodeID: ids[0], to: .workspaceRoot(workspace), at: 99)
        #expect(s.names(try s.library.tree(forWorkspace: workspace)) == ["B", "A"])

        try s.library.move(nodeID: ids[0], to: .workspaceRoot(workspace), at: -5)
        #expect(s.names(try s.library.tree(forWorkspace: workspace)) == ["A", "B"])
    }
}
