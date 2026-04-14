import SwiftUI

struct FolderRow: View {
    @Bindable var folder: Folder
    @Binding var selectedRequestId: UUID?
    let indentLevel: Int
    var onSelectRequest: (APIRequest) -> Void
    var onCreateRequest: (String, Folder) -> Void
    var onDeleteFolder: (Folder) -> Void
    var onDeleteRequest: (APIRequest) -> Void

    @State private var isHovered = false
    @State private var isCreatingRequest = false
    @State private var newRequestName = ""

    private var sortedRequests: [APIRequest] {
        folder.requests.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedSubFolders: [Folder] {
        folder.subFolders.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Folder header
            HStack(spacing: 6) {
                Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(folder.name)
                    .font(.system(size: 12))
                    .lineLimit(1)

                Spacer()

                if isHovered {
                    Button {
                        isCreatingRequest = true
                        newRequestName = ""
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.courierHover(size: .small))
                }
            }
            .padding(.leading, CGFloat(indentLevel) * 16 + 12)
            .padding(.trailing, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(isHovered ? 0.04 : 0))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    folder.isExpanded.toggle()
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .contextMenu {
                Button("New Request") {
                    isCreatingRequest = true
                    newRequestName = ""
                }
                Divider()
                Button("Delete Folder", role: .destructive) {
                    onDeleteFolder(folder)
                }
            }

            // Children
            if folder.isExpanded {
                ForEach(sortedSubFolders) { subFolder in
                    FolderRow(
                        folder: subFolder,
                        selectedRequestId: $selectedRequestId,
                        indentLevel: indentLevel + 1,
                        onSelectRequest: onSelectRequest,
                        onCreateRequest: onCreateRequest,
                        onDeleteFolder: onDeleteFolder,
                        onDeleteRequest: onDeleteRequest
                    )
                }

                ForEach(sortedRequests) { request in
                    RequestRow(
                        request: request,
                        isSelected: selectedRequestId == request.id,
                        indentLevel: indentLevel + 1,
                        onSelect: {
                            selectedRequestId = request.id
                            onSelectRequest(request)
                        },
                        onDelete: {
                            onDeleteRequest(request)
                        }
                    )
                }
            }
        }
        .alert("New Request", isPresented: $isCreatingRequest) {
            TextField("Request name", text: $newRequestName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newRequestName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    onCreateRequest(name, folder)
                }
            }
        }
    }
}
