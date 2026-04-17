import Foundation
import Observation

/// Shared, transient drag state for the sidebar. Rows read this to show
/// drag feedback (opacity/scale); drop delegates mutate it as a drag starts
/// and ends. Kept per-sidebar on the SidebarViewModel so it resets cleanly
/// when the drag completes or is cancelled.
@Observable
final class SidebarDragState {
    var draggedId: UUID?
    var draggedKind: SidebarItem.Kind?
    /// Snapshot of the dragged folder's expansion state, so we can restore it
    /// after the drop (or cancel). Only meaningful when `draggedKind == .folder`.
    var folderWasExpanded: Bool = false

    var isActive: Bool { draggedId != nil }

    func begin(id: UUID, kind: SidebarItem.Kind, folderWasExpanded: Bool = false) {
        self.draggedId = id
        self.draggedKind = kind
        self.folderWasExpanded = folderWasExpanded
    }

    func end() {
        draggedId = nil
        draggedKind = nil
        folderWasExpanded = false
    }
}
