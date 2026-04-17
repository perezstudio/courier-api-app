import SwiftUI
import SwiftData

/// Admiral-style pill tab representing the active workspace on its own page.
/// Styled to match Mjolnir's `TabPillView`: 28pt tall, 6pt corner radius,
/// primary-opacity-0.1 selected background.
///
/// Interactive: context menu + menu button for rename / icon / delete.
struct WorkspaceTab: View {
    @Bindable var workspace: Workspace
    var onRename: (String) -> Void
    var onSetIcon: (String) -> Void
    var onDelete: () -> Void

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""

    /// Curated list of SF Symbols for the workspace icon picker.
    private let iconChoices: [String] = [
        "folder.fill",
        "tray.fill",
        "star.fill",
        "bolt.fill",
        "globe",
        "hammer.fill",
        "book.fill",
        "briefcase.fill",
        "paperplane.fill",
        "server.rack",
        "cloud.fill",
        "lock.fill",
    ]

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: workspace.iconSymbolName)
                .font(.system(size: 10))
                .foregroundStyle(.primary)

            Text(workspace.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            if isHovered {
                Menu {
                    menuContents
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.1))
        }
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered ? 0.05 : 0))
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            menuContents
        }
        .alert("Rename Workspace", isPresented: $isRenaming) {
            TextField("Workspace name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                onRename(renameText)
            }
        }
    }

    @ViewBuilder
    private var menuContents: some View {
        Button("Rename…") {
            renameText = workspace.name
            isRenaming = true
        }
        Menu("Icon") {
            ForEach(iconChoices, id: \.self) { symbol in
                Button {
                    onSetIcon(symbol)
                } label: {
                    Label(symbol, systemImage: symbol)
                }
            }
        }
        Divider()
        Button("Delete Workspace", role: .destructive) {
            onDelete()
        }
    }
}
