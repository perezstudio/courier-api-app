import SwiftUI
import SwiftData

struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    var onSelectRequest: (APIRequest) -> Void

    @State private var isCreatingWorkspace = false
    @State private var newWorkspaceName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar area - reserves space for traffic lights
            sidebarToolbar

            Divider()

            // Workspace switcher + collection tree
            if viewModel.workspaces.isEmpty {
                emptyState
            } else {
                workspaceContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { VisualEffectBackground(material: .sidebar) }
        .sheet(isPresented: $isCreatingWorkspace) {
            newWorkspaceSheet
        }
    }

    // MARK: - Toolbar

    private var sidebarToolbar: some View {
        HStack {
            Spacer()

            Button {
                isCreatingWorkspace = true
                newWorkspaceName = ""
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: HoverButtonSize.regular.symbolSize))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.courierHover())
        }
        .padding(.horizontal, 12)
        .frame(height: ContentCardMetrics.tabBarHeight)
        .padding(.top, 6) // Extra space for traffic lights
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No Workspaces")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Create Workspace") {
                isCreatingWorkspace = true
                newWorkspaceName = ""
            }
            .buttonStyle(.courierHoverText())
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Workspace Content

    private var workspaceContent: some View {
        VStack(spacing: 0) {
            // Workspace switcher
            WorkspaceSwitcherView(
                workspaces: viewModel.workspaces,
                selectedIndex: $viewModel.selectedWorkspaceIndex
            )

            Divider()

            // Collection tree
            if let workspace = viewModel.currentWorkspace {
                CollectionTreeView(
                    workspace: workspace,
                    selectedRequestId: $viewModel.selectedRequestId,
                    onSelectRequest: onSelectRequest,
                    onCreateFolder: { name in
                        viewModel.createFolder(name: name, in: workspace)
                    },
                    onCreateRequest: { name, folder in
                        viewModel.createRequest(name: name, in: folder)
                    },
                    onDeleteFolder: { folder in
                        viewModel.deleteFolder(folder)
                    },
                    onDeleteRequest: { request in
                        viewModel.deleteRequest(request)
                    }
                )
            }
        }
    }

    // MARK: - New Workspace Sheet

    private var newWorkspaceSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("New Workspace")
                .font(.headline)

            TextField("Workspace name", text: $newWorkspaceName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit {
                    createWorkspace()
                }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isCreatingWorkspace = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    createWorkspace()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }

    private func createWorkspace() {
        let name = newWorkspaceName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        viewModel.createWorkspace(name: name)
        isCreatingWorkspace = false
    }
}
