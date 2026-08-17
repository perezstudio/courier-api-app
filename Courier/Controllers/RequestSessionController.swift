import AppKit

/// Owns the editor and response state for one window.
///
/// Has no view of its own. The window is a single three-column split — sidebar
/// | request settings | results — so the editor and response are sibling split
/// items rather than children of a content view, and something has to hold the
/// state that used to live in that content view controller.
@MainActor
final class RequestSessionController {

    private let libraryController: LibraryController
    private let editorController: EditorController
    private let responseController: ResponseController

    let sections: RequestSectionsTabViewController
    let responseSections: ResponseViewController
    private let history = RunHistoryViewController()

    private var requestID: UUID?
    private var libraryObservation: ObservationToken?

    // Reported up to the window controller, which owns the toolbar.
    var onRequestChange: ((String, String, Bool) -> Void)?
    var onSendingChange: ((Bool) -> Void)?
    var onUnresolvedVariablesChange: ((Set<String>) -> Void)?

    init(libraryController: LibraryController, secretStore: SecretStore) {
        self.libraryController = libraryController

        let editorController = EditorController(
            libraryController: libraryController,
            secretStore: secretStore
        )
        self.editorController = editorController
        self.responseController = ResponseController(libraryController: libraryController)
        self.sections = RequestSectionsTabViewController(editorController: editorController)
        self.responseSections = ResponseViewController(historyViewController: history)

        wire()
    }

    private func wire() {
        sections.variableContextProvider = { [weak self] in
            self?.libraryController.makeVariableContext() ?? VariableResolver.Context()
        }
        sections.secretVariableNamesProvider = { [weak self] in
            self?.secretVariableNames() ?? []
        }

        editorController.onChange = { [weak self] in
            self?.refreshVariableState()
        }

        // Changing the active environment has to re-resolve everything, and it
        // happens outside this controller.
        libraryObservation = libraryController.observe { [weak self] in
            self?.refreshVariableState()
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

    // MARK: - Content

    func showRequest(_ requestID: UUID?) {
        // Switching requests must not leave the previous one's response on
        // screen, or cancel silently.
        responseController.cancel()
        responseSections.showIdle()

        self.requestID = requestID
        editorController.load(requestID: requestID)

        sections.setHasRequest(requestID != nil)
        if requestID != nil {
            sections.reload()
        }
        reloadHistory()
        refreshVariableState()
        onRequestChange?(editorController.method, editorController.url, requestID != nil)
    }

    func flushPendingEdits() {
        editorController.flushPendingSave()
    }

    func setResponseMode(_ mode: ResponseViewController.Mode) {
        responseSections.setMode(mode)
    }

    // MARK: - Toolbar-driven edits

    func setMethod(_ method: String) {
        editorController.setMethod(method)
    }

    func setURL(_ url: String) {
        editorController.setURL(url)
        // Typing in the URL rewrites the params table, but not the URL field
        // itself — reloading it would fight the insertion point.
        sections.refreshParams()
        refreshVariableState()
    }

    func sendOrCancel() {
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
            context: libraryController.makeVariableContext()
        )
    }

    // MARK: - State

    private func applyResponseState(_ state: ResponseController.State) {
        switch state {
        case .idle: responseSections.showIdle()
        case .sending: responseSections.showSending()
        case .finished(let result): responseSections.showResult(result)
        case .failed(let message): responseSections.showError(message)
        }
        onSendingChange?(responseController.isSending)
    }

    private func refreshVariableState() {
        sections.refreshDerived()
        onUnresolvedVariablesChange?(sections.unresolvedNames())
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

    /// Names whose winning binding is a secret, so the Variables tab can mask
    /// them rather than printing a token on screen.
    private func secretVariableNames() -> Set<String> {
        var names: Set<String> = []
        for environment in libraryController.environmentsForActiveWorkspace()
        where environment.id == libraryController.activeEnvironmentID {
            for variable in environment.variables where variable.isSecret && variable.isEnabled {
                names.insert(variable.key)
            }
        }
        if let workspaceID = libraryController.activeWorkspaceID,
           let collection = try? libraryController.environments.collectionVariables(
               forWorkspace: workspaceID
           ) {
            for variable in collection where variable.isSecret && variable.isEnabled {
                names.insert(variable.key)
            }
        }
        return names
    }
}
