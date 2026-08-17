import AppKit

/// The non-sidebar half of the window: URL bar across the top, editor/response
/// split below. The URL bar spans the full width so it reads as belonging to
/// both panes (REQUIREMENTS.md §8.3).
@MainActor
final class ContentViewController: NSViewController {

    private let libraryController: LibraryController
    private let urlBarPlaceholder = NSView()
    private let editorResponseSplit: EditorResponseSplitViewController
    private let emptyState: EmptyStateView

    private var requestID: UUID?

    init(libraryController: LibraryController) {
        self.libraryController = libraryController
        self.editorResponseSplit = EditorResponseSplitViewController()
        self.emptyState = EmptyStateView(
            symbolName: "square.on.square.dashed",
            title: "No Request Open",
            subtitle: "Create a request, or open one from the sidebar."
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
        setupURLBar()
        setupSplit()
        setupEmptyState()
        updateVisibility()
    }

    // MARK: - Setup

    private func setupURLBar() {
        // Phase 4 replaces this with the real URL bar: method popup, URL field
        // with {{variable}} highlighting, and the Send button.
        urlBarPlaceholder.wantsLayer = true
        urlBarPlaceholder.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(urlBarPlaceholder)
        urlBarPlaceholder.addSubview(separator)

        // Safe area, not the view: the content pane also runs under the
        // titlebar when the toolbar is unified.
        NSLayoutConstraint.activate([
            urlBarPlaceholder.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            urlBarPlaceholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            urlBarPlaceholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            urlBarPlaceholder.heightAnchor.constraint(equalToConstant: Theme.Metrics.urlBarHeight),

            separator.leadingAnchor.constraint(equalTo: urlBarPlaceholder.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: urlBarPlaceholder.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: urlBarPlaceholder.bottomAnchor),
        ])
    }

    private func setupSplit() {
        addChild(editorResponseSplit)
        let splitView = editorResponseSplit.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: urlBarPlaceholder.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: view.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Content

    func showRequest(_ requestID: UUID?) {
        self.requestID = requestID
        updateVisibility()
    }

    private func updateVisibility() {
        let hasRequest = requestID != nil
        emptyState.isHidden = hasRequest
        urlBarPlaceholder.isHidden = !hasRequest
        editorResponseSplit.view.isHidden = !hasRequest
    }

    func toggleResponsePane() {
        editorResponseSplit.toggleResponsePane()
    }
}
