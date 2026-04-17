import SwiftUI

/// Footer workspace indicator: one dot per workspace; the active workspace's slot
/// shows its SF Symbol instead of a dot. Tap a dot to jump to that workspace.
struct WorkspaceIndicatorDots: View {
    let workspaces: [Workspace]
    @Binding var selectedId: UUID?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(workspaces, id: \.id) { workspace in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedId = workspace.id
                    }
                } label: {
                    indicator(for: workspace)
                }
                .buttonStyle(.plain)
                .help(workspace.name)
            }
        }
    }

    @ViewBuilder
    private func indicator(for workspace: Workspace) -> some View {
        if workspace.id == selectedId {
            Image(systemName: workspace.iconSymbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 14, height: 14)
        } else {
            Circle()
                .fill(Color.primary.opacity(0.3))
                .frame(width: 5, height: 5)
                .frame(width: 14, height: 14) // match active hit area
        }
    }
}
