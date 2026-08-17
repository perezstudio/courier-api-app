import AppKit

/// Sidebar | content. The sidebar item is created with
/// `NSSplitViewItem(sidebarWithViewController:)` so the system supplies the
/// material, full-height behavior under the titlebar, and the collapse
/// animation — none of that is app code.
@MainActor
final class RootSplitViewController: NSSplitViewController {

    private let libraryController: LibraryController
    private unowned let registry: WindowRegistry

    private let sidebarViewController: SidebarViewController
    private let contentViewController: ContentViewController

    private var sidebarItem: NSSplitViewItem!

    init(libraryController: LibraryController, registry: WindowRegistry) {
        self.libraryController = libraryController
        self.registry = registry
        self.sidebarViewController = SidebarViewController(
            libraryController: libraryController,
            registry: registry
        )
        self.contentViewController = ContentViewController(libraryController: libraryController)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = Theme.Metrics.sidebarMinWidth
        sidebarItem.maximumThickness = Theme.Metrics.sidebarMaxWidth
        sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)

        let contentItem = NSSplitViewItem(viewController: contentViewController)
        contentItem.minimumThickness = Theme.Metrics.editorMinWidth + Theme.Metrics.responseMinWidth
        addSplitViewItem(contentItem)

        splitView.autosaveName = "CourierRootSplit"
    }

    func showRequest(_ requestID: UUID?) {
        contentViewController.showRequest(requestID)
    }

    func createRequestAtSelection() {
        sidebarViewController.createRequestAtSelection()
    }

    func createFolderAtSelection() {
        sidebarViewController.createFolderAtSelection()
    }

    func toggleSidebar() {
        toggleSidebar(nil)
    }

    func toggleResponsePane() {
        contentViewController.toggleResponsePane()
    }
}
