import CoreData
import Foundation

/// Workspaces and the collection tree: folders, requests, ordering, and moves.
///
/// Ordering is a plain `sortOrder: Int32`, renumbered densely within a parent on
/// every structural change (REQUIREMENTS.md §4.1). Renumbering is bounded by the
/// number of siblings and keeps the values readable, which matters because
/// ordering bugs in a tree are otherwise very hard to see.
@MainActor
final class LibraryRepository {

    enum RepositoryError: Error, LocalizedError {
        case notFound
        case invalidMove(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                "The item no longer exists."
            case .invalidMove(let reason):
                reason
            }
        }
    }

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Workspaces

    func workspaces() throws -> [WorkspaceSnapshot] {
        let request = CDWorkspace.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return try context.fetch(request).map(Self.snapshot(of:))
    }

    @discardableResult
    func createWorkspace(name: String, iconSymbolName: String = "folder.fill") throws -> WorkspaceSnapshot {
        // Counted before the insert: a newly-created object is already live in
        // the context, so counting afterwards includes it and every new item
        // lands one slot too high.
        let sortOrder = try nextWorkspaceSortOrder()

        let workspace = CDWorkspace(context: context)
        workspace.name = name
        workspace.iconSymbolName = iconSymbolName
        workspace.sortOrder = Int32(sortOrder)
        try context.save()
        return Self.snapshot(of: workspace)
    }

    func renameWorkspace(id: UUID, to name: String) throws {
        let workspace = try fetchWorkspace(id)
        workspace.name = name
        try context.save()
    }

    func setActiveEnvironment(_ environmentID: UUID?, forWorkspace id: UUID) throws {
        let workspace = try fetchWorkspace(id)
        workspace.activeEnvironmentID = environmentID
        try context.save()
    }

    func deleteWorkspace(id: UUID) throws {
        let workspace = try fetchWorkspace(id)
        context.delete(workspace)
        try context.save()
    }

    // MARK: - Tree

    /// The full tree for a workspace.
    ///
    /// Folders and requests share one `sortOrder` sequence per parent and are
    /// interleaved freely. An earlier version forced folders to display first,
    /// which quietly diverged from `move(nodeID:to:at:)` — that honors any drop
    /// index, so a request dropped above a folder would store order 0 and still
    /// render second. One ordered sequence keeps storage and display identical.
    func tree(forWorkspace id: UUID) throws -> [TreeNode] {
        let workspace = try fetchWorkspace(id)
        let folders = workspace.folders
            .filter { $0.parentFolder == nil }
            .map { TreeNode.folder(Self.snapshot(of: $0)) }
        let requests = workspace.requests
            .map { TreeNode.request(Self.summary(of: $0)) }
        return (folders + requests).sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(name: String, in parent: TreeParent) throws -> FolderSnapshot {
        // Counted before the relationship is set — attaching first would make
        // the new folder one of its own siblings.
        let sortOrder = try siblingCount(in: parent)

        let folder = CDFolder(context: context)
        folder.name = name

        switch parent {
        case .workspaceRoot(let workspaceID):
            folder.workspace = try fetchWorkspace(workspaceID)
        case .folder(let folderID):
            folder.parentFolder = try fetchFolder(folderID)
        }

        folder.sortOrder = Int32(sortOrder)
        try context.save()
        return Self.snapshot(of: folder)
    }

    func renameFolder(id: UUID, to name: String) throws {
        let folder = try fetchFolder(id)
        folder.name = name
        try context.save()
    }

    func setFolderExpanded(id: UUID, isExpanded: Bool) throws {
        let folder = try fetchFolder(id)
        folder.isExpanded = isExpanded
        try context.save()
    }

    func deleteFolder(id: UUID) throws {
        let folder = try fetchFolder(id)
        let parent = Self.parent(of: folder)
        context.delete(folder)
        try context.save()
        if let parent { try renumber(parent) }
    }

    // MARK: - Requests

    @discardableResult
    func createRequest(
        name: String,
        method: String = "GET",
        in parent: TreeParent
    ) throws -> RequestSummary {
        // Counted before the relationship is set — see `createFolder`.
        let sortOrder = try siblingCount(in: parent)

        let request = CDRequest(context: context)
        request.name = name
        request.method = method

        switch parent {
        case .workspaceRoot(let workspaceID):
            request.workspace = try fetchWorkspace(workspaceID)
        case .folder(let folderID):
            request.folder = try fetchFolder(folderID)
        }

        request.sortOrder = Int32(sortOrder)
        try context.save()
        return Self.summary(of: request)
    }

    func renameRequest(id: UUID, to name: String) throws {
        let request = try fetchRequest(id)
        request.name = name
        request.updatedAt = Date()
        try context.save()
    }

    @discardableResult
    func duplicateRequest(id: UUID) throws -> RequestSummary {
        let source = try fetchRequest(id)
        let copy = CDRequest(context: context)

        copy.name = "\(source.name) copy"
        copy.method = source.method
        copy.urlTemplate = source.urlTemplate
        copy.bodyType = source.bodyType
        copy.bodyContent = source.bodyContent
        copy.binaryBookmark = source.binaryBookmark
        copy.graphqlVariables = source.graphqlVariables
        copy.authType = source.authType
        copy.authData = source.authData
        copy.followRedirects = source.followRedirects
        copy.timeout = source.timeout
        copy.folder = source.folder
        copy.workspace = source.workspace
        copy.sortOrder = source.sortOrder + 1

        for header in source.headers {
            let new = CDHeader(context: context)
            new.key = header.key
            new.value = header.value
            new.isEnabled = header.isEnabled
            new.sortOrder = header.sortOrder
            new.note = header.note
            new.request = copy
        }
        for param in source.queryParams {
            let new = CDQueryParam(context: context)
            new.key = param.key
            new.value = param.value
            new.isEnabled = param.isEnabled
            new.sortOrder = param.sortOrder
            new.note = param.note
            new.request = copy
        }

        // Runs are history of the original and are deliberately not copied.

        try context.save()
        if let parent = Self.parent(of: copy) { try renumber(parent) }
        return Self.summary(of: copy)
    }

    func deleteRequest(id: UUID) throws {
        let request = try fetchRequest(id)
        let parent = Self.parent(of: request)
        context.delete(request)
        try context.save()
        if let parent { try renumber(parent) }
    }

    // MARK: - Moving & reordering

    /// Moves a folder or request to `destination`, inserting at `index`
    /// (or appending when `index` is nil), then renumbers both affected parents.
    func move(nodeID: UUID, to destination: TreeParent, at index: Int? = nil) throws {
        if let folder = try? fetchFolder(nodeID) {
            try moveFolder(folder, to: destination, at: index)
        } else if let request = try? fetchRequest(nodeID) {
            try moveRequest(request, to: destination, at: index)
        } else {
            throw RepositoryError.notFound
        }
    }

    private func moveFolder(_ folder: CDFolder, to destination: TreeParent, at index: Int?) throws {
        // A folder cannot be moved inside itself or its own descendant — that
        // would detach the whole subtree from the workspace and orphan it.
        if case .folder(let destinationID) = destination {
            let target = try fetchFolder(destinationID)
            if target.id == folder.id || Self.isDescendant(target, of: folder) {
                throw RepositoryError.invalidMove("A folder can't be moved into itself.")
            }
        }

        let oldParent = Self.parent(of: folder)

        folder.workspace = nil
        folder.parentFolder = nil
        switch destination {
        case .workspaceRoot(let workspaceID):
            folder.workspace = try fetchWorkspace(workspaceID)
        case .folder(let folderID):
            folder.parentFolder = try fetchFolder(folderID)
        }

        try place(folder.id, in: destination, at: index)
        try context.save()
        if let oldParent, oldParent != destination { try renumber(oldParent) }
    }

    private func moveRequest(_ request: CDRequest, to destination: TreeParent, at index: Int?) throws {
        let oldParent = Self.parent(of: request)

        request.workspace = nil
        request.folder = nil
        switch destination {
        case .workspaceRoot(let workspaceID):
            request.workspace = try fetchWorkspace(workspaceID)
        case .folder(let folderID):
            request.folder = try fetchFolder(folderID)
        }

        try place(request.id, in: destination, at: index)
        try context.save()
        if let oldParent, oldParent != destination { try renumber(oldParent) }
    }

    /// Assigns dense sort orders within `parent`, putting `movedID` at `index`.
    private func place(_ movedID: UUID, in parent: TreeParent, at index: Int?) throws {
        var siblings = try siblingIDs(in: parent)
        siblings.removeAll { $0 == movedID }

        let target = min(max(index ?? siblings.count, 0), siblings.count)
        siblings.insert(movedID, at: target)

        try applyOrder(siblings, in: parent)
    }

    /// Renumbers a parent's children densely from 0, preserving current order.
    private func renumber(_ parent: TreeParent) throws {
        let siblings = try siblingIDs(in: parent)
        try applyOrder(siblings, in: parent)
        if context.hasChanges { try context.save() }
    }

    private func applyOrder(_ orderedIDs: [UUID], in parent: TreeParent) throws {
        let (folders, requests) = try siblings(in: parent)
        var lookup: [UUID: NSManagedObject] = [:]
        for folder in folders { lookup[folder.id] = folder }
        for request in requests { lookup[request.id] = request }

        for (position, id) in orderedIDs.enumerated() {
            switch lookup[id] {
            case let folder as CDFolder: folder.sortOrder = Int32(position)
            case let request as CDRequest: request.sortOrder = Int32(position)
            default: continue
            }
        }
    }

    // MARK: - Sibling helpers

    private func siblings(in parent: TreeParent) throws -> (folders: [CDFolder], requests: [CDRequest]) {
        switch parent {
        case .workspaceRoot(let workspaceID):
            let workspace = try fetchWorkspace(workspaceID)
            return (
                workspace.folders.filter { $0.parentFolder == nil },
                Array(workspace.requests)
            )
        case .folder(let folderID):
            let folder = try fetchFolder(folderID)
            return (Array(folder.subfolders), Array(folder.requests))
        }
    }

    /// Sibling ids in display order: folders first, then requests, each by
    /// `sortOrder`. This is the order the outline view renders.
    private func siblingIDs(in parent: TreeParent) throws -> [UUID] {
        let (folders, requests) = try siblings(in: parent)
        return folders.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
            + requests.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
    }

    private func siblingCount(in parent: TreeParent) throws -> Int {
        let (folders, requests) = try siblings(in: parent)
        return folders.count + requests.count
    }

    private func nextWorkspaceSortOrder() throws -> Int {
        let request = CDWorkspace.fetchRequest()
        return try context.count(for: request)
    }

    // MARK: - Fetching

    private func fetchWorkspace(_ id: UUID) throws -> CDWorkspace {
        try fetchOne(CDWorkspace.fetchRequest(), id: id)
    }

    private func fetchFolder(_ id: UUID) throws -> CDFolder {
        try fetchOne(CDFolder.fetchRequest(), id: id)
    }

    private func fetchRequest(_ id: UUID) throws -> CDRequest {
        try fetchOne(CDRequest.fetchRequest(), id: id)
    }

    private func fetchOne<T: NSManagedObject>(_ request: NSFetchRequest<T>, id: UUID) throws -> T {
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let result = try context.fetch(request).first else {
            throw RepositoryError.notFound
        }
        return result
    }

    // MARK: - Conversions

    private static func parent(of folder: CDFolder) -> TreeParent? {
        if let parent = folder.parentFolder { return .folder(parent.id) }
        if let workspace = folder.workspace { return .workspaceRoot(workspace.id) }
        return nil
    }

    private static func parent(of request: CDRequest) -> TreeParent? {
        if let folder = request.folder { return .folder(folder.id) }
        if let workspace = request.workspace { return .workspaceRoot(workspace.id) }
        return nil
    }

    private static func isDescendant(_ candidate: CDFolder, of ancestor: CDFolder) -> Bool {
        var node = candidate.parentFolder
        while let current = node {
            if current.id == ancestor.id { return true }
            node = current.parentFolder
        }
        return false
    }

    static func snapshot(of workspace: CDWorkspace) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            id: workspace.id,
            name: workspace.name,
            sortOrder: Int(workspace.sortOrder),
            iconSymbolName: workspace.iconSymbolName,
            activeEnvironmentID: workspace.activeEnvironmentID,
            requestCount: countRequests(in: workspace)
        )
    }

    private static func countRequests(in workspace: CDWorkspace) -> Int {
        func count(_ folder: CDFolder) -> Int {
            folder.requests.count + folder.subfolders.reduce(0) { $0 + count($1) }
        }
        return workspace.requests.count
            + workspace.folders.filter { $0.parentFolder == nil }.reduce(0) { $0 + count($1) }
    }

    static func snapshot(of folder: CDFolder) -> FolderSnapshot {
        let subfolders = folder.subfolders.map { TreeNode.folder(snapshot(of: $0)) }
        let requests = folder.requests.map { TreeNode.request(summary(of: $0)) }

        return FolderSnapshot(
            id: folder.id,
            name: folder.name,
            sortOrder: Int(folder.sortOrder),
            isExpanded: folder.isExpanded,
            children: (subfolders + requests).sorted { $0.sortOrder < $1.sortOrder }
        )
    }

    static func summary(of request: CDRequest) -> RequestSummary {
        RequestSummary(
            id: request.id,
            name: request.name,
            method: request.method,
            sortOrder: Int(request.sortOrder)
        )
    }
}
