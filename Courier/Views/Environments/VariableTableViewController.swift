import AppKit

/// Editable variable table: enabled, key, value, secret.
///
/// Secret values use `NSSecureTextField` and are read from and written to the
/// Keychain by the repository — the snapshot's `value` is empty for them
/// (REQUIREMENTS.md §6). A per-row reveal button swaps in a plain field so a
/// user can check what they stored.
@MainActor
final class VariableTableViewController: NSViewController {

    struct Row {
        var id: UUID
        var key: String
        var value: String
        var isSecret: Bool
        var isEnabled: Bool
    }

    var onEdit: ((Row) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    var onDone: (() -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let addButton = NSButton()
    private let doneButton = NSButton()
    private let emptyState = EmptyStateView(
        symbolName: "curlybraces",
        title: "No Variables",
        subtitle: "Add one, then reference it as {{name}}."
    )

    private var rows: [Row] = []
    /// Secrets shown in the clear, by explicit request, until the sheet closes.
    private var revealed: Set<UUID> = []

    private enum Column {
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let key = NSUserInterfaceItemIdentifier("key")
        static let value = NSUserInterfaceItemIdentifier("value")
        static let secret = NSUserInterfaceItemIdentifier("secret")
        static let reveal = NSUserInterfaceItemIdentifier("reveal")
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
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26

        let enabled = NSTableColumn(identifier: Column.enabled)
        enabled.title = ""
        enabled.width = 24
        enabled.minWidth = 24
        enabled.maxWidth = 24
        tableView.addTableColumn(enabled)

        let key = NSTableColumn(identifier: Column.key)
        key.title = "Name"
        key.minWidth = 120
        tableView.addTableColumn(key)

        let value = NSTableColumn(identifier: Column.value)
        value.title = "Value"
        value.minWidth = 160
        tableView.addTableColumn(value)

        let reveal = NSTableColumn(identifier: Column.reveal)
        reveal.title = ""
        reveal.width = 28
        reveal.minWidth = 28
        reveal.maxWidth = 28
        tableView.addTableColumn(reveal)

        let secret = NSTableColumn(identifier: Column.secret)
        secret.title = "Secret"
        secret.width = 56
        secret.minWidth = 56
        secret.maxWidth = 56
        tableView.addTableColumn(secret)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayout() {
        addButton.title = "Add Variable"
        addButton.bezelStyle = .push
        addButton.controlSize = .small
        addButton.target = self
        addButton.action = #selector(addTapped)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        // The sheet has no title bar, so this is the only way out of it.
        doneButton.title = "Done"
        doneButton.bezelStyle = .push
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(doneTapped)
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        emptyState.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(emptyState)
        view.addSubview(addButton)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyState.topAnchor.constraint(equalTo: view.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

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
                constant: -Theme.Metrics.standardPadding
            ),

            doneButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            doneButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Theme.Metrics.standardPadding
            ),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 78),
        ])
    }

    // MARK: - Content

    func setRows(_ rows: [Row]) {
        self.rows = rows
        tableView.reloadData()
        emptyState.isHidden = !rows.isEmpty
        scrollView.isHidden = rows.isEmpty
        addButton.isEnabled = true
    }

    func setEnabled(_ isEnabled: Bool) {
        addButton.isEnabled = isEnabled
        tableView.isEnabled = isEnabled
    }

    /// Forgets revealed secrets. Called when the sheet closes so a value is
    /// never left on screen for the next person to open it.
    func hideRevealedSecrets() {
        revealed.removeAll()
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func addTapped() {
        onAdd?()
    }

    @objc private func doneTapped() {
        onDone?()
    }

    /// Escape closes the sheet, matching every other sheet on the platform.
    override func cancelOperation(_ sender: Any?) {
        onDone?()
    }

    @objc private func enabledToggled(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }
        rows[sender.tag].isEnabled = sender.state == .on
        onEdit?(rows[sender.tag])
    }

    @objc private func secretToggled(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }
        rows[sender.tag].isSecret = sender.state == .on
        // Revealing then un-secreting would otherwise leave the row in a state
        // where the mask is off but the value is meant to be hidden.
        revealed.remove(rows[sender.tag].id)
        onEdit?(rows[sender.tag])
        tableView.reloadData()
    }

    @objc private func revealToggled(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }
        let id = rows[sender.tag].id
        if revealed.contains(id) {
            revealed.remove(id)
        } else {
            revealed.insert(id)
        }
        tableView.reloadData()
    }

    override func keyDown(with event: NSEvent) {
        let deleteKey = 51
        if Int(event.keyCode) == deleteKey, tableView.selectedRow >= 0,
           rows.indices.contains(tableView.selectedRow) {
            onDelete?(rows[tableView.selectedRow].id)
            return
        }
        super.keyDown(with: event)
    }
}

extension VariableTableViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, rows.indices.contains(row) else { return nil }
        let model = rows[row]

        switch tableColumn.identifier {
        case Column.enabled:
            let checkbox = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(enabledToggled(_:))
            )
            checkbox.state = model.isEnabled ? .on : .off
            checkbox.tag = row
            checkbox.setAccessibilityLabel("Enabled")
            return checkbox

        case Column.secret:
            let checkbox = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(secretToggled(_:))
            )
            checkbox.state = model.isSecret ? .on : .off
            checkbox.tag = row
            checkbox.setAccessibilityLabel("Secret")
            checkbox.toolTip = "Store this value in the Keychain instead of the library"
            return checkbox

        case Column.reveal:
            guard model.isSecret else { return NSView() }
            let button = NSButton()
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            let isRevealed = revealed.contains(model.id)
            button.image = NSImage(
                systemSymbolName: isRevealed ? "eye.slash" : "eye",
                accessibilityDescription: isRevealed ? "Hide value" : "Reveal value"
            )
            button.contentTintColor = .secondaryLabelColor
            button.tag = row
            button.target = self
            button.action = #selector(revealToggled(_:))
            button.title = ""
            return button

        case Column.key:
            let field = editableField(text: model.key, row: row, identifier: Column.key)
            field.placeholderString = "Name"
            field.textColor = model.isEnabled ? .labelColor : .tertiaryLabelColor
            return field

        case Column.value:
            let showMasked = model.isSecret && !revealed.contains(model.id)
            let field: NSTextField = showMasked ? NSSecureTextField() : NSTextField()
            field.stringValue = model.value
            field.isBordered = false
            field.drawsBackground = false
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
            field.placeholderString = model.isSecret ? "Stored in Keychain" : "Value"
            field.textColor = model.isEnabled ? .labelColor : .tertiaryLabelColor
            field.delegate = self
            field.tag = row
            field.identifier = Column.value
            return field

        default:
            return nil
        }
    }

    private func editableField(
        text: String,
        row: Int,
        identifier: NSUserInterfaceItemIdentifier
    ) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = self
        field.tag = row
        field.identifier = identifier
        return field
    }
}

extension VariableTableViewController: NSTextFieldDelegate {

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
        default:
            return
        }
        onEdit?(rows[field.tag])
    }
}
