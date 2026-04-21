import SwiftUI
import UniformTypeIdentifiers
import os

/// Drop delegate for a single sidebar item row (folder or request). Receives
/// drags from other rows and performs a live reflow: as soon as the drag
/// enters, the dragged item is moved to this row's current position in the
/// model, animated with a spring so neighbors slide out of the way.
struct ItemDropDelegate: DropDelegate {
    let targetId: UUID
    let dragState: SidebarDragState
    /// Called to reorder: move `draggedId` to immediately before `targetId`.
    /// Works across containers too — the view model resolves the target's
    /// container and re-parents the dragged item automatically.
    let moveBefore: (UUID, UUID) -> Void
    /// Called on `performDrop` to finalise and clear drag state.
    let onDropFinished: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        SidebarLog.drag.debug("ItemDrop enter target=\(targetId, privacy: .public) dragged=\(dragState.draggedId?.uuidString ?? "nil", privacy: .public)")
        guard let draggedId = dragState.draggedId, draggedId != targetId else {
            SidebarLog.drag.debug("  skip — same id or no dragged")
            return
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            moveBefore(draggedId, targetId)
        }
    }

    func dropExited(info: DropInfo) {
        SidebarLog.drag.debug("ItemDrop exit target=\(targetId, privacy: .public)")
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        SidebarLog.drag.debug("ItemDrop performDrop target=\(targetId, privacy: .public) dragged=\(dragState.draggedId?.uuidString ?? "nil", privacy: .public)")
        onDropFinished()
        return true
    }
}
