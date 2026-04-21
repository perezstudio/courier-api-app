import Foundation
import Observation
import os

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
        SidebarLog.drag.debug("DragState.begin id=\(id, privacy: .public) kind=\(String(describing: kind), privacy: .public) folderWasExpanded=\(folderWasExpanded)")
        self.draggedId = id
        self.draggedKind = kind
        self.folderWasExpanded = folderWasExpanded
    }

    func end() {
        SidebarLog.drag.debug("DragState.end (was dragging \(self.draggedId?.uuidString ?? "nil", privacy: .public))")
        draggedId = nil
        draggedKind = nil
        folderWasExpanded = false
    }
}
