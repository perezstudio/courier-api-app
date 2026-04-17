import SwiftUI
import UniformTypeIdentifiers

/// Drop delegate for a single sidebar item row (folder or request). Receives
/// drags from other rows and performs a live reflow: as soon as the drag
/// enters, the dragged item is moved to this row's current position in the
/// model, animated with a spring so neighbors slide out of the way.
struct ItemDropDelegate: DropDelegate {
    let targetId: UUID
    let dragState: SidebarDragState
    /// Called to reorder: move `draggedId` to immediately before `targetId`.
    let moveBefore: (UUID, UUID) -> Void
    /// Called on `performDrop` to finalise and clear drag state.
    let onDropFinished: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        guard let draggedId = dragState.draggedId, draggedId != targetId else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            moveBefore(draggedId, targetId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onDropFinished()
        return true
    }

    func dropExited(info: DropInfo) {
        // no-op; we let the next entered event reflow further.
    }
}
