import SwiftUI

struct RequestRow: View {
    let request: APIRequest
    let isSelected: Bool
    let indentLevel: Int
    var onSelect: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

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
    }
}
