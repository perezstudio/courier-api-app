import AppKit

/// Pure identifier-list arithmetic behind `NSToolbar.applyIdentifiers(_:)`,
/// separated from the toolbar so the diffing can be tested without a window.
nonisolated enum ToolbarLayout {

    /// Longest common prefix and suffix (non-overlapping) between the current
    /// and desired identifier lists. Everything between them is the window that
    /// actually has to be replaced.
    static func diffWindow(
        current: [NSToolbarItem.Identifier],
        desired: [NSToolbarItem.Identifier]
    ) -> (prefix: Int, suffix: Int) {
        var prefix = 0
        while prefix < desired.count, prefix < current.count,
              desired[prefix] == current[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < desired.count - prefix, suffix < current.count - prefix,
              desired[desired.count - 1 - suffix] == current[current.count - 1 - suffix] {
            suffix += 1
        }
        return (prefix, suffix)
    }
}

extension NSToolbar {

    /// Re-syncs the toolbar to `desired`, replacing only the changed window
    /// between the common prefix and suffix.
    ///
    /// `NSToolbar` animates every insert and remove on its own, which is what
    /// makes the results items slide in and out when the pane is toggled — no
    /// hand-rolled fading is involved, and none is possible for the status chip
    /// or the section group anyway, since both are system-drawn with no view to
    /// animate.
    ///
    /// The diff is what makes that animation read correctly. Removing and
    /// re-inserting every item animates *all* of them at once, so the untouched
    /// sidebar and settings items flash on each toggle. Worse, the full
    /// teardown took the toolbar's material with it and left the response body
    /// showing through the toolbar.
    func applyIdentifiers(_ desired: [NSToolbarItem.Identifier]) {
        let current = items.map(\.itemIdentifier)
        guard desired != current else { return }

        let (prefix, suffix) = ToolbarLayout.diffWindow(current: current, desired: desired)
        for index in stride(from: current.count - suffix - 1, through: prefix, by: -1) {
            removeItem(at: index)
        }
        for (offset, identifier) in desired[prefix..<(desired.count - suffix)].enumerated() {
            insertItem(withItemIdentifier: identifier, at: prefix + offset)
        }
    }
}
