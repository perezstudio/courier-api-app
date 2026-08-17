import AppKit

/// One window per open request, joined into a native tab group.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {

    private let libraryController: LibraryController
    private unowned let registry: WindowRegistry

    private let rootSplit: RootSplitViewController
    private var toolbarDelegate: MainToolbarDelegate?

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
            onNewRequest: { [weak self] in self?.newRequestInNewTab() },
            onFilterChange: { [weak self] text in self?.applyFilter(text) }
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

    private func newRequestInNewTab() {
        guard let summary = libraryController.createRequest() else { return }
        registry.forEachController { $0.refreshTitles() }
        registry.openInNewTab(requestID: summary.id)
    }

    private func applyFilter(_ text: String) {
        libraryController.filterText = text
    }

    // MARK: - Menu actions
    //
    // `NSWindowController` sits in the responder chain, so menu items with a
    // nil target reach these on the frontmost window.

    @objc func newRequest(_ sender: Any?) {
        newRequestInNewTab()
    }

    @objc func newFolder(_ sender: Any?) {
        libraryController.createFolder()
    }

    @objc func newTab(_ sender: Any?) {
        registry.openInNewTab(requestID: nil)
    }

    @objc func toggleResponsePaneAction(_ sender: Any?) {
        rootSplit.toggleResponsePane()
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
}
