import AppKit

/// Params · Headers · Body · Auth · Variables.
///
/// `NSTabViewController` with `.segmentedControlOnTop` is the stock control for
/// switching content panes (REQUIREMENTS.md §7.3).
@MainActor
final class RequestSectionsTabViewController: NSTabViewController {

    private let editorController: EditorController

    private let paramsTable = KeyValueTableViewController()
    private let headersTable = KeyValueTableViewController()
    private let bodyEditor = BodyEditorViewController()
    private let authEditor = AuthEditorViewController()
    private let variablesViewController = VariablesViewController()

    /// Shown over the sections when no request is open. The results column has
    /// its own empty state, so each column explains itself.
    private let emptyState = EmptyStateView(
        symbolName: "square.on.square.dashed",
        title: "No Request Open",
        subtitle: "Create a request, or open one from the sidebar."
    )

    init(editorController: EditorController) {
        self.editorController = editorController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .segmentedControlOnTop
        transitionOptions = []

        headersTable.keySuggestions = CommonHeaders.requestHeaders

        wireCallbacks()

        setupEmptyState()

        addSection(paramsTable, label: "Params")
        addSection(headersTable, label: "Headers")
        addSection(bodyEditor, label: "Body")
        addSection(authEditor, label: "Auth")
        addSection(variablesViewController, label: "Variables")
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

    /// Covers the section tabs when nothing is open, so the column does not
    /// show an editable-looking form with no request behind it.
    func setHasRequest(_ hasRequest: Bool) {
        loadViewIfNeeded()
        emptyState.isHidden = hasRequest
        tabView.isHidden = !hasRequest
    }

    private func addSection(_ controller: NSViewController, label: String) {
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        addTabViewItem(item)
    }

    private func wireCallbacks() {
        paramsTable.onChange = { [weak self] rows in
            self?.editorController.setQueryParams(rows)
        }
        headersTable.onChange = { [weak self] rows in
            self?.editorController.setHeaders(rows)
        }
        bodyEditor.onTypeChange = { [weak self] type in
            self?.editorController.setBodyType(type)
        }
        bodyEditor.onContentChange = { [weak self] content in
            self?.editorController.setBodyContent(content)
        }
        bodyEditor.onFormRowsChange = { [weak self] rows in
            // Form-data and URL-encoded bodies are stored as an encoded query
            // string, so the same rows round-trip through one field.
            self?.editorController.setBodyContent(
                URLQuerySync.compose(base: "", rows: rows).trimmingCharacters(in: ["?"])
            )
        }
        authEditor.onChange = { [weak self] configuration, secret in
            self?.editorController.setAuth(configuration, secret: secret)
        }
    }

    // MARK: - Content

    func reload() {
        paramsTable.setRows(editorController.queryParams)
        headersTable.setRows(editorController.headers)

        let formRows = URLQuerySync.parseQuery(editorController.bodyContent)
        bodyEditor.configure(
            type: editorController.bodyType,
            content: editorController.bodyContent,
            formRows: formRows
        )
        authEditor.configure(editorController.auth, secret: editorController.currentAuthSecret())
        refreshDerived()
    }

    /// Refreshes only what an edit elsewhere can invalidate, without disturbing
    /// a field the user is typing in.
    func refreshDerived() {
        variablesViewController.setEntries(resolvedEntries())
    }

    /// Which variables the request references, and what each resolves to right
    /// now. Uses the same context a send would, so the preview cannot drift
    /// from what actually goes out.
    func resolvedEntries() -> [VariablesViewController.Entry] {
        let context = variableContextProvider?() ?? VariableResolver.Context()
        let secretNames = secretVariableNamesProvider?() ?? []

        return editorController.referencedVariableNames().map { name in
            let binding = context.binding(for: name)
            return VariablesViewController.Entry(
                name: name,
                value: binding?.value,
                scope: binding?.scope,
                isSecret: secretNames.contains(name)
            )
        }
    }

    /// Unresolved names, for the URL bar's warning tint.
    func unresolvedNames() -> Set<String> {
        Set(resolvedEntries().filter { !$0.isResolved }.map(\.name))
    }

    /// Supplied by the owner so this controller does not reach into the
    /// library itself.
    var variableContextProvider: (() -> VariableResolver.Context)?
    var secretVariableNamesProvider: (() -> Set<String>)?

    func refreshParams() {
        paramsTable.setRows(editorController.queryParams)
    }
}

/// Variables referenced by the request, with what each resolves to and from
/// which scope.
@MainActor
final class VariablesViewController: NSViewController {

    struct Entry {
        let name: String
        let value: String?
        let scope: VariableResolver.Scope?
        /// Secret values are shown as a placeholder, never in the clear.
        let isSecret: Bool

        var isResolved: Bool { value != nil }
    }

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyState = EmptyStateView(
        symbolName: "curlybraces",
        title: "No Variables",
        subtitle: "Reference one with {{name}} in the URL, headers, or body."
    )

    private var entries: [Entry] = []

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Variable"
        tableView.addTableColumn(nameColumn)

        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.title = "Resolves To"
        tableView.addTableColumn(valueColumn)

        let scopeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("scope"))
        scopeColumn.title = "Scope"
        scopeColumn.width = 100
        tableView.addTableColumn(scopeColumn)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyState.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(emptyState)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: view.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func setEntries(_ entries: [Entry]) {
        self.entries = entries
        tableView.reloadData()
        emptyState.isHidden = !entries.isEmpty
        scrollView.isHidden = entries.isEmpty
    }
}

extension VariablesViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, entries.indices.contains(row) else { return nil }
        let entry = entries[row]

        switch tableColumn.identifier.rawValue {
        case "name":
            let field = NSTextField(labelWithString: "{{\(entry.name)}}")
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            // Same colors as the URL bar: purple resolves, orange doesn't.
            field.textColor = entry.isResolved ? .systemPurple : .systemOrange
            return field

        case "value":
            let text: String
            let color: NSColor
            if entry.isSecret {
                text = "••••••••"
                color = .secondaryLabelColor
            } else if let value = entry.value {
                text = value.isEmpty ? "(empty)" : value
                color = value.isEmpty ? .tertiaryLabelColor : .labelColor
            } else {
                text = "Unresolved"
                color = .systemOrange
            }
            let field = NSTextField(labelWithString: text)
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.textColor = color
            field.lineBreakMode = .byTruncatingTail
            field.isSelectable = !entry.isSecret
            field.toolTip = entry.isSecret ? "Stored in your Keychain" : entry.value
            return field

        case "scope":
            let field = NSTextField(labelWithString: entry.scope?.displayName ?? "—")
            field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            field.textColor = .secondaryLabelColor
            return field

        default:
            return nil
        }
    }
}
