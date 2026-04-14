import SwiftUI

struct TabItemView: View {
    let tab: RequestTab
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            MethodBadge(method: tab.method)

            Text(tab.name)
                .font(.system(size: 11))
                .lineLimit(1)

            if isHovered || isActive {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            tabBackground
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
    }

    @ViewBuilder
    private var tabBackground: some View {
        if isActive {
            // Active tab: matches content card surface, connects visually
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8
            )
            .fill(Color.courierCardSurface)
        } else {
            // Inactive tab: subtle hover state in window background
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
        }
    }
}
