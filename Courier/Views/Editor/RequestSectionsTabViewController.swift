import AppKit

/// Params · Headers · Body · Auth · Variables.
///
/// `NSTabViewController` with `.segmentedControlOnTop` is the stock control for
/// switching content panes — this replaces what an earlier draft specified as a
/// custom view with an animated `CALayer` indicator (REQUIREMENTS.md §7.3).
@MainActor
final class RequestSectionsTabViewController: NSTabViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .segmentedControlOnTop
        transitionOptions = []

        // Phase 4 replaces each placeholder with its real editor.
        addSection(label: "Params", symbol: "list.bullet", title: "Query Parameters")
        addSection(label: "Headers", symbol: "tag", title: "Headers")
        addSection(label: "Body", symbol: "doc.plaintext", title: "Request Body")
        addSection(label: "Auth", symbol: "lock", title: "Authorization")
        addSection(label: "Variables", symbol: "curlybraces", title: "Variables")
    }

    private func addSection(label: String, symbol: String, title: String) {
        let controller = PlaceholderViewController(symbolName: symbol, title: title)
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        addTabViewItem(item)
    }
}

/// Stand-in pane used while a section is unimplemented.
@MainActor
final class PlaceholderViewController: NSViewController {

    private let symbolName: String
    private let title_: String

    init(symbolName: String, title: String) {
        self.symbolName = symbolName
        self.title_ = title
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = EmptyStateView(symbolName: symbolName, title: title_)
    }
}
