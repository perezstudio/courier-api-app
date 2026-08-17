import AppKit
import Testing

@testable import Courier

/// The identifier arithmetic behind the toolbar's animated inserts and
/// removes. Exercised directly, without a window: the point of keeping
/// `ToolbarLayout` free of the live toolbar is that the replace window can be
/// pinned here rather than judged by eye.
@Suite("Toolbar layout")
struct ToolbarLayoutTests {

    private static func ids(_ names: String...) -> [NSToolbarItem.Identifier] {
        names.map(NSToolbarItem.Identifier.init(_:))
    }

    /// The case the results pane actually produces: collapsing drops a run of
    /// items from the middle and leaves both ends alone. Everything before the
    /// separator — the whole sidebar and settings region — must fall in the
    /// common prefix, or those items animate too and the toolbar flashes.
    @Test("Collapsing replaces only the results run")
    func collapseReplacesOnlyResultsRun() {
        let expanded = Self.ids(
            "toggleSidebar", "flexible", "new", "sidebarSep",
            "method", "url", "send",
            "contentSep", "status", "mode", "flexible2", "section",
            "inspector"
        )
        let collapsed = Self.ids(
            "toggleSidebar", "flexible", "new", "sidebarSep",
            "method", "url", "send",
            "flexible2",
            "inspector"
        )

        let (prefix, suffix) = ToolbarLayout.diffWindow(current: expanded, desired: collapsed)

        #expect(prefix == 7, "the sidebar and settings items must not be touched")
        // Only the toggle. The flexible space sits at a different index on
        // each side, so it falls inside the replace window rather than the
        // common suffix — harmless, since a space has nothing to animate.
        #expect(suffix == 1, "the inspector toggle must not be touched")
    }

    /// Expanding is the same edit in reverse, so the two directions stay
    /// symmetric and neither disturbs more than the results run.
    @Test("Expanding is the reverse edit")
    func expandIsReverse() {
        let collapsed = Self.ids("a", "b", "flexible", "inspector")
        let expanded = Self.ids("a", "b", "sep", "status", "flexible", "inspector")

        let (prefix, suffix) = ToolbarLayout.diffWindow(current: collapsed, desired: expanded)

        #expect(prefix == 2)
        #expect(suffix == 2)
    }

    @Test("Identical lists have nothing to replace")
    func identicalLists() {
        let list = Self.ids("a", "b", "c")
        let (prefix, suffix) = ToolbarLayout.diffWindow(current: list, desired: list)

        #expect(prefix == 3)
        #expect(suffix == 0)
        // The replace window is empty, so no item is removed or re-inserted.
        #expect(prefix + suffix == list.count)
    }

    /// The prefix and suffix must never overlap, or `applyIdentifiers` would
    /// compute a negative range and trap. A repeated identifier either side of
    /// the change is the case that provokes it.
    @Test("Prefix and suffix never overlap")
    func prefixAndSuffixDoNotOverlap() {
        let current = Self.ids("x", "x", "x", "x")
        let desired = Self.ids("x", "x")

        let (prefix, suffix) = ToolbarLayout.diffWindow(current: current, desired: desired)

        #expect(prefix + suffix <= desired.count)
        #expect(prefix + suffix <= current.count)
    }

    @Test("An append touches nothing that already exists")
    func appendOnly() {
        let current = Self.ids("a", "b")
        let desired = Self.ids("a", "b", "c")

        let (prefix, suffix) = ToolbarLayout.diffWindow(current: current, desired: desired)

        #expect(prefix == 2)
        #expect(suffix == 0)
    }

    /// A change at the head must not be absorbed into the suffix, which would
    /// leave the wrong item in place.
    @Test("A leading change is replaced from index zero")
    func leadingChange() {
        let current = Self.ids("a", "b", "c")
        let desired = Self.ids("z", "b", "c")

        let (prefix, suffix) = ToolbarLayout.diffWindow(current: current, desired: desired)

        #expect(prefix == 0)
        #expect(suffix == 2)
    }
}
