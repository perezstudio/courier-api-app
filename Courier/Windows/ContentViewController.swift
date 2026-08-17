import AppKit

/// The non-sidebar half of the window: URL bar across the top, editor/response
/// split below. The URL bar spans the full width so it reads as belonging to
/// both panes (REQUIREMENTS.md §8.3).
@MainActor
final class ContentViewController: NSViewController {

    private let libraryController: LibraryController
    private let editorController: EditorController
    private let responseController: ResponseController

    private let urlBar = URLBarViewController()
    private let editorResponseSplit: EditorResponseSplitViewController
    private let sections: RequestSectionsTabViewController
    private let responseSections: ResponseSectionsTabViewController
    private let history = RunHistoryViewController()
    private let emptyState: EmptyStateView

    private var requestID: UUID?

    init(libraryController: LibraryController, secretStore: SecretStore) {
        self.libraryController = libraryController
        let editorController = EditorController(
            libraryController: libraryController,
            secretStore: secretStore
        )
        self.editorController = editorController
        self.responseController = ResponseController(libraryController: libraryController)
        self.sections = RequestSectionsTabViewController(editorController: editorController)
        self.responseSections = ResponseSectionsTabViewController(
            historyViewController: history
        )
        self.editorResponseSplit = EditorResponseSplitViewController(
            editor: sections,
            response: responseSections
        )
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
        wireCallbacks()
        updateVisibility()
    }

    // MARK: - Setup

    private func setupURLBar() {
        addChild(urlBar)
        let bar = urlBar.view
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        // Safe area, not the view: the content pane runs under the titlebar
        // when the toolbar is unified.
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: Theme.Metrics.urlBarHeight),
        ])
    }

    private func setupSplit() {
        addChild(editorResponseSplit)
        let splitView = editorResponseSplit.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: urlBar.view.bottomAnchor),
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

    private func wireCallbacks() {
        urlBar.onMethodChange = { [weak self] method in
            self?.editorController.setMethod(method)
        }
        urlBar.onURLChange = { [weak self] url in
            guard let self else { return }
            self.editorController.setURL(url)
            // Typing in the URL rewrites the params table, but not the URL
            // field itself — reloading it would fight the insertion point.
            self.sections.refreshParams()
        }
        urlBar.onSend = { [weak self] in
            self?.sendRequest()
        }

        editorController.onChange = { [weak self] in
            self?.sections.refreshDerived()
        }

        responseController.onStateChange = { [weak self] state in
            self?.applyResponseState(state)
        }
        responseController.onHistoryChange = { [weak self] in
            self?.reloadHistory()
        }

        history.onSelect = { [weak self] runID in
            self?.showStoredRun(runID)
        }
        history.onToggleStar = { [weak self] runID, isStarred in
            self?.responseController.setStarred(isStarred, runID: runID)
        }
    }

    private func applyResponseState(_ state: ResponseController.State) {
        switch state {
        case .idle:
            responseSections.showIdle()
        case .sending:
            responseSections.showSending()
        case .finished(let result):
            responseSections.showResult(result)
        case .failed(let message):
            responseSections.showError(message)
        }

        // The Send button becomes Cancel while a request is in flight, which is
        // the only affordance for stopping one (§8.3).
        urlBar.setSending(responseController.isSending)
    }

    private func reloadHistory() {
        guard let requestID else {
            history.setRuns([])
            return
        }
        history.setRuns(responseController.runs(forRequest: requestID))
    }

    private func showStoredRun(_ runID: UUID) {
        guard let stored = responseController.storedRun(id: runID) else { return }
        responseSections.showStoredRun(
            summary: stored.summary,
            body: stored.body,
            headersJSON: stored.headers,
            timingJSON: stored.timing
        )
    }

    // MARK: - Content

    func showRequest(_ requestID: UUID?) {
        // Switching requests must not leave the previous one's response on
        // screen, or cancel silently.
        responseController.cancel()
        responseSections.showIdle()

        self.requestID = requestID
        editorController.load(requestID: requestID)

        if requestID != nil {
            urlBar.configure(method: editorController.method, url: editorController.url)
            sections.reload()
        }
        reloadHistory()
        updateVisibility()
    }

    /// Writes any debounced edit immediately — called when the window is
    /// closing or the request is changing out from under the editor.
    func flushPendingEdits() {
        editorController.flushPendingSave()
    }

    private func updateVisibility() {
        let hasRequest = requestID != nil
        emptyState.isHidden = hasRequest
        urlBar.view.isHidden = !hasRequest
        editorResponseSplit.view.isHidden = !hasRequest
    }

    func toggleResponsePane() {
        editorResponseSplit.toggleResponsePane()
    }

    private func sendRequest() {
        guard let requestID else { return }

        if responseController.isSending {
            responseController.cancel()
            return
        }

        // Flush first: an in-flight autosave debounce would otherwise mean the
        // request that goes out differs from the one that gets stored.
        editorController.flushPendingSave()

        let input = RequestBuilder.Input(
            method: editorController.method,
            urlTemplate: editorController.url,
            headers: editorController.headers,
            queryParams: editorController.queryParams,
            bodyType: editorController.bodyType,
            bodyContent: editorController.bodyContent,
            auth: editorController.auth,
            authSecret: editorController.currentAuthSecret(),
            timeout: editorController.detail?.timeout ?? 30,
            followRedirects: editorController.detail?.followRedirects ?? true
        )

        responseController.send(
            input: input,
            requestID: requestID,
            context: responseController.makeVariableContext()
        )
    }
}
