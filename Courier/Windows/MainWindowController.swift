import AppKit

/// One window per open request, joined into a native tab group.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {

    private let libraryController: LibraryController
    private unowned let registry: WindowRegistry

    private let rootSplit: RootSplitViewController
    private var toolbarDelegate: MainToolbarDelegate?
    private var environmentWindowController: EnvironmentWindowController?
    private var libraryObservation: ObservationToken?

    /// The request shown in this tab. Selection is per-window; everything else
    /// about the tree is shared via `LibraryController` (REQUIREMENTS.md §7.2).
    private(set) var requestID: UUID?

    /// Only the first window claims the autosave name. Tabs adopt the host
    /// window's frame, and several windows sharing one autosave name fight over
    /// it on quit.
    private static var hasFrameAutosaveOwner = false

    init(libraryController: LibraryController, registry: WindowRegistry) {
        self.libraryController = libraryController
        self.registry = registry
        self.rootSplit = RootSplitViewController(
            libraryController: libraryController,
            registry: registry
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        configureWindow(window)
        configureToolbar(window)
        updateTitles()

        libraryObservation = libraryController.observe { [weak self] in
            self?.refreshEnvironmentPicker()
        }
        refreshEnvironmentPicker()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    private func configureWindow(_ window: NSWindow) {
        window.contentViewController = rootSplit
        window.delegate = self
        window.minSize = NSSize(width: 900, height: 500)

        // Native window tabs. `tabbingMode = .preferred` means new windows
        // prefer to become tabs; the shared identifier makes them eligible.
        window.tabbingMode = .preferred
        window.tabbingIdentifier = WindowRegistry.tabbingIdentifier

        if !Self.hasFrameAutosaveOwner {
            Self.hasFrameAutosaveOwner = true
            window.setFrameAutosaveName("CourierMainWindow")
        } else {
            window.center()
        }
    }

    private func configureToolbar(_ window: NSWindow) {
        let delegate = MainToolbarDelegate(
            splitView: rootSplit.splitView,
            onNewRequest: { [weak self] in self?.rootSplit.createRequestAtSelection() },
            onFilterChange: { [weak self] text in self?.applyFilter(text) },
            onEnvironmentChange: { [weak self] id in
                self?.libraryController.setActiveEnvironment(id)
            },
            onEditEnvironments: { [weak self] in self?.showEnvironments(nil) }
        )
        self.toolbarDelegate = delegate

        let toolbar = NSToolbar(identifier: "CourierMainToolbar")
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true

        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
    }

    // MARK: - Content

    /// Points this tab at a request.
    func show(requestID: UUID?) {
        self.requestID = requestID
        rootSplit.showRequest(requestID)
        updateTitles()
    }

    /// Window title and subtitle drive the native tab label, so they are the
    /// tab's name as well as the window's.
    private func updateTitles() {
        guard let window else { return }
        if let requestID, let summary = libraryController.requestSummary(for: requestID) {
            window.title = summary.name
            window.subtitle = libraryController.path(toRequest: requestID)
        } else {
            window.title = "Courier"
            window.subtitle = libraryController.activeWorkspace?.name ?? ""
        }
    }

    /// Refreshes the title after the underlying request changes elsewhere.
    func refreshTitles() {
        updateTitles()
    }

    // MARK: - Actions

    private func applyFilter(_ text: String) {
        libraryController.filterText = text
    }

    // MARK: - Menu actions
    //
    // `NSWindowController` sits in the responder chain, so menu items with a
    // nil target reach these on the frontmost window.

    @objc func newRequest(_ sender: Any?) {
        rootSplit.createRequestAtSelection()
    }

    @objc func newFolder(_ sender: Any?) {
        rootSplit.createFolderAtSelection()
    }

    @objc func newTab(_ sender: Any?) {
        registry.openInNewTab(requestID: nil)
    }

    @objc func toggleResponsePaneAction(_ sender: Any?) {
        rootSplit.toggleResponsePane()
    }

    @objc func showEnvironments(_ sender: Any?) {
        guard let window else { return }
        let controller = EnvironmentWindowController(libraryController: libraryController)
        environmentWindowController = controller
        controller.present(in: window)
    }

    /// Repopulates the toolbar picker from shared state. Every window does
    /// this, so switching environments in one tab shows in all of them.
    private func refreshEnvironmentPicker() {
        toolbarDelegate?.updateEnvironments(
            libraryController.environmentsForActiveWorkspace(),
            activeID: libraryController.activeEnvironmentID
        )
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(newRequest(_:)), #selector(newFolder(_:)):
            // Both need somewhere to put the new item.
            return libraryController.activeWorkspace != nil
        case #selector(toggleResponsePaneAction(_:)):
            return requestID != nil
        default:
            return true
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        registry.controllerWillClose(self)
    }

    /// Returns nil: **undo is not implemented yet**, so Cmd+Z is inert rather
    /// than dangerous.
    ///
    /// Handing the window `viewContext.undoManager` looks like it should work —
    /// REQUIREMENTS.md §7.5 lists undo as a free native win — but Core Data
    /// groups undo registrations by event loop iteration, and repositories save
    /// on every mutation without closing a group. In testing, one Cmd+Z after a
    /// single delete reverted several unrelated operations (the tree went from
    /// six rows to three). Correct undo needs explicit
    /// begin/endUndoGrouping around each repository mutation, which is its own
    /// piece of work. A destructive Cmd+Z is worse than none.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        libraryController.undoManager
    }
}
