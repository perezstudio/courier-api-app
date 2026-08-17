import AppKit

/// A horizontally paged workspace switcher over the collection tree.
///
/// One page per workspace, each rendering its own tree, so swiping shows the
/// destination workspace's requests sliding in rather than a pane that fills
/// after the fact. Page dots in the footer carry the state a swipe leaves no
/// trace of: how many workspaces there are, and which one is showing.
@MainActor
final class SidebarViewController: NSViewController {

    private let libraryController: LibraryController
    private unowned let registry: WindowRegistry

    private let pagerScrollView = NSScrollView()
    private let pagerStack = NSStackView()
    private var pages: [WorkspacePage] = []

    private let dotsView = WorkspaceDotsView()

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
    /// repopulated, which would reselect the environment on every reload.
    private var isPopulating = false

    /// Suppresses the snap handler while the pager is being driven
    /// programmatically, so an animated scroll to a page cannot be read back as
    /// the user having swiped to it.
    private var isScrollingProgrammatically = false

    private struct WorkspacePage {
        let workspaceID: UUID
        let controller: CollectionOutlineViewController
        let container: NSView
        let title: NSTextField
    }

    init(libraryController: LibraryController, registry: WindowRegistry) {
        self.libraryController = libraryController
        self.registry = registry
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
            self?.reload()
        }
        reload()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Page width tracks the sidebar, which the user can drag. Re-align on
        // every layout pass or a resize leaves the active page part-scrolled.
        scrollToActiveWorkspace(animated: false)
    }

    private func setupLayout() {
        pagerStack.translatesAutoresizingMaskIntoConstraints = false
        pagerStack.orientation = .horizontal
        pagerStack.spacing = 0
        pagerStack.distribution = .fillEqually

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(pagerStack)

        pagerScrollView.translatesAutoresizingMaskIntoConstraints = false
        pagerScrollView.documentView = document
        pagerScrollView.hasHorizontalScroller = false
        pagerScrollView.hasVerticalScroller = false
        // The pages scroll vertically themselves; letting the pager bounce
        // vertically too would fight them.
        pagerScrollView.verticalScrollElasticity = .none
        pagerScrollView.drawsBackground = false
        pagerScrollView.automaticallyAdjustsContentInsets = false

        // A swipe is only committed once it settles. Switching workspaces
        // mid-gesture would reload the request editor on every frame the finger
        // crosses a page boundary.
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: pagerScrollView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.snapToNearestPage() }
        }

        environmentPopUp.translatesAutoresizingMaskIntoConstraints = false
        environmentPopUp.bezelStyle = .rounded
        environmentPopUp.controlSize = .small
        environmentPopUp.target = self
        environmentPopUp.action = #selector(environmentChanged(_:))
        environmentPopUp.setAccessibilityLabel("Active environment")

        dotsView.onSelect = { [weak self] id in
            self?.selectWorkspace(id)
        }
        dotsView.onAdd = { [weak self] in
            self?.addWorkspace()
        }

        view.addSubview(pagerScrollView)
        view.addSubview(dotsView)
        view.addSubview(environmentPopUp)

        // Pinned to the safe area: the sidebar runs full height under the
        // titlebar, so view.topAnchor would put the pages behind the traffic
        // lights.
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            document.heightAnchor.constraint(equalTo: pagerScrollView.heightAnchor),
            pagerStack.topAnchor.constraint(equalTo: document.topAnchor),
            pagerStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            pagerStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            pagerStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),

            pagerScrollView.topAnchor.constraint(equalTo: safe.topAnchor),
            pagerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerScrollView.bottomAnchor.constraint(
                equalTo: dotsView.topAnchor,
                constant: -Theme.Metrics.tightPadding
            ),

            dotsView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dotsView.bottomAnchor.constraint(
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
                equalTo: safe.bottomAnchor,
                constant: -Theme.Metrics.tightPadding
            ),
        ])
    }

    // MARK: - Creation
    //
    // Forwarded from the File menu so menu and context-menu creation share one
    // insertion rule. Routed to the visible page, so a new request lands in the
    // workspace the user is looking at.

    func createRequestAtSelection() {
        activePage?.controller.createRequestAtSelection()
    }

    func createFolderAtSelection() {
        activePage?.controller.createFolderAtSelection()
    }

    private var activePage: WorkspacePage? {
        guard let activeID = libraryController.activeWorkspaceID else { return pages.first }
        return pages.first { $0.workspaceID == activeID } ?? pages.first
    }

    // MARK: - Workspaces

    private func reload() {
        rebuildPagesIfNeeded()
        for page in pages {
            page.title.stringValue = Self.pageTitle(
                for: page.workspaceID,
                in: libraryController.workspaces
            )
        }
        dotsView.update(
            workspaces: libraryController.workspaces,
            activeID: libraryController.activeWorkspaceID
        )
        scrollToActiveWorkspace(animated: false)
        reloadEnvironments()
    }

    /// Rebuilds the pages only when the set of workspaces changes.
    ///
    /// The library notifies on every mutation, a request rename included.
    /// Rebuilding on those would tear down each page's outline view and take
    /// its expansion and selection with it.
    private func rebuildPagesIfNeeded() {
        let ids = libraryController.workspaces.map(\.id)
        guard ids != pages.map(\.workspaceID) else { return }

        for page in pages {
            page.controller.removeFromParent()
            pagerStack.removeArrangedSubview(page.container)
            page.container.removeFromSuperview()
        }

        pages = libraryController.workspaces.map { workspace in
            let controller = CollectionOutlineViewController(
                libraryController: libraryController,
                workspaceID: workspace.id,
                registry: registry
            )
            addChild(controller)
            controller.attachPager(pagerScrollView)

            let title = NSTextField(labelWithString: "")
            title.translatesAutoresizingMaskIntoConstraints = false
            title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            title.textColor = .secondaryLabelColor
            title.lineBreakMode = .byTruncatingTail
            // Lets the header truncate rather than hold the sidebar open at
            // the width of its own text. A label resists compression at 750 by
            // default, which would put a floor under the sidebar set by the
            // longest workspace name.
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            let tree = controller.view
            tree.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(title)
            container.addSubview(tree)
            // Added to the stack *before* the constraints below are activated.
            // One of them ties the page's width to the pager, and a constraint
            // between two views with no common ancestor throws — which AppKit
            // swallows, leaving a running app with no window at all.
            pagerStack.addArrangedSubview(container)

            NSLayoutConstraint.activate([
                title.topAnchor.constraint(
                    equalTo: container.topAnchor,
                    constant: Theme.Metrics.tightPadding
                ),
                title.leadingAnchor.constraint(
                    equalTo: container.leadingAnchor,
                    constant: Theme.Metrics.tightPadding
                ),
                title.trailingAnchor.constraint(
                    equalTo: container.trailingAnchor,
                    constant: -Theme.Metrics.tightPadding
                ),

                tree.topAnchor.constraint(
                    equalTo: title.bottomAnchor,
                    constant: Theme.Metrics.tightPadding
                ),
                tree.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                tree.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                tree.bottomAnchor.constraint(equalTo: container.bottomAnchor),

                // Every page is exactly the sidebar's width, which is what
                // makes a page index out of a scroll offset.
                container.widthAnchor.constraint(equalTo: pagerScrollView.widthAnchor),
            ])

            return WorkspacePage(
                workspaceID: workspace.id,
                controller: controller,
                container: container,
                title: title
            )
        }
    }

    private static func pageTitle(for id: UUID, in workspaces: [WorkspaceSnapshot]) -> String {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return "" }
        let count = workspace.requestCount == 1
            ? "1 request"
            : "\(workspace.requestCount) requests"
        return "\(workspace.name.uppercased()) — \(count)"
    }

    // MARK: - Paging

    private func snapToNearestPage() {
        guard !isScrollingProgrammatically else { return }
        guard let index = PagerGeometry.pageIndex(
            offsetX: pagerScrollView.contentView.bounds.origin.x,
            pageWidth: pagerScrollView.bounds.width,
            pageCount: pages.count
        ) else { return }

        let target = pages[index].workspaceID
        if target != libraryController.activeWorkspaceID {
            libraryController.setActiveWorkspace(target)
        }
        scrollToActiveWorkspace(animated: true)
    }

    private func selectWorkspace(_ id: UUID) {
        guard id != libraryController.activeWorkspaceID else { return }
        libraryController.setActiveWorkspace(id)
        scrollToActiveWorkspace(animated: true)
    }

    private func addWorkspace() {
        guard let workspace = libraryController.createWorkspace(name: "New Workspace") else {
            return
        }
        libraryController.setActiveWorkspace(workspace.id)
        scrollToActiveWorkspace(animated: true)
    }

    private func scrollToActiveWorkspace(animated: Bool) {
        guard
            let activeID = libraryController.activeWorkspaceID,
            let index = pages.firstIndex(where: { $0.workspaceID == activeID })
        else { return }

        let width = pagerScrollView.bounds.width
        guard width > 0 else { return }
        let target = NSPoint(x: PagerGeometry.offset(forPage: index, pageWidth: width), y: 0)
        // Already there — bail out rather than re-animate, which would fight a
        // layout pass that runs mid-animation.
        guard abs(pagerScrollView.contentView.bounds.origin.x - target.x) > 0.5 else { return }

        isScrollingProgrammatically = true
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? 0
                    : 0.25
                context.allowsImplicitAnimation = true
                pagerScrollView.contentView.animator().setBoundsOrigin(target)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.isScrollingProgrammatically = false }
            }
        } else {
            pagerScrollView.contentView.setBoundsOrigin(target)
            isScrollingProgrammatically = false
        }
        pagerScrollView.reflectScrolledClipView(pagerScrollView.contentView)
    }

    // MARK: - Environments

    private func reloadEnvironments() {
        isPopulating = true
        defer { isPopulating = false }

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
}

/// Top-left origin, so the pager's pages lay out left to right from the top
/// rather than growing upward from the bottom as an unflipped view would.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
