import AppKit

/// Workspace popup above the collection tree.
@MainActor
final class SidebarViewController: NSViewController {

    private let libraryController: LibraryController
    private unowned let registry: WindowRegistry

    private let workspacePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let outlineController: CollectionOutlineViewController
    private var observation: ObservationToken?

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

        addChild(outlineController)
        let tree = outlineController.view
        tree.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(workspacePopUp)
        view.addSubview(tree)

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

            tree.topAnchor.constraint(
                equalTo: workspacePopUp.bottomAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            tree.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tree.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tree.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
    }

    @objc private func workspaceChanged(_ sender: NSPopUpButton) {
        guard !isPopulating,
              let id = sender.selectedItem?.representedObject as? UUID
        else { return }
        libraryController.setActiveWorkspace(id)
    }
}
