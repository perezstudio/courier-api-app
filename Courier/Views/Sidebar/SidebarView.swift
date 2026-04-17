import SwiftUI
import SwiftData

struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    var onSelectRequest: (APIRequest) -> Void

    @State private var isCreatingWorkspace = false
    @State private var newWorkspaceName = ""
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar — reserves space for traffic lights.
            sidebarToolbar

            // Body
            if viewModel.workspaces.isEmpty {
                emptyState
            } else {
                workspacePager
            }

            // Footer: + folder (left) | dots (center) | + workspace (right)
            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $isCreatingWorkspace) {
            newWorkspaceSheet
        }
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let workspace = viewModel.currentWorkspace {
                    viewModel.createFolder(name: name, in: workspace)
                }
            }
        }
    }

    // MARK: - Top toolbar (traffic-light clearance)

    private var sidebarToolbar: some View {
        HStack { Spacer() }
            .frame(height: ContentCardMetrics.tabBarHeight)
            .padding(.top, 6)
    }

    // MARK: - Empty state

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Horizontal paging body

    private var workspacePager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(viewModel.workspaces) { workspace in
                    WorkspacePageView(
                        workspace: workspace,
                        selectedRequestId: $viewModel.selectedRequestId,
                        onSelectRequest: onSelectRequest,
                        onCreateRequest: { name, folder in
                            viewModel.createRequest(name: name, in: folder)
                        },
                        onDeleteFolder: { folder in
                            viewModel.deleteFolder(folder)
                        },
                        onDeleteRequest: { request in
                            viewModel.deleteRequest(request)
                        },
                        onRenameWorkspace: { newName in
                            viewModel.renameWorkspace(workspace, to: newName)
                        },
                        onSetWorkspaceIcon: { symbol in
                            viewModel.setWorkspaceIcon(workspace, to: symbol)
                        },
                        onDeleteWorkspace: {
                            viewModel.deleteWorkspace(workspace)
                        },
                        onMoveFolder: { dragged, target in
                            viewModel.moveFolder(dragged, before: target)
                        },
                        onMoveRequest: { dragged, target in
                            viewModel.moveRequest(dragged, before: target)
                        }
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(workspace.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $viewModel.selectedWorkspaceId)
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        HStack {
            Button {
                isCreatingFolder = true
                newFolderName = ""
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: HoverButtonSize.small.symbolSize))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.courierHover(size: .small))
            .disabled(viewModel.currentWorkspace == nil)

            Spacer()

            WorkspaceIndicatorDots(
                workspaces: viewModel.workspaces,
                selectedId: $viewModel.selectedWorkspaceId
            )

            Spacer()

            Button {
                isCreatingWorkspace = true
                newWorkspaceName = ""
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: HoverButtonSize.small.symbolSize))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.courierHover(size: .small))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
