import SwiftUI

/// Dispatches a `SidebarItem` to the appropriate concrete row.
struct SidebarItemRow: View {
    let item: SidebarItem
    @Bindable var dragState: SidebarDragState
    @Binding var selectedRequestId: UUID?
    let indentLevel: Int
    var onSelectRequest: (APIRequest) -> Void
    var onCreateRequest: (String, Folder) -> Void
    var onDeleteFolder: (Folder) -> Void
    var onDeleteRequest: (APIRequest) -> Void
    var onMoveItem: (UUID, UUID) -> Void
    var onMoveIntoFolder: (UUID, Folder) -> Void

    var body: some View {
        switch item {
        case .folder(let folder):
            FolderRow(
                folder: folder,
                dragState: dragState,
                selectedRequestId: $selectedRequestId,
                indentLevel: indentLevel,
                onSelectRequest: onSelectRequest,
                onCreateRequest: onCreateRequest,
                onDeleteFolder: onDeleteFolder,
                onDeleteRequest: onDeleteRequest,
                onMoveItem: onMoveItem,
                onMoveIntoFolder: onMoveIntoFolder
            )
        case .request(let request):
            RequestRow(
                request: request,
                dragState: dragState,
                isSelected: selectedRequestId == request.id,
                indentLevel: indentLevel,
                onSelect: {
                    selectedRequestId = request.id
                    onSelectRequest(request)
                },
                onDelete: { onDeleteRequest(request) },
                onMoveItem: onMoveItem
            )
        }
    }
}
