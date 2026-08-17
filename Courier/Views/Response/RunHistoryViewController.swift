import AppKit

/// Past runs for the open request, newest first.
@MainActor
final class RunHistoryViewController: NSViewController {

    var onSelect: ((UUID) -> Void)?
    var onToggleStar: ((UUID, Bool) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyState = EmptyStateView(
        symbolName: "clock.arrow.circlepath",
        title: "No History",
        subtitle: "Runs of this request are kept here."
    )

    private var runs: [RunSummary] = []
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    private enum Column {
        static let star = NSUserInterfaceItemIdentifier("star")
        static let status = NSUserInterfaceItemIdentifier("status")
        static let when = NSUserInterfaceItemIdentifier("when")
        static let duration = NSUserInterfaceItemIdentifier("duration")
        static let size = NSUserInterfaceItemIdentifier("size")
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
        tableView.rowHeight = 24
        tableView.target = self
        tableView.action = #selector(rowClicked)

        let star = NSTableColumn(identifier: Column.star)
        star.title = ""
        star.width = 24
        star.minWidth = 24
        star.maxWidth = 24
        tableView.addTableColumn(star)

        for (identifier, title, width) in [
            (Column.status, "Status", 110.0),
            (Column.when, "When", 150.0),
            (Column.duration, "Time", 70.0),
            (Column.size, "Size", 70.0),
        ] {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            column.minWidth = 50
            tableView.addTableColumn(column)
        }

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

    func setRuns(_ runs: [RunSummary]) {
        self.runs = runs
        tableView.reloadData()
        emptyState.isHidden = !runs.isEmpty
        scrollView.isHidden = runs.isEmpty
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard runs.indices.contains(row) else { return }
        onSelect?(runs[row].id)
    }

    @objc private func starToggled(_ sender: NSButton) {
        guard runs.indices.contains(sender.tag) else { return }
        onToggleStar?(runs[sender.tag].id, sender.state == .on)
    }
}

extension RunHistoryViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        runs.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, runs.indices.contains(row) else { return nil }
        let run = runs[row]

        if tableColumn.identifier == Column.star {
            let button = NSButton()
            button.setButtonType(.toggle)
            button.isBordered = false
            button.image = NSImage(systemSymbolName: "star", accessibilityDescription: "Not starred")
            button.alternateImage = NSImage(
                systemSymbolName: "star.fill",
                accessibilityDescription: "Starred"
            )
            button.contentTintColor = run.isStarred ? .systemYellow : .tertiaryLabelColor
            button.state = run.isStarred ? .on : .off
            button.tag = row
            button.target = self
            button.action = #selector(starToggled(_:))
            button.title = ""
            // Starred runs survive history pruning, so this is a retention
            // control, not just a bookmark.
            button.toolTip = "Keep this run when history is trimmed"
            return button
        }

        let text: String
        var color: NSColor = .secondaryLabelColor

        switch tableColumn.identifier {
        case Column.status:
            if let code = run.statusCode {
                text = "\(code)"
                color = Theme.color(forStatusCode: code)
            } else if run.errorMessage != nil {
                text = "Failed"
                color = .systemRed
            } else {
                text = run.status.rawValue.capitalized
            }
        case Column.when:
            text = Self.timeFormatter.string(from: run.createdAt)
        case Column.duration:
            text = run.duration.map { String(format: "%.0f ms", $0 * 1000) } ?? "—"
        case Column.size:
            text = run.size.map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .binary)
            } ?? "—"
        default:
            return nil
        }

        let field = NSTextField(labelWithString: text)
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
