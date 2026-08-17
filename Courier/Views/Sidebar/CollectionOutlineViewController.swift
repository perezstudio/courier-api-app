import AppKit

/// The collection tree.
///
/// Backed by immutable snapshots from `LibraryRepository` rather than an
/// `NSFetchedResultsController` — an FRC is flat and cannot express a nested
/// tree. This is the approach REQUIREMENTS.md §11 prescribes as the mitigation
/// for this exact combination: the repository hands out a snapshot and the
/// outline view rebuilds against it, with expansion and selection restored by
/// id.
@MainActor
final class CollectionOutlineViewController: NSViewController {

    static let nodePasteboardType = NSPasteboard.PasteboardType("com.perezstudio.Courier.node")

    private let libraryController: LibraryController
    private unowned let registry: WindowRegistry

    private let outlineView = SidebarOutlineView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No requests")

    private var roots: [SidebarNode] = []
    private var observation: ObservationToken?

    /// Suppresses expansion callbacks while the view is being rebuilt, so
    /// restoring state doesn't write it straight back to the store.
    private var isRestoring = false

    init(libraryController: LibraryController, registry: WindowRegistry) {
        self.libraryController = libraryController
        self.registry = registry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOutlineView()
        setupLayout()

        observation = libraryController.observe { [weak self] in
            self?.rebuild()
        }
        rebuild()
    }

    private func setupOutlineView() {
        outlineView.style = .sourceList
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 14
        outlineView.allowsMultipleSelection = true
        outlineView.autoresizesOutlineColumn = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.interactionDelegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(rename(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.registerForDraggedTypes([Self.nodePasteboardType])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = true
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        view.addSubview(scrollView)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
        ])
    }

    // MARK: - Rebuilding

    /// Rebuilds from the shared snapshot, preserving expansion and selection.
    private func rebuild() {
        let selectedIDs = selectedNodeIDs()

        roots = SidebarNode.build(
            from: libraryController.tree,
            filter: libraryController.filterText
        )

        isRestoring = true
        outlineView.reloadData()
        restoreExpansion()
        restoreSelection(selectedIDs)
        isRestoring = false

        let isEmpty = roots.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyLabel.stringValue = libraryController.filterText.isEmpty
            ? "No requests"
            : "No matches"
    }

    private func restoreExpansion() {
        func walk(_ nodes: [SidebarNode]) {
            for node in nodes where node.isFolder {
                // While filtering, force folders open so matches deeper in the
                // tree are actually visible.
                let shouldExpand = !libraryController.filterText.isEmpty
                    || libraryController.isExpanded(node.id)
                if shouldExpand {
                    outlineView.expandItem(node)
                }
                walk(node.children)
            }
        }
        walk(roots)
    }

    private func selectedNodeIDs() -> [UUID] {
        outlineView.selectedRowIndexes.compactMap {
            (outlineView.item(atRow: $0) as? SidebarNode)?.id
        }
    }

    private func restoreSelection(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var indexes = IndexSet()
        for id in ids {
            guard let node = SidebarNode.find(id, in: roots) else { continue }
            let row = outlineView.row(forItem: node)
            if row >= 0 { indexes.insert(row) }
        }
        outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    // MARK: - Selection helpers

    private var focusedNode: SidebarNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? SidebarNode
    }

    /// The parent a new item should be created in, given what's selected.
    private func insertionParent() -> TreeParent? {
        guard let workspaceID = libraryController.activeWorkspaceID else { return nil }
        guard let node = focusedNode else { return .workspaceRoot(workspaceID) }

        // Creating while a folder is selected puts the item inside it; while a
        // request is selected, alongside it.
        if node.isFolder { return .folder(node.id) }
        if let parent = node.parent { return .folder(parent.id) }
        return .workspaceRoot(workspaceID)
    }
}

// MARK: - Data source

extension CollectionOutlineViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? SidebarNode else { return roots.count }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? SidebarNode else { return roots[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.isFolder ?? false
    }

    // MARK: Drag & drop

    func outlineView(
        _ outlineView: NSOutlineView,
        pasteboardWriterForItem item: Any
    ) -> NSPasteboardWriting? {
        guard let node = item as? SidebarNode else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(node.id.uuidString, forType: Self.nodePasteboardType)
        return pasteboardItem
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let draggedID = draggedNodeID(from: info) else { return [] }

        // Dropping *onto* a request would be meaningless — requests hold
        // nothing. Retarget those to the request's parent.
        if let target = item as? SidebarNode, !target.isFolder {
            return []
        }

        // A folder cannot absorb itself or its own descendant; the repository
        // rejects it too, but refusing the drop is better feedback than
        // accepting and failing.
        if let target = item as? SidebarNode,
           let dragged = SidebarNode.find(draggedID, in: roots),
           dragged.isFolder,
           target.id == dragged.id || isDescendant(target, of: dragged) {
            return []
        }

        return .move
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard
            let draggedID = draggedNodeID(from: info),
            let workspaceID = libraryController.activeWorkspaceID
        else { return false }

        let destination: TreeParent
        if let target = item as? SidebarNode, target.isFolder {
            destination = .folder(target.id)
        } else {
            destination = .workspaceRoot(workspaceID)
        }

        // NSOutlineViewDropOnItemIndex (-1) means "onto the container" rather
        // than at a position, which the repository reads as append.
        let childIndex = index == NSOutlineViewDropOnItemIndex ? nil : index

        do {
            try libraryController.library.move(
                nodeID: draggedID,
                to: destination,
                at: childIndex
            )
            libraryController.reloadTree()
            return true
        } catch {
            showMoveError(error)
            return false
        }
    }

    private func draggedNodeID(from info: NSDraggingInfo) -> UUID? {
        guard
            let string = info.draggingPasteboard.string(forType: Self.nodePasteboardType)
        else { return nil }
        return UUID(uuidString: string)
    }

    private func isDescendant(_ candidate: SidebarNode, of ancestor: SidebarNode) -> Bool {
        var node = candidate.parent
        while let current = node {
            if current.id == ancestor.id { return true }
            node = current.parent
        }
        return false
    }
}

// MARK: - Delegate

extension CollectionOutlineViewController: NSOutlineViewDelegate {

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }

        if node.isFolder {
            let cell = outlineView.makeView(
                withIdentifier: FolderCellView.reuseIdentifier, owner: self
            ) as? FolderCellView ?? {
                let new = FolderCellView()
                new.identifier = FolderCellView.reuseIdentifier
                return new
            }()
            cell.configure(node: node)
            cell.textField?.delegate = self
            return cell
        }

        let cell = outlineView.makeView(
            withIdentifier: RequestCellView.reuseIdentifier, owner: self
        ) as? RequestCellView ?? {
            let new = RequestCellView()
            new.identifier = RequestCellView.reuseIdentifier
            return new
        }()
        cell.configure(node: node)
        cell.textField?.delegate = self
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isRestoring else { return }
        guard let node = focusedNode, !node.isFolder else { return }
        registry.navigateCurrentTab(to: node.id)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isRestoring,
              let node = notification.userInfo?["NSObject"] as? SidebarNode
        else { return }
        libraryController.setExpanded(true, forFolder: node.id)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isRestoring,
              let node = notification.userInfo?["NSObject"] as? SidebarNode
        else { return }
        libraryController.setExpanded(false, forFolder: node.id)
    }
}

// MARK: - Interaction

extension CollectionOutlineViewController: SidebarOutlineViewDelegate {

    func outlineView(_ outlineView: SidebarOutlineView, didCommandClickRow row: Int) {
        guard let node = outlineView.item(atRow: row) as? SidebarNode, !node.isFolder else { return }
        registry.openInNewTab(requestID: node.id)
    }

    func outlineViewDidPressDelete(_ outlineView: SidebarOutlineView) {
        delete(nil)
    }

    func outlineView(_ outlineView: SidebarOutlineView, menuForRow row: Int) -> NSMenu? {
        let menu = NSMenu()

        menu.addItem(withTitle: "New Request", action: #selector(newRequest(_:)), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "New Folder", action: #selector(newFolder(_:)), keyEquivalent: "")
            .target = self

        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else {
            return menu
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Rename", action: #selector(rename(_:)), keyEquivalent: "")
            .target = self

        if !node.isFolder {
            menu.addItem(withTitle: "Duplicate", action: #selector(duplicate(_:)), keyEquivalent: "")
                .target = self
            menu.addItem(
                withTitle: "Open in New Tab",
                action: #selector(openInNewTab(_:)),
                keyEquivalent: ""
            ).target = self
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(delete(_:)), keyEquivalent: "")
            .target = self

        return menu
    }
}

// MARK: - Actions

extension CollectionOutlineViewController: NSTextFieldDelegate {

    @objc func newRequest(_ sender: Any?) {
        createRequestAtSelection()
    }

    @objc func newFolder(_ sender: Any?) {
        createFolderAtSelection()
    }

    /// Creates a request where the selection implies, selects it, and starts an
    /// inline rename.
    ///
    /// The File menu routes here too, so Cmd+N and the context menu can't drift
    /// apart — an earlier version had the menu always create at the workspace
    /// root while the context menu created inside the selected folder.
    func createRequestAtSelection() {
        guard let parent = insertionParent() else { return }
        guard let summary = try? libraryController.library.createRequest(
            name: "New Request", in: parent
        ) else { return }

        if case .folder(let folderID) = parent {
            libraryController.setExpanded(true, forFolder: folderID)
        }
        libraryController.reloadTree()
        registry.forEachController { $0.refreshTitles() }
        select(id: summary.id, startEditing: true)
        registry.navigateCurrentTab(to: summary.id)
    }

    func createFolderAtSelection() {
        guard let parent = insertionParent() else { return }
        guard let folder = try? libraryController.library.createFolder(
            name: "New Folder", in: parent
        ) else { return }

        if case .folder(let folderID) = parent {
            libraryController.setExpanded(true, forFolder: folderID)
        }
        libraryController.reloadTree()
        select(id: folder.id, startEditing: true)
    }

    @objc func rename(_ sender: Any?) {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return }
        beginEditing(row: row)
    }

    @objc func duplicate(_ sender: Any?) {
        guard let node = focusedNode, !node.isFolder else { return }
        guard let copy = try? libraryController.library.duplicateRequest(id: node.id) else { return }
        libraryController.reloadTree()
        select(id: copy.id, startEditing: false)
    }

    @objc func openInNewTab(_ sender: Any?) {
        guard let node = focusedNode, !node.isFolder else { return }
        registry.openInNewTab(requestID: node.id)
    }

    @objc func delete(_ sender: Any?) {
        let nodes = outlineView.selectedRowIndexes.compactMap {
            outlineView.item(atRow: $0) as? SidebarNode
        }
        guard !nodes.isEmpty else { return }

        // Folder deletes cascade to the whole subtree, so they get a
        // confirmation. Deleting one request is cheap to redo and does not.
        let needsConfirmation = nodes.contains { $0.isFolder } || nodes.count > 1
        if needsConfirmation, !confirmDelete(of: nodes) { return }

        for node in nodes {
            if node.isFolder {
                try? libraryController.library.deleteFolder(id: node.id)
            } else {
                try? libraryController.library.deleteRequest(id: node.id)
            }
        }
        libraryController.reloadTree()
        registry.forEachController { $0.refreshTitles() }
    }

    private func confirmDelete(of nodes: [SidebarNode]) -> Bool {
        let alert = NSAlert()
        if nodes.count == 1, let node = nodes.first {
            alert.messageText = "Delete “\(node.name)”?"
            alert.informativeText = node.isFolder
                ? "Everything inside this folder will be deleted too."
                : "This request will be deleted."
        } else {
            alert.messageText = "Delete \(nodes.count) items?"
            alert.informativeText = "Anything inside the selected folders will be deleted too."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Editing

    private func select(id: UUID, startEditing: Bool) {
        guard let node = SidebarNode.find(id, in: roots) else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }

        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        if startEditing { beginEditing(row: row) }
    }

    private func beginEditing(row: Int) {
        guard let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) else { return }
        (cell as? RequestCellView)?.beginEditing()
        (cell as? FolderCellView)?.beginEditing()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        defer {
            field.isEditable = false
        }

        let row = outlineView.row(for: field)
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return }

        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != node.name else {
            // Reverting keeps an accidental empty name from silently erasing a
            // label the user can no longer identify.
            field.stringValue = node.name
            return
        }

        if node.isFolder {
            try? libraryController.library.renameFolder(id: node.id, to: newName)
        } else {
            try? libraryController.library.renameRequest(id: node.id, to: newName)
        }
        libraryController.reloadTree()
        registry.forEachController { $0.refreshTitles() }
    }

    private func showMoveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
