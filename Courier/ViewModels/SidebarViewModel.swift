import Foundation
import SwiftData
import SwiftUI

@Observable
final class SidebarViewModel {
    var workspaces: [Workspace] = []
    /// ID-based selection for use with `.scrollPosition(id:)` in the paging sidebar.
    /// Source of truth; `selectedWorkspaceIndex` is derived.
    var selectedWorkspaceId: UUID?
    var selectedRequestId: UUID?

    private var modelContext: ModelContext

    var selectedWorkspaceIndex: Int {
        get {
            guard let id = selectedWorkspaceId,
                  let idx = workspaces.firstIndex(where: { $0.id == id }) else { return 0 }
            return idx
        }
        set {
            guard workspaces.indices.contains(newValue) else { return }
            selectedWorkspaceId = workspaces[newValue].id
        }
    }

    var currentWorkspace: Workspace? {
        if let id = selectedWorkspaceId, let ws = workspaces.first(where: { $0.id == id }) {
            return ws
        }
        return workspaces.first
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchWorkspaces()
    }

    func fetchWorkspaces() {
        let descriptor = FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder)])
        workspaces = (try? modelContext.fetch(descriptor)) ?? []
        if selectedWorkspaceId == nil || !workspaces.contains(where: { $0.id == selectedWorkspaceId }) {
            selectedWorkspaceId = workspaces.first?.id
        }
    }

    // MARK: - Workspace CRUD

    func createWorkspace(name: String) {
        let workspace = Workspace(name: name, sortOrder: workspaces.count)
        modelContext.insert(workspace)
        try? modelContext.save()
        fetchWorkspaces()
        selectedWorkspaceId = workspace.id
    }

    func renameWorkspace(_ workspace: Workspace, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        workspace.name = trimmed
        try? modelContext.save()
    }

    func setWorkspaceIcon(_ workspace: Workspace, to symbolName: String) {
        workspace.iconSymbolName = symbolName
        try? modelContext.save()
    }

    func deleteWorkspace(_ workspace: Workspace) {
        let wasSelected = (selectedWorkspaceId == workspace.id)
        modelContext.delete(workspace)
        try? modelContext.save()
        fetchWorkspaces()
        if wasSelected {
            selectedWorkspaceId = workspaces.first?.id
        }
    }

    // MARK: - Folder / Request CRUD

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

    // MARK: - Reorder (v1: same-parent only)

    /// Reorder `draggedId` so it lands immediately before `targetId` within the same parent
    /// (same workspace + same parentFolder). Ignores the move if they don't share a parent.
    func moveFolder(_ draggedId: UUID, before targetId: UUID) {
        guard draggedId != targetId else { return }
        guard let dragged = findFolder(id: draggedId),
              let target = findFolder(id: targetId) else { return }
        guard dragged.workspace?.id == target.workspace?.id,
              dragged.parentFolder?.id == target.parentFolder?.id else { return }

        let siblings = siblingFolders(of: dragged)
        var ordered = siblings.filter { $0.id != draggedId }
        if let targetIdx = ordered.firstIndex(where: { $0.id == targetId }) {
            ordered.insert(dragged, at: targetIdx)
        } else {
            ordered.append(dragged)
        }
        for (idx, folder) in ordered.enumerated() {
            folder.sortOrder = idx
        }
        try? modelContext.save()
    }

    /// Reorder `draggedId` so it lands immediately before `targetId` within the same folder.
    func moveRequest(_ draggedId: UUID, before targetId: UUID) {
        guard draggedId != targetId else { return }
        guard let dragged = findRequest(id: draggedId),
              let target = findRequest(id: targetId) else { return }
        guard let parent = dragged.folder, parent.id == target.folder?.id else { return }

        var ordered = parent.requests.sorted { $0.sortOrder < $1.sortOrder }.filter { $0.id != draggedId }
        if let targetIdx = ordered.firstIndex(where: { $0.id == targetId }) {
            ordered.insert(dragged, at: targetIdx)
        } else {
            ordered.append(dragged)
        }
        for (idx, request) in ordered.enumerated() {
            request.sortOrder = idx
        }
        try? modelContext.save()
    }

    // MARK: - Lookup helpers

    private func findFolder(id: UUID) -> Folder? {
        for workspace in workspaces {
            if let match = searchFolder(id: id, in: workspace.folders) { return match }
        }
        return nil
    }

    private func searchFolder(id: UUID, in folders: [Folder]) -> Folder? {
        for folder in folders {
            if folder.id == id { return folder }
            if let nested = searchFolder(id: id, in: folder.subFolders) { return nested }
        }
        return nil
    }

    private func findRequest(id: UUID) -> APIRequest? {
        for workspace in workspaces {
            if let match = searchRequest(id: id, in: workspace.folders) { return match }
        }
        return nil
    }

    private func searchRequest(id: UUID, in folders: [Folder]) -> APIRequest? {
        for folder in folders {
            if let match = folder.requests.first(where: { $0.id == id }) { return match }
            if let nested = searchRequest(id: id, in: folder.subFolders) { return nested }
        }
        return nil
    }

    private func siblingFolders(of folder: Folder) -> [Folder] {
        let siblings: [Folder]
        if let parent = folder.parentFolder {
            siblings = parent.subFolders
        } else if let workspace = folder.workspace {
            siblings = workspace.folders.filter { $0.parentFolder == nil }
        } else {
            siblings = []
        }
        return siblings.sorted { $0.sortOrder < $1.sortOrder }
    }
}
