import AppKit

/// Stand-in pane for a section that is not implemented yet.
@MainActor
final class PlaceholderViewController: NSViewController {

    private let symbolName: String
    private let placeholderTitle: String

    init(symbolName: String, title: String) {
        self.symbolName = symbolName
        self.placeholderTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = EmptyStateView(symbolName: symbolName, title: placeholderTitle)
    }
}
