import SwiftUI
import UniformTypeIdentifiers
import os

struct FolderRow: View {
    @Bindable var folder: Folder
    @Bindable var dragState: SidebarDragState
    @Binding var selectedRequestId: UUID?
    let indentLevel: Int
    var onSelectRequest: (APIRequest) -> Void
    var onCreateRequest: (String, Folder) -> Void
    var onDeleteFolder: (Folder) -> Void
    var onDeleteRequest: (APIRequest) -> Void
    var onMoveItem: (UUID, UUID) -> Void
    var onMoveIntoFolder: (UUID, Folder) -> Void

    @State private var isHovered = false
    @State private var isCreatingRequest = false
    @State private var newRequestName = ""
    /// True between this row starting a drag and the drag ending. Lets us
    /// restore this folder's expansion state even if the drop lands on a
    /// different row (which is the common case).
    @State private var startedDragHere = false
    @State private var expansionBeforeDrag = true

    private var children: [SidebarItem] { folder.children }
    private var isBeingDragged: Bool { dragState.draggedId == folder.id }

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
            .opacity(isBeingDragged ? 0.4 : 1)
            .scaleEffect(isBeingDragged ? 0.97 : 1)
            .onDrag {
                SidebarLog.drag.debug("onDrag folder=\(folder.name, privacy: .public) id=\(folder.id, privacy: .public)")
                expansionBeforeDrag = folder.isExpanded
                startedDragHere = true
                dragState.begin(id: folder.id, kind: .folder, folderWasExpanded: folder.isExpanded)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    folder.isExpanded = false
                }
                return NSItemProvider(object: folder.id.uuidString as NSString)
            }
            .onDrop(
                of: [.text],
                delegate: ItemDropDelegate(
                    targetId: folder.id,
                    dragState: dragState,
                    moveBefore: onMoveItem,
                    onDropFinished: { dragState.end() }
                )
            )
            // Dwell-to-expand strip: when this folder is collapsed, an overlay
            // on the header detects a hovering drag and auto-expands after 400ms.
            .overlay {
                if !folder.isExpanded && !isBeingDragged {
                    Color.clear
                        .contentShape(Rectangle())
                        .onDrop(
                            of: [.text],
                            delegate: FolderHeaderDropDelegate(
                                folder: folder,
                                dragState: dragState,
                                appendIntoFolder: { id in onMoveIntoFolder(id, folder) },
                                onDropFinished: { dragState.end() }
                            )
                        )
                        .allowsHitTesting(dragState.isActive)
                }
            }
            .onChange(of: dragState.isActive) { _, active in
                // Drag ended: restore this folder's expansion if we started the drag.
                if !active && startedDragHere {
                    SidebarLog.drag.debug("restore expansion folder=\(folder.name, privacy: .public) wasExpanded=\(expansionBeforeDrag)")
                    startedDragHere = false
                    if expansionBeforeDrag {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            folder.isExpanded = true
                        }
                    }
                }
            }

            // Children (unified folders + requests)
            if folder.isExpanded {
                ForEach(children) { item in
                    SidebarItemRow(
                        item: item,
                        dragState: dragState,
                        selectedRequestId: $selectedRequestId,
                        indentLevel: indentLevel + 1,
                        onSelectRequest: onSelectRequest,
                        onCreateRequest: onCreateRequest,
                        onDeleteFolder: onDeleteFolder,
                        onDeleteRequest: onDeleteRequest,
                        onMoveItem: onMoveItem,
                        onMoveIntoFolder: onMoveIntoFolder
                    )
                }

                // Tail zone inside expanded folder: drop here to append to this folder.
                if dragState.isActive {
                    Color.clear
                        .frame(height: 12)
                        .contentShape(Rectangle())
                        .onDrop(
                            of: [.text],
                            delegate: ContainerDropDelegate(
                                dragState: dragState,
                                appendToContainer: { id in onMoveIntoFolder(id, folder) },
                                onDropFinished: { dragState.end() }
                            )
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
