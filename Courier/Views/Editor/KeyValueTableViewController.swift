import AppKit

/// Editable key/value table.
///
/// One component serves Params, Headers, form-data, and URL-encoded bodies —
/// REQUIREMENTS.md §11 counts this reuse as part of what pays for writing the
/// UI in AppKit rather than SwiftUI.
@MainActor
final class KeyValueTableViewController: NSViewController {

    /// Completion suggestions offered for the key column.
    var keySuggestions: [String] = []

    var onChange: (([KeyValueRow]) -> Void)?

    private(set) var rows: [KeyValueRow] = []

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let addButton = NSButton()

    private enum Column {
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let key = NSUserInterfaceItemIdentifier("key")
        static let value = NSUserInterfaceItemIdentifier("value")
        static let note = NSUserInterfaceItemIdentifier("note")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTable()
        setupLayout()
    }

    private func setupTable() {
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24

        let enabled = NSTableColumn(identifier: Column.enabled)
        enabled.title = ""
        enabled.width = 24
        enabled.minWidth = 24
        enabled.maxWidth = 24
        tableView.addTableColumn(enabled)

        let key = NSTableColumn(identifier: Column.key)
        key.title = "Key"
        key.minWidth = 100
        tableView.addTableColumn(key)

        let value = NSTableColumn(identifier: Column.value)
        value.title = "Value"
        value.minWidth = 120
        tableView.addTableColumn(value)

        let note = NSTableColumn(identifier: Column.note)
        note.title = "Description"
        note.minWidth = 80
        tableView.addTableColumn(note)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayout() {
        addButton.title = "Add Row"
        addButton.bezelStyle = .push
        addButton.controlSize = .small
        addButton.target = self
        addButton.action = #selector(addRow)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(addButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            addButton.topAnchor.constraint(
                equalTo: scrollView.bottomAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            addButton.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Theme.Metrics.standardPadding
            ),
            addButton.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -Theme.Metrics.tightPadding
            ),
        ])
    }

    // MARK: - Content

    /// Replaces the rows without notifying `onChange` — used when loading a
    /// request, where echoing back would look like a user edit.
    func setRows(_ newRows: [KeyValueRow]) {
        rows = newRows
        tableView.reloadData()
    }

    private func commit() {
        onChange?(rows)
    }

    @objc private func addRow() {
        rows.append(KeyValueRow(key: "", value: ""))
        tableView.reloadData()
        commit()

        let row = rows.count - 1
        tableView.scrollRowToVisible(row)
        tableView.editColumn(1, row: row, with: nil, select: false)
    }

    private func deleteRows(at indexes: IndexSet) {
        guard !indexes.isEmpty else { return }
        for index in indexes.sorted(by: >) where index < rows.count {
            rows.remove(at: index)
        }
        tableView.reloadData()
        commit()
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard rows.indices.contains(row) else { return }
        rows[row].isEnabled = sender.state == .on
        commit()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let deleteKey = 51
        if Int(event.keyCode) == deleteKey, !tableView.selectedRowIndexes.isEmpty {
            deleteRows(at: tableView.selectedRowIndexes)
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Data source

extension KeyValueTableViewController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }
}

// MARK: - Delegate

extension KeyValueTableViewController: NSTableViewDelegate {

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, rows.indices.contains(row) else { return nil }
        let model = rows[row]

        if tableColumn.identifier == Column.enabled {
            let checkbox = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(toggleEnabled(_:))
            )
            checkbox.state = model.isEnabled ? .on : .off
            checkbox.tag = row
            checkbox.setAccessibilityLabel("Enabled")
            return checkbox
        }

        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self
        field.tag = row
        field.identifier = tableColumn.identifier

        switch tableColumn.identifier {
        case Column.key:
            field.stringValue = model.key
            field.placeholderString = "Key"
            // Disabled rows are dimmed rather than hidden, so it stays obvious
            // they exist and can be switched back on.
            field.textColor = model.isEnabled ? .labelColor : .tertiaryLabelColor
        case Column.value:
            field.stringValue = model.value
            field.placeholderString = "Value"
            field.textColor = model.isEnabled ? .labelColor : .tertiaryLabelColor
        case Column.note:
            field.stringValue = model.note ?? ""
            field.placeholderString = "Description"
            field.textColor = .secondaryLabelColor
        default:
            return nil
        }

        return field
    }
}

// MARK: - Editing

extension KeyValueTableViewController: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ notification: Notification) {
        guard
            let field = notification.object as? NSTextField,
            rows.indices.contains(field.tag)
        else { return }

        switch field.identifier {
        case Column.key:
            rows[field.tag].key = field.stringValue
        case Column.value:
            rows[field.tag].value = field.stringValue
        case Column.note:
            rows[field.tag].note = field.stringValue.isEmpty ? nil : field.stringValue
        default:
            return
        }
        commit()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        completions words: [String],
        forPartialWordRange charRange: NSRange,
        indexOfSelectedItem index: UnsafeMutablePointer<Int>
    ) -> [String] {
        guard control.identifier == Column.key, !keySuggestions.isEmpty else { return [] }
        let partial = (textView.string as NSString).substring(with: charRange).lowercased()
        guard !partial.isEmpty else { return [] }
        return keySuggestions.filter { $0.lowercased().hasPrefix(partial) }
    }
}

/// Header names offered as completions in the Headers tab.
enum CommonHeaders {
    static let requestHeaders = [
        "Accept", "Accept-Encoding", "Accept-Language", "Authorization",
        "Cache-Control", "Connection", "Content-Length", "Content-Type",
        "Cookie", "Host", "If-Match", "If-None-Match", "Origin", "Referer",
        "User-Agent", "X-Api-Key", "X-Request-Id", "X-Requested-With",
    ]
}
