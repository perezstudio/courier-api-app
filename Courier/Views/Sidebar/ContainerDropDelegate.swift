import SwiftUI
import UniformTypeIdentifiers
import os

/// Drop delegate for a container's empty/tail zone. Used at the bottom of a
/// workspace's root list and inside expanded-but-empty folders. Drops here
/// append the dragged item to the end of that container's children.
struct ContainerDropDelegate: DropDelegate {
    let dragState: SidebarDragState
    /// Move the dragged id to the tail of this container.
    let appendToContainer: (UUID) -> Void
    let onDropFinished: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        SidebarLog.drag.debug("ContainerDrop enter dragged=\(dragState.draggedId?.uuidString ?? "nil", privacy: .public)")
        guard let draggedId = dragState.draggedId else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            appendToContainer(draggedId)
        }
    }

    func dropExited(info: DropInfo) {
        SidebarLog.drag.debug("ContainerDrop exit")
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        SidebarLog.drag.debug("ContainerDrop performDrop dragged=\(dragState.draggedId?.uuidString ?? "nil", privacy: .public)")
        onDropFinished()
        return true
    }
}

/// Drop delegate attached to a folder *header* row. While the dragged item
/// dwells over the header for `dwellSeconds`, the folder auto-expands so
/// the user can drill in. On drop, the item is appended inside the folder.
final class FolderHeaderDropDelegate: DropDelegate {
    let folder: Folder
    let dragState: SidebarDragState
    let appendIntoFolder: (UUID) -> Void
    let onDropFinished: () -> Void
    let dwellSeconds: TimeInterval

    private var dwellTask: Task<Void, Never>?

    init(folder: Folder,
         dragState: SidebarDragState,
         appendIntoFolder: @escaping (UUID) -> Void,
         onDropFinished: @escaping () -> Void,
         dwellSeconds: TimeInterval = 0.4) {
        self.folder = folder
        self.dragState = dragState
        self.appendIntoFolder = appendIntoFolder
        self.onDropFinished = onDropFinished
        self.dwellSeconds = dwellSeconds
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        SidebarLog.drag.debug("FolderHeader enter folder=\(self.folder.name, privacy: .public) id=\(self.folder.id, privacy: .public)")
        guard dragState.draggedId != folder.id else { return }
        // Start dwell timer to auto-expand.
        dwellTask?.cancel()
        let folderRef = folder
        let dwell = dwellSeconds
        dwellTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(dwell * 1_000_000_000))
            if Task.isCancelled { return }
            if !folderRef.isExpanded {
                SidebarLog.drag.debug("FolderHeader dwell-expand folder=\(folderRef.name, privacy: .public)")
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    folderRef.isExpanded = true
                }
            }
        }
    }

    func dropExited(info: DropInfo) {
        SidebarLog.drag.debug("FolderHeader exit folder=\(self.folder.name, privacy: .public)")
        dwellTask?.cancel()
        dwellTask = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        SidebarLog.drag.debug("FolderHeader performDrop folder=\(self.folder.name, privacy: .public) dragged=\(self.dragState.draggedId?.uuidString ?? "nil", privacy: .public)")
        dwellTask?.cancel()
        dwellTask = nil
        guard let draggedId = dragState.draggedId else {
            onDropFinished()
            return false
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            appendIntoFolder(draggedId)
        }
        onDropFinished()
        return true
    }
}
