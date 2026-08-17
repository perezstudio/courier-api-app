import AppKit

/// Environment list for the editor sheet, with a fixed collection-scope row.
@MainActor
final class EnvironmentListViewController: NSViewController {

    enum Selection {
        case collection
        case environment(UUID)
    }

    var onSelect: ((Selection) -> Void)?
    var onCreate: (() -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDelete: ((UUID) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let addButton = NSButton()
    private let removeButton = NSButton()

    private var environments: [EnvironmentSnapshot] = []
    private var activeID: UUID?

    /// Row 0 is always collection scope, so environments start at row 1.
    private let collectionRowCount = 1

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTable()
        setupLayout()
    }

    private func setupTable() {
        tableView.style = .sourceList
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayout() {
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New environment")
        addButton.bezelStyle = .smallSquare
        addButton.isBordered = false
        addButton.target = self
        addButton.action = #selector(addTapped)

        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Delete environment")
        removeButton.bezelStyle = .smallSquare
        removeButton.isBordered = false
        removeButton.target = self
        removeButton.action = #selector(removeTapped)

        let buttons = NSStackView(views: [addButton, removeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 4
        buttons.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(buttons)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            buttons.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Content

    func setEnvironments(_ environments: [EnvironmentSnapshot], activeID: UUID?) {
        self.environments = environments
        self.activeID = activeID
        let selected = tableView.selectedRow
        tableView.reloadData()
        if selected >= 0, selected < collectionRowCount + environments.count {
            tableView.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        removeButton.isEnabled = tableView.selectedRow >= collectionRowCount
    }

    func beginRenaming(_ id: UUID) {
        guard let index = environments.firstIndex(where: { $0.id == id }) else { return }
        let row = index + collectionRowCount
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView
        else { return }
        cell.textField?.isEditable = true
        view.window?.makeFirstResponder(cell.textField)
    }

    // MARK: - Actions

    @objc private func addTapped() {
        onCreate?()
    }

    @objc private func removeTapped() {
        let row = tableView.selectedRow
        guard row >= collectionRowCount else { return }
        onDelete?(environments[row - collectionRowCount].id)
    }
}

extension EnvironmentListViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        collectionRowCount + environments.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: "")
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = false
        field.delegate = self
        field.tag = row
        field.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentTintColor = .secondaryLabelColor

        cell.addSubview(icon)
        cell.addSubview(field)
        cell.textField = field
        cell.imageView = icon

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        if row < collectionRowCount {
            icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            field.stringValue = "Collection Variables"
            field.textColor = .labelColor
            return cell
        }

        let environment = environments[row - collectionRowCount]
        icon.image = NSImage(systemSymbolName: "cube", accessibilityDescription: nil)
        field.stringValue = environment.name
        // The active environment is marked here as well as in the toolbar, so
        // the sheet alone tells you which one a send would use.
        if environment.id == activeID {
            field.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            icon.contentTintColor = .controlAccentColor
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }

        removeButton.isEnabled = row >= collectionRowCount
        if row < collectionRowCount {
            onSelect?(.collection)
        } else {
            onSelect?(.environment(environments[row - collectionRowCount].id))
        }
    }
}

extension EnvironmentListViewController: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        defer { field.isEditable = false }

        let row = field.tag
        guard row >= collectionRowCount, environments.indices.contains(row - collectionRowCount)
        else { return }

        let environment = environments[row - collectionRowCount]
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != environment.name else {
            field.stringValue = environment.name
            return
        }
        onRename?(environment.id, name)
    }
}
