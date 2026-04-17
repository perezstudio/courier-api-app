import SwiftUI

struct RequestRow: View {
    let request: APIRequest
    let isSelected: Bool
    let indentLevel: Int
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onMoveRequest: (UUID, UUID) -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 6) {
            MethodBadge(method: request.method)

            Text(request.name)
                .font(.system(size: 12))
                .lineLimit(1)

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
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
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
}
