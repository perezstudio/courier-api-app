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

        addSection(paramsTable, label: "Params")
        addSection(headersTable, label: "Headers")
        addSection(bodyEditor, label: "Body")
        addSection(authEditor, label: "Auth")
        addSection(variablesViewController, label: "Variables")
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
        variablesViewController.setNames(editorController.referencedVariableNames())
    }

    /// Refreshes only what an edit elsewhere can invalidate, without disturbing
    /// a field the user is typing in.
    func refreshDerived() {
        variablesViewController.setNames(editorController.referencedVariableNames())
    }

    func refreshParams() {
        paramsTable.setRows(editorController.queryParams)
    }
}

/// Variables referenced by the request.
///
/// Phase 6 adds resolution — which environment supplies each value and what it
/// resolves to. For now it lists what the request references, which is already
/// enough to spot a typo in a placeholder name.
@MainActor
final class VariablesViewController: NSViewController {

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyState = EmptyStateView(
        symbolName: "curlybraces",
        title: "No Variables",
        subtitle: "Reference one with {{name}} in the URL, headers, or body."
    )

    private var names: [String] = []

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

    func setNames(_ names: [String]) {
        self.names = names
        tableView.reloadData()
        emptyState.isHidden = !names.isEmpty
        scrollView.isHidden = names.isEmpty
    }
}

extension VariablesViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        names.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, names.indices.contains(row) else { return nil }

        if tableColumn.identifier.rawValue == "name" {
            let field = NSTextField(labelWithString: "{{\(names[row])}}")
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.textColor = .systemPurple
            return field
        }

        let field = NSTextField(labelWithString: "Not resolved yet")
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .tertiaryLabelColor
        return field
    }
}
