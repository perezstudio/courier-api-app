import CoreData
import Foundation

/// Cancels an observation when released or explicitly cancelled.
///
/// `cancelNow()` must take effect *synchronously* — an earlier version deferred
/// removal to a `Task`, so a cancelled observer still fired for any change made
/// later in the same turn. `isolated deinit` lets the automatic path share the
/// same main-actor cleanup instead of needing a second, async mechanism.
@MainActor
final class ObservationToken {
    private let cancel: @MainActor () -> Void
    private var isCancelled = false

    init(cancel: @escaping @MainActor () -> Void) {
        self.cancel = cancel
    }

    isolated deinit {
        if !isCancelled { cancel() }
    }

    func cancelNow() {
        guard !isCancelled else { return }
        isCancelled = true
        cancel()
    }
}

/// The single owner of collection-tree state shared by every window.
///
/// Request tabs are native window tabs, so each tab is a full `NSWindow` with
/// its own sidebar (REQUIREMENTS.md §7.2). If each window owned its own tree
/// state, expanding a folder in one tab would not expand it in the next — which
/// reads as a bug, not a feature. So expansion, active workspace, filter text,
/// and the tree snapshot live here, app-wide; only *selection* is per-window.
///
/// §11 names this the top risk of the window-tab design, which is why it is
/// built and verified in Phase 2, before the sidebar lands in Phase 3.
@MainActor
final class LibraryController {

    private let stack: CoreDataStack
    /// Exposed so editors can read and write auth secrets without a second
    /// dependency-injection path down through the view controllers.
    let secretStore: SecretStore
    let library: LibraryRepository
    let requests: RequestRepository
    let environments: EnvironmentRepository
    let runs: RunRepository

    // MARK: - Shared state

    private(set) var workspaces: [WorkspaceSnapshot] = []
    private(set) var tree: [TreeNode] = []

    /// Folder ids the user has expanded. Shared so the tree looks the same in
    /// every tab.
    private(set) var expandedFolderIDs: Set<UUID> = []

    private(set) var activeWorkspaceID: UUID? {
        didSet { if oldValue != activeWorkspaceID { reloadTree() } }
    }

    var filterText: String = "" {
        didSet { if oldValue != filterText { notifyObservers() } }
    }

    var activeWorkspace: WorkspaceSnapshot? {
        guard let activeWorkspaceID else { return nil }
        return workspaces.first { $0.id == activeWorkspaceID }
    }

    // MARK: - Observation

    private var observers: [UUID: () -> Void] = [:]

    /// Undo is deliberately **not** wired up yet — see the note on
    /// `MainWindowController.windowWillReturnUndoManager`.
    var undoManager: UndoManager? { nil }

    init(stack: CoreDataStack, secretStore: SecretStore) {
        self.stack = stack
        self.secretStore = secretStore
        library = LibraryRepository(context: stack.viewContext)
        requests = RequestRepository(context: stack.viewContext)
        environments = EnvironmentRepository(context: stack.viewContext, secretStore: secretStore)
        runs = RunRepository(context: stack.viewContext)
    }

    /// Registers a change handler. Every window's sidebar holds one of these;
    /// the returned token unregisters on deinit.
    func observe(_ handler: @escaping () -> Void) -> ObservationToken {
        let id = UUID()
        observers[id] = handler
        return ObservationToken { [weak self] in
            self?.removeObserver(id)
        }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notifyObservers() {
        for handler in observers.values {
            handler()
        }
    }

    // MARK: - Loading

    /// Loads workspaces, creating a default one on first launch so the app has
    /// somewhere to put a new request.
    func load() {
        do {
            workspaces = try library.workspaces()
            if workspaces.isEmpty {
                try library.createWorkspace(name: "My Workspace")
                workspaces = try library.workspaces()
            }
            if activeWorkspaceID == nil || !workspaces.contains(where: { $0.id == activeWorkspaceID }) {
                activeWorkspaceID = workspaces.first?.id
            }
            reloadTree()
        } catch {
            workspaces = []
            tree = []
            notifyObservers()
        }
    }

    /// Re-reads the tree and tells every window. Call after any mutation.
    ///
    /// Refreshes the workspace snapshots too. `requestCount` is derived from the
    /// tree but lives on `WorkspaceSnapshot`, so refreshing only `tree` leaves
    /// the sidebar reporting a stale count — it showed "0 requests" after two
    /// were created.
    func reloadTree() {
        workspaces = (try? library.workspaces()) ?? []

        if let activeWorkspaceID {
            tree = (try? library.tree(forWorkspace: activeWorkspaceID)) ?? []
        } else {
            tree = []
        }
        notifyObservers()
    }

    /// Re-reads workspaces and the tree, re-picking the active workspace if it
    /// has gone away.
    func reloadAll() {
        workspaces = (try? library.workspaces()) ?? []
        if !workspaces.contains(where: { $0.id == activeWorkspaceID }) {
            activeWorkspaceID = workspaces.first?.id
        }
        reloadTree()
    }

    func setActiveWorkspace(_ id: UUID) {
        activeWorkspaceID = id
    }

    /// The tree for one specific workspace, rather than whichever is active.
    ///
    /// The sidebar's pager shows every workspace at once — a page whose content
    /// only appeared once it became active would slide in empty.
    func tree(forWorkspace id: UUID) -> [TreeNode] {
        (try? library.tree(forWorkspace: id)) ?? []
    }

    @discardableResult
    func createWorkspace(name: String) -> WorkspaceSnapshot? {
        guard let snapshot = try? library.createWorkspace(name: name) else { return nil }
        reloadAll()
        return snapshot
    }

    // MARK: - Expansion

    func isExpanded(_ folderID: UUID) -> Bool {
        expandedFolderIDs.contains(folderID)
    }

    func setExpanded(_ isExpanded: Bool, forFolder folderID: UUID) {
        let changed: Bool
        if isExpanded {
            changed = expandedFolderIDs.insert(folderID).inserted
        } else {
            changed = expandedFolderIDs.remove(folderID) != nil
        }
        guard changed else { return }

        // Persisted so expansion survives relaunch, and notified so sibling
        // tabs match immediately.
        try? library.setFolderExpanded(id: folderID, isExpanded: isExpanded)
        notifyObservers()
    }

    /// Seeds expansion from the store. Called once at launch.
    func loadExpansionState() {
        var expanded: Set<UUID> = []
        func walk(_ nodes: [TreeNode]) {
            for node in nodes {
                guard case .folder(let folder) = node else { continue }
                if folder.isExpanded { expanded.insert(folder.id) }
                walk(folder.children)
            }
        }
        walk(tree)
        expandedFolderIDs = expanded
    }

    // MARK: - Mutations

    /// Creates a request in the active workspace's root.
    @discardableResult
    func createRequest(named name: String = "New Request") -> RequestSummary? {
        guard let activeWorkspaceID else { return nil }
        let summary = try? library.createRequest(name: name, in: .workspaceRoot(activeWorkspaceID))
        reloadTree()
        return summary
    }

    @discardableResult
    func createFolder(named name: String = "New Folder") -> FolderSnapshot? {
        guard let activeWorkspaceID else { return nil }
        let snapshot = try? library.createFolder(name: name, in: .workspaceRoot(activeWorkspaceID))
        reloadTree()
        return snapshot
    }

    // MARK: - Environments

    /// Environments for the active workspace.
    func environmentsForActiveWorkspace() -> [EnvironmentSnapshot] {
        guard let activeWorkspaceID else { return [] }
        return (try? environments.environments(forWorkspace: activeWorkspaceID)) ?? []
    }

    var activeEnvironmentID: UUID? {
        activeWorkspace?.activeEnvironmentID
    }

    var activeEnvironmentName: String? {
        guard let activeEnvironmentID else { return nil }
        return environmentsForActiveWorkspace()
            .first { $0.id == activeEnvironmentID }?
            .name
    }

    func setActiveEnvironment(_ environmentID: UUID?) {
        guard let activeWorkspaceID else { return }
        try? library.setActiveEnvironment(environmentID, forWorkspace: activeWorkspaceID)
        reloadTree()
    }

    /// Builds the resolution context for the active workspace.
    ///
    /// Lives here rather than on the sender because the Variables tab has to
    /// show exactly what a send would use — two implementations would drift and
    /// the preview would start lying.
    func makeVariableContext() -> VariableResolver.Context {
        guard let activeWorkspaceID else { return VariableResolver.Context() }

        var environmentValues: [String: String] = [:]
        if let activeEnvironmentID,
           let environment = environmentsForActiveWorkspace()
               .first(where: { $0.id == activeEnvironmentID }) {
            for variable in environment.variables where variable.isEnabled {
                environmentValues[variable.key] = resolvedValue(of: variable)
            }
        }

        var collectionValues: [String: String] = [:]
        if let variables = try? environments.collectionVariables(forWorkspace: activeWorkspaceID) {
            for variable in variables where variable.isEnabled {
                collectionValues[variable.key] = resolvedValue(of: variable)
            }
        }

        return VariableResolver.Context.build([
            (.environment, environmentValues),
            (.collection, collectionValues),
        ])
    }

    /// Secret values come from the Keychain, never from the snapshot.
    private func resolvedValue(of variable: VariableSnapshot) -> String {
        guard variable.isSecret else { return variable.value }
        return (try? environments.value(for: variable.id)) ?? ""
    }

    /// Looks up a request summary anywhere in the current tree.
    func requestSummary(for id: UUID) -> RequestSummary? {
        func find(_ nodes: [TreeNode]) -> RequestSummary? {
            for node in nodes {
                switch node {
                case .request(let request) where request.id == id:
                    return request
                case .folder(let folder):
                    if let found = find(folder.children) { return found }
                case .request:
                    continue
                }
            }
            return nil
        }
        return find(tree)
    }

    /// The collection path to a request, for the window subtitle.
    func path(toRequest id: UUID) -> String {
        var result: [String] = []

        func walk(_ nodes: [TreeNode], trail: [String]) -> Bool {
            for node in nodes {
                switch node {
                case .request(let request) where request.id == id:
                    result = trail
                    return true
                case .folder(let folder):
                    if walk(folder.children, trail: trail + [folder.name]) { return true }
                case .request:
                    continue
                }
            }
            return false
        }

        let workspaceName = activeWorkspace?.name ?? ""
        _ = walk(tree, trail: [workspaceName])
        return result.joined(separator: " › ")
    }
}
