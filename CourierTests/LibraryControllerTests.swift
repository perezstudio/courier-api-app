import Foundation
import Testing

@testable import Courier

/// The cross-window shared-state design.
///
/// Every request tab is a full window with its own sidebar, so anything that
/// should look identical across tabs has to live in `LibraryController` and fan
/// out to all of them. REQUIREMENTS.md §11 names this the top risk of using
/// native window tabs, so it is tested rather than eyeballed — each observer
/// here stands in for one window's sidebar.
@MainActor
@Suite("Shared library state")
struct LibraryControllerTests {

    private func makeController() throws -> LibraryController {
        let stack = try CoreDataStack(location: .inMemory)
        return LibraryController(stack: stack, secretStore: InMemorySecretStore())
    }

    @Test("First launch creates a default workspace")
    func createsDefaultWorkspace() throws {
        let controller = try makeController()
        controller.load()

        #expect(controller.workspaces.count == 1)
        #expect(controller.activeWorkspace?.name == "My Workspace")
    }

    @Test("Loading twice does not create a second default workspace")
    func loadIsIdempotent() throws {
        let controller = try makeController()
        controller.load()
        controller.load()

        #expect(controller.workspaces.count == 1)
    }

    @Test("Every observer is notified — one per window")
    func allObserversNotified() throws {
        let controller = try makeController()
        controller.load()

        var first = 0
        var second = 0
        var third = 0
        let tokens = [
            controller.observe { first += 1 },
            controller.observe { second += 1 },
            controller.observe { third += 1 },
        ]

        controller.createRequest(named: "A")

        // If only the acting window refreshed, the other tabs would show a
        // stale tree — the exact failure this design exists to prevent.
        #expect(first == 1)
        #expect(second == 1)
        #expect(third == 1)
        #expect(tokens.count == 3)
    }

    @Test("Request count refreshes after a mutation")
    func requestCountRefreshes() throws {
        let controller = try makeController()
        controller.load()
        #expect(controller.activeWorkspace?.requestCount == 0)

        controller.createRequest(named: "A")
        controller.createRequest(named: "B")

        // Regression: reloadTree() once refreshed only `tree`, leaving the
        // cached workspace snapshot reporting "0 requests" in every sidebar.
        #expect(controller.activeWorkspace?.requestCount == 2)
    }

    @Test("A cancelled observer stops receiving notifications")
    func cancelledObserverStops() throws {
        let controller = try makeController()
        controller.load()

        var live = 0
        var cancelled = 0
        let liveToken = controller.observe { live += 1 }
        let cancelledToken = controller.observe { cancelled += 1 }

        cancelledToken.cancelNow()
        controller.createRequest(named: "A")

        #expect(live == 1)
        #expect(cancelled == 0)
        liveToken.cancelNow()
    }

    @Test("Filter text changes notify every window")
    func filterNotifies() throws {
        let controller = try makeController()
        controller.load()

        var notifications = 0
        let token = controller.observe { notifications += 1 }

        controller.filterText = "user"
        #expect(notifications == 1)

        // Setting the same value again shouldn't churn every sidebar.
        controller.filterText = "user"
        #expect(notifications == 1)

        token.cancelNow()
    }

    @Test("Expansion state is shared and persisted")
    func expansionShared() throws {
        let controller = try makeController()
        controller.load()
        let folder = try #require(controller.createFolder(named: "Users"))

        var notifications = 0
        let token = controller.observe { notifications += 1 }

        controller.setExpanded(true, forFolder: folder.id)
        #expect(controller.isExpanded(folder.id))
        #expect(notifications == 1)

        // Re-reading from the store proves it persisted, not just cached —
        // expansion has to survive relaunch as well as reach sibling tabs.
        controller.reloadTree()
        controller.loadExpansionState()
        #expect(controller.isExpanded(folder.id))

        controller.setExpanded(false, forFolder: folder.id)
        #expect(!controller.isExpanded(folder.id))

        token.cancelNow()
    }

    @Test("Setting the same expansion value twice notifies once")
    func expansionIsIdempotent() throws {
        let controller = try makeController()
        controller.load()
        let folder = try #require(controller.createFolder(named: "Users"))

        var notifications = 0
        let token = controller.observe { notifications += 1 }

        controller.setExpanded(true, forFolder: folder.id)
        controller.setExpanded(true, forFolder: folder.id)
        #expect(notifications == 1)

        token.cancelNow()
    }

    @Test("A request can be found anywhere in the tree")
    func findsNestedRequest() throws {
        let controller = try makeController()
        controller.load()
        let workspace = try #require(controller.activeWorkspaceID)

        let folder = try controller.library.createFolder(
            name: "Users", in: .workspaceRoot(workspace)
        )
        let nested = try controller.library.createRequest(
            name: "Get User", in: .folder(folder.id)
        )
        controller.reloadTree()

        #expect(controller.requestSummary(for: nested.id)?.name == "Get User")
    }

    @Test("Collection path drives the window subtitle")
    func buildsPath() throws {
        let controller = try makeController()
        controller.load()
        let workspace = try #require(controller.activeWorkspaceID)

        let outer = try controller.library.createFolder(
            name: "API", in: .workspaceRoot(workspace)
        )
        let inner = try controller.library.createFolder(name: "Users", in: .folder(outer.id))
        let nested = try controller.library.createRequest(
            name: "Get User", in: .folder(inner.id)
        )
        let root = try controller.library.createRequest(
            name: "Health", in: .workspaceRoot(workspace)
        )
        controller.reloadTree()

        #expect(controller.path(toRequest: nested.id) == "My Workspace › API › Users")
        #expect(controller.path(toRequest: root.id) == "My Workspace")
    }
}
