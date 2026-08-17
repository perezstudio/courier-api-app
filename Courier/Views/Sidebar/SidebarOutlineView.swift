import AppKit

@MainActor
protocol SidebarOutlineViewDelegate: AnyObject {
    /// Command-click: open in a new tab rather than changing selection.
    func outlineView(_ outlineView: SidebarOutlineView, didCommandClickRow row: Int)
    /// Right-click or Control-click. `row` is -1 for empty space.
    func outlineView(_ outlineView: SidebarOutlineView, menuForRow row: Int) -> NSMenu?
    /// Delete or forward-delete pressed with a non-empty selection.
    func outlineViewDidPressDelete(_ outlineView: SidebarOutlineView)
}

/// Source-list outline view with two interaction rules AppKit doesn't provide.
final class SidebarOutlineView: NSOutlineView {

    weak var interactionDelegate: SidebarOutlineViewDelegate?

    /// Command-click normally *toggles* selection in a table view. Courier uses
    /// it to open a request in a new tab, matching Finder and Safari
    /// (REQUIREMENTS.md §7.2), so it has to be intercepted before AppKit's own
    /// selection handling.
    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else {
            super.mouseDown(with: event)
            return
        }
        interactionDelegate?.outlineView(self, didCommandClickRow: row)
    }

    /// `NSOutlineView` does not map Delete to anything, but removing the
    /// selection with the Delete key is standard macOS behavior everywhere else
    /// — Finder, Mail, Xcode's navigator — so users reach for it.
    override func keyDown(with event: NSEvent) {
        let deleteKey = 51
        let forwardDeleteKey = 117

        if Int(event.keyCode) == deleteKey || Int(event.keyCode) == forwardDeleteKey,
           !selectedRowIndexes.isEmpty {
            interactionDelegate?.outlineViewDidPressDelete(self)
            return
        }
        super.keyDown(with: event)
    }

    /// Right-clicking a row selects it first, so the menu acts on what the user
    /// pointed at rather than on whatever happened to be selected.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)

        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return interactionDelegate?.outlineView(self, menuForRow: row)
    }
}
