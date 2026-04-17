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
    /// Shared drag state for the sidebar.
    let dragState = SidebarDragState()

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

    // MARK: - Reorder (unified folders + requests)

    /// Container that holds sidebar items. Either a workspace (root) or a folder.
    enum ItemContainer {
        case workspace(Workspace)
        case folder(Folder)

        var id: UUID {
            switch self {
            case .workspace(let w): return w.id
            case .folder(let f): return f.id
            }
        }
    }

    /// Move a folder or request into `destination` at a specific index.
    /// Handles cross-container moves (root ↔ folder ↔ another folder) and same-container reorders.
    /// Rejects moves that would place a folder inside itself or one of its descendants.
    func moveItem(_ draggedId: UUID, into destination: ItemContainer, at insertIndex: Int) {
        // Resolve the dragged item.
        if let dragged = findFolder(id: draggedId) {
            // Prevent moving a folder into itself or any of its descendants.
            if case .folder(let destFolder) = destination {
                if destFolder.id == dragged.id || isDescendant(destFolder, of: dragged) {
                    return
                }
            }

            let originChildren = containerChildren(for: containerFor(folder: dragged))
            var destinationChildren = containerChildren(for: destination)
                .filter { $0.id != draggedId }
            let clampedIdx = max(0, min(insertIndex, destinationChildren.count))
            destinationChildren.insert(.folder(dragged), at: clampedIdx)

            // Reassign parentage.
            switch destination {
            case .workspace(let ws):
                dragged.workspace = ws
                dragged.parentFolder = nil
            case .folder(let parent):
                dragged.workspace = parent.workspace
                dragged.parentFolder = parent
            }

            renumber(children: destinationChildren)
            // If origin and destination differ, renumber the origin too.
            if originChildren.map(\.id) != destinationChildren.map(\.id) {
                renumber(children: originChildren.filter { $0.id != draggedId })
            }
            try? modelContext.save()
            return
        }

        if let dragged = findRequest(id: draggedId) {
            let originChildren = containerChildren(for: containerFor(request: dragged))
            var destinationChildren = containerChildren(for: destination)
                .filter { $0.id != draggedId }
            let clampedIdx = max(0, min(insertIndex, destinationChildren.count))
            destinationChildren.insert(.request(dragged), at: clampedIdx)

            switch destination {
            case .workspace(let ws):
                dragged.workspace = ws
                dragged.folder = nil
            case .folder(let parent):
                dragged.workspace = nil
                dragged.folder = parent
            }

            renumber(children: destinationChildren)
            if originChildren.map(\.id) != destinationChildren.map(\.id) {
                renumber(children: originChildren.filter { $0.id != draggedId })
            }
            try? modelContext.save()
            return
        }
    }

    /// Move `draggedId` to immediately before `targetId`. The target's container is resolved automatically.
    func moveItem(_ draggedId: UUID, before targetId: UUID) {
        guard let targetContainer = containerForItem(id: targetId) else { return }
        let children = containerChildren(for: targetContainer).filter { $0.id != draggedId }
        let insertIdx = children.firstIndex { $0.id == targetId } ?? children.count
        moveItem(draggedId, into: targetContainer, at: insertIdx)
    }

    /// Move `draggedId` to immediately after `targetId`.
    func moveItem(_ draggedId: UUID, after targetId: UUID) {
        guard let targetContainer = containerForItem(id: targetId) else { return }
        let children = containerChildren(for: targetContainer).filter { $0.id != draggedId }
        let insertIdx = (children.firstIndex { $0.id == targetId } ?? (children.count - 1)) + 1
        moveItem(draggedId, into: targetContainer, at: insertIdx)
    }

    /// Append `draggedId` to the end of `workspace`'s root items.
    func moveItemToWorkspaceRoot(_ draggedId: UUID, workspace: Workspace) {
        let count = workspace.rootItems.filter { $0.id != draggedId }.count
        moveItem(draggedId, into: .workspace(workspace), at: count)
    }

    /// Append `draggedId` to the end of `folder`'s children.
    func moveItemIntoFolder(_ draggedId: UUID, folder: Folder) {
        let count = folder.children.filter { $0.id != draggedId }.count
        moveItem(draggedId, into: .folder(folder), at: count)
    }

    // MARK: - Container helpers

    private func containerChildren(for container: ItemContainer) -> [SidebarItem] {
        switch container {
        case .workspace(let w): return w.rootItems
        case .folder(let f): return f.children
        }
    }

    private func containerFor(folder: Folder) -> ItemContainer {
        if let parent = folder.parentFolder { return .folder(parent) }
        if let ws = folder.workspace { return .workspace(ws) }
        return .workspace(workspaces.first!) // fallback; should not happen
    }

    private func containerFor(request: APIRequest) -> ItemContainer {
        if let parent = request.folder { return .folder(parent) }
        if let ws = request.workspace { return .workspace(ws) }
        return .workspace(workspaces.first!) // fallback
    }

    private func containerForItem(id: UUID) -> ItemContainer? {
        if let f = findFolder(id: id) { return containerFor(folder: f) }
        if let r = findRequest(id: id) { return containerFor(request: r) }
        return nil
    }

    private func renumber(children: [SidebarItem]) {
        for (idx, item) in children.enumerated() {
            switch item {
            case .folder(let f): f.sortOrder = idx
            case .request(let r): r.sortOrder = idx
            }
        }
    }

    private func isDescendant(_ candidate: Folder, of ancestor: Folder) -> Bool {
        var cursor: Folder? = candidate.parentFolder
        while let c = cursor {
            if c.id == ancestor.id { return true }
            cursor = c.parentFolder
        }
        return false
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

}
