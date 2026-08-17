import AppKit

/// Sheet for managing environments and their variables.
///
/// Master/detail: environments on the left (plus a fixed "Collection Variables"
/// entry for workspace scope), that selection's variables on the right.
@MainActor
final class EnvironmentWindowController: NSWindowController {

    private let libraryController: LibraryController

    private let listViewController = EnvironmentListViewController()
    private let tableViewController = VariableTableViewController()
    /// Retained explicitly: the window uses a plain `contentView`, so nothing
    /// else keeps the split controller alive.
    private let splitViewController = NSSplitViewController()

    /// nil means the fixed collection-scope row is selected.
    private var selectedEnvironmentID: UUID?
    private var isCollectionScopeSelected = true

    init(libraryController: LibraryController) {
        self.libraryController = libraryController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Environments"
        // Sized to fit both panes plus the variable table's columns; narrower
        // than this and the Secret column is clipped off the right edge.
        window.minSize = NSSize(width: 780, height: 380)
        window.setContentSize(NSSize(width: 860, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let split = splitViewController
        let listItem = NSSplitViewItem(sidebarWithViewController: listViewController)
        listItem.minimumThickness = 180
        listItem.maximumThickness = 260
        listItem.canCollapse = false
        split.addSplitViewItem(listItem)

        let detailItem = NSSplitViewItem(viewController: tableViewController)
        detailItem.minimumThickness = 360
        split.addSplitViewItem(detailItem)

        // A sheet hides its title bar, so `.closable` gives the user nothing to
        // click — without an explicit Done button the sheet is a trap.
        //
        // Built as a plain `contentView` rather than a `contentViewController`:
        // assigning a container view controller resized the sheet to a size
        // that clipped the button bar entirely.
        window.contentViewController = split
        wire()
    }



    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Wiring

    private func wire() {
        listViewController.onSelect = { [weak self] selection in
            guard let self else { return }
            switch selection {
            case .collection:
                isCollectionScopeSelected = true
                selectedEnvironmentID = nil
            case .environment(let id):
                isCollectionScopeSelected = false
                selectedEnvironmentID = id
            }
            reloadVariables()
        }
        listViewController.onCreate = { [weak self] in self?.createEnvironment() }
        listViewController.onRename = { [weak self] id, name in
            try? self?.libraryController.environments.renameEnvironment(id: id, to: name)
            self?.reloadAll()
        }
        listViewController.onDelete = { [weak self] id in self?.deleteEnvironment(id) }

        tableViewController.onAdd = { [weak self] in self?.addVariable() }
        tableViewController.onDone = { [weak self] in self?.closeSheet() }
        tableViewController.onEdit = { [weak self] row in self?.updateVariable(row) }
        tableViewController.onDelete = { [weak self] id in
            try? self?.libraryController.environments.deleteVariable(id: id)
            self?.reloadVariables()
        }
    }

    // MARK: - Presentation

    /// Shown as an ordinary window rather than a sheet.
    ///
    /// A sheet hides its title bar, so it has no close control of its own and
    /// needs a hand-built button bar — which then has to fit inside a sheet
    /// narrow enough to clip the variable table. A titled utility window gets a
    /// real close button for free, can be resized, and can stay open while the
    /// user edits requests against it.
    func present(in parent: NSWindow) {
        reloadAll()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func closeSheet() {
        // Revealed secrets must not persist into the next opening.
        tableViewController.hideRevealedSecrets()
        window?.performClose(nil)
    }

    // MARK: - Data

    private func reloadAll() {
        let environments = libraryController.environmentsForActiveWorkspace()
        listViewController.setEnvironments(
            environments,
            activeID: libraryController.activeEnvironmentID
        )

        if let selectedEnvironmentID,
           !environments.contains(where: { $0.id == selectedEnvironmentID }) {
            self.selectedEnvironmentID = nil
            isCollectionScopeSelected = true
        }
        reloadVariables()
    }

    private func reloadVariables() {
        let variables: [VariableSnapshot]

        if isCollectionScopeSelected {
            variables = (try? libraryController.environments.collectionVariables(
                forWorkspace: libraryController.activeWorkspaceID ?? UUID()
            )) ?? []
        } else if let selectedEnvironmentID,
                  let environment = libraryController.environmentsForActiveWorkspace()
                      .first(where: { $0.id == selectedEnvironmentID }) {
            variables = environment.variables
        } else {
            variables = []
        }

        tableViewController.setRows(
            variables.map { variable in
                VariableTableViewController.Row(
                    id: variable.id,
                    key: variable.key,
                    // A secret's real value is only loaded when the user asks
                    // to see it; the snapshot deliberately carries an empty one.
                    value: variable.isSecret
                        ? ((try? libraryController.environments.value(for: variable.id)) ?? "")
                        : variable.value,
                    isSecret: variable.isSecret,
                    isEnabled: variable.isEnabled
                )
            }
        )
    }

    // MARK: - Mutations

    private func createEnvironment() {
        guard let workspaceID = libraryController.activeWorkspaceID else { return }
        guard let environment = try? libraryController.environments.createEnvironment(
            name: "New Environment",
            inWorkspace: workspaceID
        ) else { return }

        selectedEnvironmentID = environment.id
        isCollectionScopeSelected = false
        libraryController.reloadTree()
        reloadAll()
        listViewController.beginRenaming(environment.id)
    }

    private func deleteEnvironment(_ id: UUID) {
        let alert = NSAlert()
        alert.messageText = "Delete this environment?"
        alert.informativeText = "Its variables and any secrets stored for them will be removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if libraryController.activeEnvironmentID == id {
            libraryController.setActiveEnvironment(nil)
        }
        try? libraryController.environments.deleteEnvironment(id: id)

        selectedEnvironmentID = nil
        isCollectionScopeSelected = true
        libraryController.reloadTree()
        reloadAll()
    }

    private func addVariable() {
        guard let workspaceID = libraryController.activeWorkspaceID else { return }

        if isCollectionScopeSelected {
            try? libraryController.environments.addCollectionVariable(
                key: "", value: "", isSecret: false, toWorkspace: workspaceID
            )
        } else if let selectedEnvironmentID {
            try? libraryController.environments.addVariable(
                key: "", value: "", isSecret: false, toEnvironment: selectedEnvironmentID
            )
        }
        reloadVariables()
        libraryController.reloadTree()
    }

    private func updateVariable(_ row: VariableTableViewController.Row) {
        try? libraryController.environments.updateVariable(
            id: row.id,
            key: row.key,
            value: row.value,
            isSecret: row.isSecret,
            isEnabled: row.isEnabled
        )
        // Notifies every window so the Variables tab and unresolved warnings
        // update while the sheet is still open.
        libraryController.reloadTree()
    }
}
