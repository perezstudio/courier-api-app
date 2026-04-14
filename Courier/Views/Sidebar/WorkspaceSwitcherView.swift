import SwiftUI

struct WorkspaceSwitcherView: View {
    let workspaces: [Workspace]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                    workspacePage(workspace, index: index)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: Binding(
            get: { workspaces.indices.contains(selectedIndex) ? workspaces[selectedIndex].id : nil },
            set: { newId in
                if let id = newId, let index = workspaces.firstIndex(where: { $0.id == id }) {
                    selectedIndex = index
                }
            }
        ))
        .frame(height: 44)
    }

    private func workspacePage(_ workspace: Workspace, index: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(workspace.folders.flatMap(\.requests).count) requests")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Page indicator dots
            if workspaces.count > 1 {
                HStack(spacing: 4) {
                    ForEach(workspaces.indices, id: \.self) { i in
                        Circle()
                            .fill(i == selectedIndex ? Color.primary : Color.primary.opacity(0.2))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}
