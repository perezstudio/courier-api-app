import Foundation

/// Working state for the request open in one window.
///
/// Edits land here immediately so the UI stays responsive, and are written to
/// Core Data on a short debounce. Autosave means there is no explicit save
/// command and no dirty state for the user to manage — a deviation from the
/// tab "dirty indicator" the plan mentions in §8.2, which has nothing to show
/// once every edit persists within half a second.
@MainActor
final class EditorController {

    private let libraryController: LibraryController
    private let secretStore: SecretStore

    private(set) var requestID: UUID?
    private(set) var detail: RequestDetail?

    /// Fired after any edit, so dependent views (Variables tab, window title)
    /// can refresh.
    var onChange: (() -> Void)?

    // Working copies, authoritative while a request is open.
    private(set) var method: String = "GET"
    private(set) var url: String = ""
    private(set) var headers: [KeyValueRow] = []
    private(set) var queryParams: [KeyValueRow] = []
    private(set) var bodyType: BodyType = .none
    private(set) var bodyContent: String = ""
    private(set) var auth: AuthConfiguration = .empty

    private var saveTask: Task<Void, Never>?
    private static let autosaveDelay = Duration.milliseconds(400)

    init(libraryController: LibraryController, secretStore: SecretStore) {
        self.libraryController = libraryController
        self.secretStore = secretStore
    }

    // MARK: - Loading

    func load(requestID: UUID?) {
        flushPendingSave()

        guard let requestID else {
            self.requestID = nil
            detail = nil
            return
        }

        self.requestID = requestID
        guard let detail = try? libraryController.requests.detail(for: requestID) else {
            self.detail = nil
            return
        }

        self.detail = detail
        method = detail.method
        url = detail.urlTemplate
        headers = detail.headers
        queryParams = detail.queryParams
        bodyType = BodyType(rawValue: detail.bodyType) ?? .none
        bodyContent = detail.bodyContent ?? ""
        auth = AuthConfiguration.decode(from: detail.authData)
    }

    // MARK: - Edits

    func setMethod(_ newMethod: String) {
        guard method != newMethod else { return }
        method = newMethod
        scheduleSave { [weak self] id, repository in
            guard let self else { return }
            try repository.setMethod(self.method, for: id)
        }
        libraryController.reloadTree()
    }

    /// Updates the URL and re-derives the params table from its query string.
    func setURL(_ newURL: String) {
        guard url != newURL else { return }
        url = newURL

        let parsed = URLQuerySync.parse(newURL)
        queryParams = URLQuerySync.merge(parsed: parsed.rows, into: queryParams)

        scheduleSave { [weak self] id, repository in
            guard let self else { return }
            try repository.setURL(self.url, for: id)
            try repository.replaceQueryParams(self.queryParams, for: id)
        }
    }

    /// Updates the params table and rewrites the URL's query string to match.
    func setQueryParams(_ rows: [KeyValueRow]) {
        queryParams = rows
        let base = URLQuerySync.parse(url).base
        url = URLQuerySync.compose(base: base, rows: rows)

        scheduleSave { [weak self] id, repository in
            guard let self else { return }
            try repository.replaceQueryParams(self.queryParams, for: id)
            try repository.setURL(self.url, for: id)
        }
    }

    func setHeaders(_ rows: [KeyValueRow]) {
        headers = rows
        scheduleSave { [weak self] id, repository in
            guard let self else { return }
            try repository.replaceHeaders(self.headers, for: id)
        }
    }

    func setBodyType(_ type: BodyType) {
        guard bodyType != type else { return }
        bodyType = type
        scheduleSave { [weak self] id, repository in
            guard let self else { return }
            try repository.setBody(
                type: self.bodyType.rawValue,
                content: self.bodyContent,
                for: id
            )
        }
    }

    func setBodyContent(_ content: String) {
        guard bodyContent != content else { return }
        bodyContent = content
        scheduleSave { [weak self] id, repository in
            guard let self else { return }
            try repository.setBody(
                type: self.bodyType.rawValue,
                content: self.bodyContent,
                for: id
            )
        }
    }

    // MARK: - Auth

    func setAuth(_ configuration: AuthConfiguration, secret: String?) {
        var updated = configuration

        if updated.usesSecret {
            let id = updated.secretID ?? UUID()
            updated.secretID = id
            if let secret {
                try? secretStore.set(secret, for: id)
            }
        } else if let existing = updated.secretID {
            // Switching to Inherit or No Auth should not leave a live token in
            // the Keychain with nothing pointing at it.
            try? secretStore.delete(for: existing)
            updated.secretID = nil
        }

        auth = updated
        scheduleSave { [weak self] id, repository in
            guard let self else { return }
            try repository.setAuth(
                type: self.auth.kind.rawValue,
                data: self.auth.encoded(),
                for: id
            )
        }
    }

    /// Reads the stored secret for the current auth configuration.
    func currentAuthSecret() -> String? {
        guard let secretID = auth.secretID else { return nil }
        return try? secretStore.value(for: secretID)
    }

    // MARK: - Saving

    /// Coalesces rapid edits — typing a URL would otherwise write on every
    /// keystroke.
    private func scheduleSave(
        _ work: @escaping (UUID, RequestRepository) throws -> Void
    ) {
        guard let requestID else { return }
        onChange?()

        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled, let self else { return }
            try? work(requestID, self.libraryController.requests)
        }
    }

    /// Writes any pending edit immediately. Called when switching requests, so
    /// a debounce in flight cannot be lost.
    func flushPendingSave() {
        guard let task = saveTask else { return }
        task.cancel()
        saveTask = nil

        guard let requestID else { return }
        let repository = libraryController.requests
        try? repository.setMethod(method, for: requestID)
        try? repository.setURL(url, for: requestID)
        try? repository.replaceQueryParams(queryParams, for: requestID)
        try? repository.replaceHeaders(headers, for: requestID)
        try? repository.setBody(type: bodyType.rawValue, content: bodyContent, for: requestID)
        try? repository.setAuth(type: auth.kind.rawValue, data: auth.encoded(), for: requestID)
    }

    /// Variable names referenced anywhere in the request.
    func referencedVariableNames() -> [String] {
        var names: [String] = []
        var seen = Set<String>()

        func collect(_ text: String) {
            for name in VariableTokenizer.names(in: text) where seen.insert(name).inserted {
                names.append(name)
            }
        }

        collect(url)
        for row in headers where row.isEnabled {
            collect(row.key)
            collect(row.value)
        }
        for row in queryParams where row.isEnabled {
            collect(row.key)
            collect(row.value)
        }
        collect(bodyContent)
        return names
    }
}
