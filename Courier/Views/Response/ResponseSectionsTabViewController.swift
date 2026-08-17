import AppKit

/// Body · Headers · Cookies · Timeline, under a status bar.
@MainActor
final class ResponseSectionsTabViewController: NSTabViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .segmentedControlOnTop
        transitionOptions = []

        // Phase 5 replaces these with the real renderers and wires the status
        // bar above them (code, duration, size).
        addSection(label: "Body", symbol: "doc.text", title: "No Response Yet")
        addSection(label: "Headers", symbol: "tag", title: "Response Headers")
        addSection(label: "Cookies", symbol: "circle.grid.2x2", title: "Cookies")
        addSection(label: "Timeline", symbol: "chart.bar", title: "Timeline")
    }

    private func addSection(label: String, symbol: String, title: String) {
        let controller = PlaceholderViewController(symbolName: symbol, title: title)
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        addTabViewItem(item)
    }
}
