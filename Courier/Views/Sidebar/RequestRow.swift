import SwiftUI
import UniformTypeIdentifiers

struct RequestRow: View {
    @Bindable var request: APIRequest
    @Bindable var dragState: SidebarDragState
    let isSelected: Bool
    let indentLevel: Int
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onMoveItem: (UUID, UUID) -> Void

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var isRenameFocused: Bool

    private var isBeingDragged: Bool { dragState.draggedId == request.id }

    var body: some View {
        HStack(spacing: 6) {
            MethodBadge(method: request.method)

            if isRenaming {
                TextField("", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isRenameFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .onChange(of: isRenameFocused) { _, focused in
                        if !focused && isRenaming { commitRename() }
                    }
            } else {
                Text(request.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.leading, CGFloat(indentLevel) * 16 + 24)
        .padding(.trailing, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.15) :
                      Color.primary.opacity(isHovered ? 0.04 : 0))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            beginRename()
        }
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Rename") {
                beginRename()
            }
            Button("Delete Request", role: .destructive) {
                onDelete()
            }
        }
        .opacity(isBeingDragged ? 0.4 : 1)
        .scaleEffect(isBeingDragged ? 0.97 : 1)
        .onDrag {
            dragState.begin(id: request.id, kind: .request)
            return NSItemProvider(object: request.id.uuidString as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: ItemDropDelegate(
                targetId: request.id,
                dragState: dragState,
                moveBefore: onMoveItem,
                onDropFinished: { dragState.end() }
            )
        )
    }

    private func beginRename() {
        draftName = request.name
        isRenaming = true
        DispatchQueue.main.async {
            isRenameFocused = true
        }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            request.name = trimmed
        }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }
}
