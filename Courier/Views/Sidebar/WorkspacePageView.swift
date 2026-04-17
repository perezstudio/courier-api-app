import SwiftUI

/// A single workspace page inside the sidebar's horizontal paging ScrollView.
/// Contains the Admiral-style workspace tab on top and a custom for-each
/// over the workspace's folders (recursively rendering requests).
struct WorkspacePageView: View {
    @Bindable var workspace: Workspace
    @Binding var selectedRequestId: UUID?
    var onSelectRequest: (APIRequest) -> Void
    var onCreateRequest: (String, Folder) -> Void
    var onDeleteFolder: (Folder) -> Void
    var onDeleteRequest: (APIRequest) -> Void
    var onRenameWorkspace: (String) -> Void
    var onSetWorkspaceIcon: (String) -> Void
    var onDeleteWorkspace: () -> Void
    var onMoveFolder: (UUID, UUID) -> Void
    var onMoveRequest: (UUID, UUID) -> Void

    private var sortedFolders: [Folder] {
        workspace.folders
            .filter { $0.parentFolder == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

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
                    ForEach(sortedFolders) { folder in
                        FolderRow(
                            folder: folder,
                            selectedRequestId: $selectedRequestId,
                            indentLevel: 0,
                            onSelectRequest: onSelectRequest,
                            onCreateRequest: onCreateRequest,
                            onDeleteFolder: onDeleteFolder,
                            onDeleteRequest: onDeleteRequest,
                            onMoveFolder: onMoveFolder,
                            onMoveRequest: onMoveRequest
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
