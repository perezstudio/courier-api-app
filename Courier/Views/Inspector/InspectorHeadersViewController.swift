import AppKit

/// Pure AppKit view controller displaying response headers in an NSTableView.
final class InspectorHeadersViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var headers: [(key: String, value: String)] = []

    private let keyColumnID = NSUserInterfaceItemIdentifier("key")
    private let valueColumnID = NSUserInterfaceItemIdentifier("value")

    override func loadView() {
        view = NSView()
        setupTableView()
    }

    private func setupTableView() {
        // Key column
        let keyColumn = NSTableColumn(identifier: keyColumnID)
        keyColumn.title = "Header"
        keyColumn.width = 140
        keyColumn.minWidth = 80
        keyColumn.maxWidth = 300

        // Value column
        let valueColumn = NSTableColumn(identifier: valueColumnID)
        valueColumn.title = "Value"
        valueColumn.minWidth = 100

        tableView.addTableColumn(keyColumn)
        tableView.addTableColumn(valueColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .none

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }

    func setHeaders(_ dict: [String: String]) {
        headers = dict.sorted { $0.key < $1.key }
        tableView.reloadData()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        headers.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < headers.count else { return nil }
        let entry = headers[row]

        let identifier = tableColumn?.identifier ?? keyColumnID
        let cellID = NSUserInterfaceItemIdentifier("HeaderCell_\(identifier.rawValue)")

        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellID
            textField.cell?.truncatesLastVisibleLine = true
            textField.cell?.lineBreakMode = .byTruncatingTail
            textField.isSelectable = true
        }

        textField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)

        if identifier == keyColumnID {
            textField.stringValue = entry.key
            textField.textColor = .secondaryLabelColor
            textField.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            textField.alignment = .right
        } else {
            textField.stringValue = entry.value
            textField.textColor = .labelColor
            textField.alignment = .left
        }

        return textField
    }
}
