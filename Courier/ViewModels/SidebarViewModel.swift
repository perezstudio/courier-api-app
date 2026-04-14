import Foundation
import SwiftData
import SwiftUI

@Observable
final class SidebarViewModel {
    var workspaces: [Workspace] = []
    var selectedWorkspaceIndex: Int = 0
    var selectedRequestId: UUID?

    private var modelContext: ModelContext

    var currentWorkspace: Workspace? {
        guard !workspaces.isEmpty, selectedWorkspaceIndex < workspaces.count else { return nil }
        return workspaces[selectedWorkspaceIndex]
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchWorkspaces()
    }

    func fetchWorkspaces() {
        let descriptor = FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder)])
        workspaces = (try? modelContext.fetch(descriptor)) ?? []
    }

    func createWorkspace(name: String) {
        let workspace = Workspace(name: name, sortOrder: workspaces.count)
        modelContext.insert(workspace)
        try? modelContext.save()
        fetchWorkspaces()
        selectedWorkspaceIndex = workspaces.count - 1
    }

    func createFolder(name: String, in workspace: Workspace) {
        let folder = Folder(name: name, sortOrder: workspace.folders.count)
        folder.workspace = workspace
        modelContext.insert(folder)
        try? modelContext.save()
    }

    func createRequest(name: String, method: String = "GET", in folder: Folder) {
        let request = APIRequest(name: name, method: method, sortOrder: folder.requests.count)
        request.folder = folder
        modelContext.insert(request)
        try? modelContext.save()
    }

    func deleteWorkspace(_ workspace: Workspace) {
        modelContext.delete(workspace)
        try? modelContext.save()
        fetchWorkspaces()
        if selectedWorkspaceIndex >= workspaces.count {
            selectedWorkspaceIndex = max(0, workspaces.count - 1)
        }
    }

    func deleteFolder(_ folder: Folder) {
        modelContext.delete(folder)
        try? modelContext.save()
    }

    func deleteRequest(_ request: APIRequest) {
        if selectedRequestId == request.id {
            selectedRequestId = nil
        }
        modelContext.delete(request)
        try? modelContext.save()
    }
}
