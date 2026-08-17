import AppKit

/// Workspace popup above the collection tree.
@MainActor
final class SidebarViewController: NSViewController {

    private let libraryController: LibraryController
    private unowned let registry: WindowRegistry

    private let workspacePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The filter moved out of the toolbar and into the sidebar it filters.
    private let searchField = NSSearchField()
    private let outlineController: CollectionOutlineViewController
    /// Environment picker, pinned below the tree. It scopes the whole
    /// workspace, so it belongs with the workspace, not in the request toolbar.
    private let environmentPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private var observation: ObservationToken?

    /// Opens the environment editor; supplied by the window controller.
    var onEditEnvironments: (() -> Void)?

    /// Sentinel for the "Manage Environments…" row, a command rather than a
    /// selectable environment.
    private static let manageTag = -99

    /// Guards against the popup's own action firing while it is being
    /// repopulated, which would reselect the workspace on every reload.
    private var isPopulating = false

    init(libraryController: LibraryController, registry: WindowRegistry) {
        self.libraryController = libraryController
        self.registry = registry
        self.outlineController = CollectionOutlineViewController(
            libraryController: libraryController,
            registry: registry
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()

        observation = libraryController.observe { [weak self] in
            self?.reloadWorkspaces()
        }
        reloadWorkspaces()
    }

    private func setupLayout() {
        workspacePopUp.translatesAutoresizingMaskIntoConstraints = false
        workspacePopUp.bezelStyle = .rounded
        workspacePopUp.target = self
        workspacePopUp.action = #selector(workspaceChanged(_:))

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Filter"
        searchField.controlSize = .small
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(filterChanged(_:))
        searchField.setAccessibilityLabel("Filter requests")

        environmentPopUp.translatesAutoresizingMaskIntoConstraints = false
        environmentPopUp.bezelStyle = .rounded
        environmentPopUp.controlSize = .small
        environmentPopUp.target = self
        environmentPopUp.action = #selector(environmentChanged(_:))
        environmentPopUp.setAccessibilityLabel("Active environment")

        addChild(outlineController)
        let tree = outlineController.view
        tree.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(workspacePopUp)
        view.addSubview(searchField)
        view.addSubview(tree)
        view.addSubview(environmentPopUp)

        // Pinned to the safe area: the sidebar runs full height under the
        // titlebar, so view.topAnchor would put the popup behind the traffic
        // lights.
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            workspacePopUp.topAnchor.constraint(
                equalTo: safe.topAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            workspacePopUp.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            workspacePopUp.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Theme.Metrics.tightPadding
            ),

            searchField.topAnchor.constraint(
                equalTo: workspacePopUp.bottomAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            searchField.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            searchField.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Theme.Metrics.tightPadding
            ),

            tree.topAnchor.constraint(
                equalTo: searchField.bottomAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            tree.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tree.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tree.bottomAnchor.constraint(
                equalTo: environmentPopUp.topAnchor,
                constant: -Theme.Metrics.tightPadding
            ),

            environmentPopUp.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            environmentPopUp.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Theme.Metrics.tightPadding
            ),
            environmentPopUp.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Theme.Metrics.tightPadding
            ),
        ])
    }

    // MARK: - Creation
    //
    // Forwarded from the File menu so menu and context-menu creation share one
    // insertion rule.

    func createRequestAtSelection() {
        outlineController.createRequestAtSelection()
    }

    func createFolderAtSelection() {
        outlineController.createFolderAtSelection()
    }

    // MARK: - Workspaces

    private func reloadWorkspaces() {
        isPopulating = true
        defer { isPopulating = false }

        workspacePopUp.removeAllItems()
        for workspace in libraryController.workspaces {
            let title = workspace.requestCount == 1
                ? "\(workspace.name) — 1 request"
                : "\(workspace.name) — \(workspace.requestCount) requests"
            workspacePopUp.addItem(withTitle: title)
            workspacePopUp.lastItem?.representedObject = workspace.id
            workspacePopUp.lastItem?.image = NSImage(
                systemSymbolName: workspace.iconSymbolName,
                accessibilityDescription: nil
            )
        }

        if let activeID = libraryController.activeWorkspaceID,
           let index = libraryController.workspaces.firstIndex(where: { $0.id == activeID }) {
            workspacePopUp.selectItem(at: index)
        }

        reloadEnvironments()
    }

    private func reloadEnvironments() {
        let environments = libraryController.environmentsForActiveWorkspace()

        environmentPopUp.removeAllItems()
        environmentPopUp.addItem(withTitle: "No Environment")
        environmentPopUp.lastItem?.representedObject = nil

        for environment in environments {
            environmentPopUp.addItem(withTitle: environment.name)
            environmentPopUp.lastItem?.representedObject = environment.id
        }

        environmentPopUp.menu?.addItem(.separator())
        environmentPopUp.addItem(withTitle: "Manage Environments…")
        environmentPopUp.lastItem?.tag = Self.manageTag

        if let activeID = libraryController.activeEnvironmentID,
           let index = environments.firstIndex(where: { $0.id == activeID }) {
            environmentPopUp.selectItem(at: index + 1)
        } else {
            environmentPopUp.selectItem(at: 0)
        }
    }

    @objc private func environmentChanged(_ sender: NSPopUpButton) {
        guard !isPopulating, let item = sender.selectedItem else { return }
        if item.tag == Self.manageTag {
            // A command, not a selection — restore the previous choice.
            reloadEnvironments()
            onEditEnvironments?()
            return
        }
        libraryController.setActiveEnvironment(item.representedObject as? UUID)
    }

    @objc private func filterChanged(_ sender: NSSearchField) {
        libraryController.filterText = sender.stringValue
    }

    @objc private func workspaceChanged(_ sender: NSPopUpButton) {
        guard !isPopulating,
              let id = sender.selectedItem?.representedObject as? UUID
        else { return }
        libraryController.setActiveWorkspace(id)
    }
}
