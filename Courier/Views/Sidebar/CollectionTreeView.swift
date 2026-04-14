import SwiftUI

struct CollectionTreeView: View {
    let workspace: Workspace
    @Binding var selectedRequestId: UUID?
    var onSelectRequest: (APIRequest) -> Void
    var onCreateFolder: (String) -> Void
    var onCreateRequest: (String, Folder) -> Void
    var onDeleteFolder: (Folder) -> Void
    var onDeleteRequest: (APIRequest) -> Void

    @State private var newFolderName = ""
    @State private var isCreatingFolder = false

    private var sortedFolders: [Folder] {
        workspace.folders
            .filter { $0.parentFolder == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedFolders) { folder in
                    FolderRow(
                        folder: folder,
                        selectedRequestId: $selectedRequestId,
                        indentLevel: 0,
                        onSelectRequest: onSelectRequest,
                        onCreateRequest: onCreateRequest,
                        onDeleteFolder: onDeleteFolder,
                        onDeleteRequest: onDeleteRequest
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            // Bottom toolbar
            HStack {
                Button {
                    isCreatingFolder = true
                    newFolderName = ""
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: HoverButtonSize.small.symbolSize))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.courierHover(size: .small))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                VisualEffectBackground(material: .sidebar)
            }
        }
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    onCreateFolder(name)
                }
            }
        }
    }
}
