import SwiftUI

struct RequestRow: View {
    @Bindable var request: APIRequest
    let isSelected: Bool
    let indentLevel: Int
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onMoveRequest: (UUID, UUID) -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var isRenameFocused: Bool

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
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
        }
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
        .draggable(SidebarDragPayload(kind: .request, id: request.id))
        .dropDestination(for: SidebarDragPayload.self) { payloads, _ in
            guard let payload = payloads.first, payload.kind == .request else { return false }
            onMoveRequest(payload.id, request.id)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
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
