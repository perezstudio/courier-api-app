import AppKit

/// The window's three columns: **sidebar | request settings | results**.
///
/// One split view with three items rather than a split nested inside a content
/// pane, which is how Mail arranges mailboxes, message list, and message. The
/// flat arrangement is what makes the toolbar's tracking separators work:
/// divider 0 sits between the sidebar and the settings column, divider 1
/// between settings and results, and both belong to the same split view.
///
/// Column sizing follows Admiral: the sidebar and results columns are bounded
/// and hold their width (`holdingPriority` above default), while the middle
/// settings column is unbounded and yields (`holdingPriority` at default). That
/// is what makes dragging either divider widen the settings column, and makes
/// the window's growth go to the settings rather than the results.
@MainActor
final class RootSplitViewController: NSSplitViewController {

    private let libraryController: LibraryController
    private unowned let registry: WindowRegistry

    private let sidebarViewController: SidebarViewController
    let session: RequestSessionController

    private var sidebarItem: NSSplitViewItem!
    private var settingsItem: NSSplitViewItem!
    private var resultsItem: NSSplitViewItem!

    /// Fires once the results column has settled, so the toolbar's inspector
    /// button can reflect it.
    var onResultsCollapseChange: ((Bool) -> Void)?

    /// Fires *before* the animation, carrying the direction it is about to go.
    var onResultsCollapseWillChange: ((Bool) -> Void)?

    private var isTogglingResults = false

    /// Forwarded to the sidebar's environment picker.
    var onEditEnvironments: (() -> Void)? {
        didSet { sidebarViewController.onEditEnvironments = onEditEnvironments }
    }

    var isResultsCollapsed: Bool {
        resultsItem?.isCollapsed ?? false
    }

    init(libraryController: LibraryController, registry: WindowRegistry) {
        self.libraryController = libraryController
        self.registry = registry
        self.sidebarViewController = SidebarViewController(
            libraryController: libraryController,
            registry: registry
        )
        self.session = RequestSessionController(
            libraryController: libraryController,
            secretStore: libraryController.secretStore
        )
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
        sidebarItem.holdingPriority = .defaultLow + 1
        // Set per column, not on the window. NSSplitViewController manages the
        // titlebar separator per split item and overrides the window-level
        // style, which is why setting it there had no effect.
        sidebarItem.titlebarSeparatorStyle = .line
        addSplitViewItem(sidebarItem)

        // No maximum, and the lowest holding priority of the three: this is the
        // column that grows.
        // Wrapped so the section picker clears the toolbar; see
        // SafeAreaContainerViewController for why this is not done in layout.
        settingsItem = NSSplitViewItem(
            viewController: SafeAreaContainerViewController(child: session.sections)
        )
        settingsItem.minimumThickness = Theme.Metrics.settingsMinWidth
        settingsItem.holdingPriority = .defaultLow
        // Settings and results start evenly split. Setting the divider by hand
        // after the view appeared did not work: it runs before the window
        // reaches its final size, so the arithmetic was against the wrong
        // width. AppKit applies these at the right point in layout.
        settingsItem.preferredThicknessFraction = 0.4
        settingsItem.titlebarSeparatorStyle = .line
        addSplitViewItem(settingsItem)

        // A plain content item, not `inspectorWithViewController`. An inspector
        // item is built to be a narrow side panel and holds itself near that
        // width, which kept the results column small no matter what fraction it
        // was given. Courier's results are a co-equal column.
        // Wrapped for the same reason as the settings column: with
        // .fullSizeContentView the pane runs under the toolbar, and the code
        // view's line-number ruler drew on top of it.
        resultsItem = NSSplitViewItem(
            viewController: SafeAreaContainerViewController(child: session.responseSections)
        )
        resultsItem.minimumThickness = Theme.Metrics.resultsMinWidth
        resultsItem.canCollapse = true
        // Same holding priority as the settings column. With results held
        // higher, every point of slack went to settings and any position set
        // for the divider was redistributed away on the next layout pass —
        // which is why equal default widths would not stick.
        resultsItem.holdingPriority = .defaultLow
        resultsItem.preferredThicknessFraction = 0.4
        resultsItem.titlebarSeparatorStyle = .line
        addSplitViewItem(resultsItem)

        splitView.autosaveName = "CourierColumns4"
    }

    // MARK: - Content

    func showRequest(_ requestID: UUID?) {
        session.showRequest(requestID)
    }

    func createRequestAtSelection() {
        sidebarViewController.createRequestAtSelection()
    }

    func createFolderAtSelection() {
        sidebarViewController.createFolderAtSelection()
    }

    func flushPendingEdits() {
        session.flushPendingEdits()
    }

    func setResponseMode(_ mode: ResponseViewController.Mode) {
        session.setResponseMode(mode)
    }

    func setResultsSection(_ section: ResultsViewController.Section) {
        session.setResultsSection(section)
    }

    // MARK: - Panes

    func toggleSidebar() {
        toggleSidebar(nil)
    }

    /// Collapses or expands the results pane, sequenced with the toolbar.
    ///
    /// Closing hides the results toolbar items first, then shrinks the pane.
    /// Opening runs the other way round: the pane grows, and the items arrive
    /// once it has settled. Both fall out of one marker — `willChange` sets it
    /// before the animation, the completion handler clears it — because on
    /// expand the pane is still collapsed when the marker clears, so the items
    /// stay away until the settled state lands.
    func toggleResultsPane() {
        // A second click mid-flight would interleave the two directions and
        // leave the tracking separator inserted against a divider that is on
        // its way out.
        guard !isTogglingResults else { return }
        isTogglingResults = true

        let willCollapse = !resultsItem.isCollapsed
        onResultsCollapseWillChange?(willCollapse)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? 0
                : 0.2
            context.allowsImplicitAnimation = true
            resultsItem.animator().isCollapsed = willCollapse
        } completionHandler: { [weak self] in
            guard let self else { return }
            isTogglingResults = false
            onResultsCollapseChange?(isResultsCollapsed)
        }
    }
}
