import AppKit

/// Phase 2 sidebar.
///
/// Phase 3 replaces the body with the source-list `NSOutlineView`. What is here
/// now exists to *verify the shared-state design*: every window has its own
/// sidebar, and this one renders values owned by the app-wide
/// `LibraryController`. Create a request in one tab and every other tab's
/// sidebar updates — which is the behavior §11 flags as the top risk of using
/// native window tabs.
@MainActor
final class SidebarViewController: NSViewController {

    private let libraryController: LibraryController
    private unowned let registry: WindowRegistry

    private let workspaceLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let filterLabel = NSTextField(labelWithString: "")
    private let requestStack = NSStackView()
    private var observation: ObservationToken?

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

    private func setupLayout() {
        workspaceLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        filterLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        filterLabel.textColor = .tertiaryLabelColor

        requestStack.orientation = .vertical
        requestStack.alignment = .leading
        requestStack.spacing = 2

        let header = NSStackView(views: [workspaceLabel, countLabel, filterLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2

        // A spacer that soaks up leftover height, so rows stay pinned to the top.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        let root = NSStackView(views: [header, requestStack, spacer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = Theme.Metrics.tightPadding
        root.translatesAutoresizingMaskIntoConstraints = false
        root.edgeInsets = NSEdgeInsets(
            top: Theme.Metrics.tightPadding,
            left: Theme.Metrics.standardPadding,
            bottom: Theme.Metrics.tightPadding,
            right: Theme.Metrics.standardPadding
        )

        view.addSubview(root)

        // Pinned to the safe area, not the view: the sidebar runs full height
        // under the titlebar, so view.topAnchor puts content beneath the
        // traffic lights.
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: safe.topAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
        ])
    }

    // MARK: - Rendering

    private func reload() {
        workspaceLabel.stringValue = libraryController.activeWorkspace?.name ?? "No Workspace"

        let count = libraryController.activeWorkspace?.requestCount ?? 0
        countLabel.stringValue = count == 1 ? "1 request" : "\(count) requests"

        let filter = libraryController.filterText
        filterLabel.stringValue = filter.isEmpty ? "" : "Filter: \(filter)"
        filterLabel.isHidden = filter.isEmpty

        renderRequests()
    }

    private func renderRequests() {
        for subview in requestStack.arrangedSubviews {
            requestStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let filter = libraryController.filterText.lowercased()
        for node in libraryController.tree {
            guard case .request(let request) = node else { continue }
            if !filter.isEmpty, !request.name.lowercased().contains(filter) { continue }
            requestStack.addArrangedSubview(makeRow(for: request))
        }
    }

    private func makeRow(for request: RequestSummary) -> NSView {
        let button = NSButton(title: "\(request.method)  \(request.name)", target: self, action: #selector(rowClicked(_:)))
        button.bezelStyle = .inline
        button.isBordered = false
        button.alignment = .left
        button.contentTintColor = Theme.color(forMethod: request.method)
        button.identifier = NSUserInterfaceItemIdentifier(request.id.uuidString)
        return button
    }

    @objc private func rowClicked(_ sender: NSButton) {
        guard
            let raw = sender.identifier?.rawValue,
            let id = UUID(uuidString: raw)
        else { return }

        // Finder/Safari behavior: plain click navigates this tab, Command-click
        // opens a new one. See REQUIREMENTS.md §7.2.
        if NSEvent.modifierFlags.contains(.command) {
            registry.openInNewTab(requestID: id)
        } else {
            registry.navigateCurrentTab(to: id)
        }
    }
}
