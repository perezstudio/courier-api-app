import AppKit

/// Read-only two-column table. Used for response headers.
@MainActor
final class PairTableViewController: NSViewController {

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyState: EmptyStateView

    private let firstColumnTitle: String
    private let secondColumnTitle: String
    private var pairs: [(key: String, value: String)] = []

    init(firstColumn: String, secondColumn: String, emptyTitle: String = "Nothing to Show") {
        self.firstColumnTitle = firstColumn
        self.secondColumnTitle = secondColumn
        self.emptyState = EmptyStateView(symbolName: "tag", title: emptyTitle)
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

        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let keyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        keyColumn.title = firstColumnTitle
        keyColumn.minWidth = 120
        tableView.addTableColumn(keyColumn)

        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.title = secondColumnTitle
        valueColumn.minWidth = 160
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

    func setPairs(_ pairs: [(key: String, value: String)]) {
        self.pairs = pairs
        tableView.reloadData()
        emptyState.isHidden = !pairs.isEmpty
        scrollView.isHidden = pairs.isEmpty
    }
}

extension PairTableViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        pairs.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, pairs.indices.contains(row) else { return nil }
        let pair = pairs[row]

        let isKey = tableColumn.identifier.rawValue == "key"
        // Selectable so a header value can be copied — the common reason to
        // look at this table at all.
        let field = NSTextField(labelWithString: isKey ? pair.key : pair.value)
        field.font = .monospacedSystemFont(ofSize: 11, weight: isKey ? .medium : .regular)
        field.textColor = isKey ? .labelColor : .secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        field.isSelectable = true
        field.toolTip = isKey ? pair.key : pair.value
        return field
    }
}

/// Cookies parsed from `Set-Cookie`.
@MainActor
final class CookiesViewController: NSViewController {

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyState = EmptyStateView(
        symbolName: "circle.grid.2x2",
        title: "No Cookies",
        subtitle: "This response set no cookies."
    )

    private var cookies: [ResponseFormatter.Cookie] = []

    private enum Column: String, CaseIterable {
        case name = "Name"
        case value = "Value"
        case domain = "Domain"
        case path = "Path"
        case expires = "Expires"
        case flags = "Flags"
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22

        for column in Column.allCases {
            let tableColumn = NSTableColumn(
                identifier: NSUserInterfaceItemIdentifier(column.rawValue)
            )
            tableColumn.title = column.rawValue
            tableColumn.minWidth = 60
            tableView.addTableColumn(tableColumn)
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
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

    func setCookies(_ cookies: [ResponseFormatter.Cookie]) {
        self.cookies = cookies
        tableView.reloadData()
        emptyState.isHidden = !cookies.isEmpty
        scrollView.isHidden = cookies.isEmpty
    }
}

extension CookiesViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        cookies.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard
            let tableColumn,
            let column = Column(rawValue: tableColumn.identifier.rawValue),
            cookies.indices.contains(row)
        else { return nil }

        let cookie = cookies[row]
        let text: String
        switch column {
        case .name: text = cookie.name
        case .value: text = cookie.value
        case .domain: text = cookie.domain
        case .path: text = cookie.path
        case .expires: text = cookie.expires.isEmpty ? "Session" : cookie.expires
        case .flags:
            var flags: [String] = []
            if cookie.isSecure { flags.append("Secure") }
            if cookie.isHTTPOnly { flags.append("HttpOnly") }
            text = flags.joined(separator: ", ")
        }

        let field = NSTextField(labelWithString: text)
        field.font = .monospacedSystemFont(ofSize: 11, weight: column == .name ? .medium : .regular)
        field.textColor = column == .name ? .labelColor : .secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        field.isSelectable = true
        field.toolTip = text
        return field
    }
}
