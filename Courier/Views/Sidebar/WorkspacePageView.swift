import SwiftUI
import UniformTypeIdentifiers

/// A single workspace page inside the sidebar's horizontal paging ScrollView.
/// Contains the Admiral-style workspace tab on top and a custom for-each
/// over the workspace's folders (recursively rendering requests).
struct WorkspacePageView: View {
    @Bindable var workspace: Workspace
    @Bindable var dragState: SidebarDragState
    @Binding var selectedRequestId: UUID?
    var onSelectRequest: (APIRequest) -> Void
    var onCreateRequest: (String, Folder) -> Void
    var onDeleteFolder: (Folder) -> Void
    var onDeleteRequest: (APIRequest) -> Void
    var onRenameWorkspace: (String) -> Void
    var onSetWorkspaceIcon: (String) -> Void
    var onDeleteWorkspace: () -> Void
    var onMoveItem: (UUID, UUID) -> Void
    var onMoveToRoot: (UUID) -> Void
    var onMoveIntoFolder: (UUID, Folder) -> Void

    private var rootItems: [SidebarItem] { workspace.rootItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceTab(
                workspace: workspace,
                onRename: onRenameWorkspace,
                onSetIcon: onSetWorkspaceIcon,
                onDelete: onDeleteWorkspace
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rootItems) { item in
                        SidebarItemRow(
                            item: item,
                            dragState: dragState,
                            selectedRequestId: $selectedRequestId,
                            indentLevel: 0,
                            onSelectRequest: onSelectRequest,
                            onCreateRequest: onCreateRequest,
                            onDeleteFolder: onDeleteFolder,
                            onDeleteRequest: onDeleteRequest,
                            onMoveItem: onMoveItem,
                            onMoveIntoFolder: onMoveIntoFolder
                        )
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // Fallback drop zone: any drop in the scroll area below the last
            // row falls through to this background and appends at workspace root.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [.text],
                        delegate: ContainerDropDelegate(
                            dragState: dragState,
                            appendToContainer: onMoveToRoot,
                            onDropFinished: { dragState.end() }
                        )
                    )
            }
        }
    }
}
