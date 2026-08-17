import AppKit

/// Builds the unified toolbar.
@MainActor
final class MainToolbarDelegate: NSObject, NSToolbarDelegate {

    private let splitView: NSSplitView
    private let onNewRequest: () -> Void
    private let onFilterChange: (String) -> Void

    init(
        splitView: NSSplitView,
        onNewRequest: @escaping () -> Void,
        onFilterChange: @escaping (String) -> Void
    ) {
        self.splitView = splitView
        self.onNewRequest = onNewRequest
        self.onFilterChange = onFilterChange
        super.init()
    }

    // MARK: - Identifiers

    private enum ItemID {
        static let trackingSeparator = NSToolbarItem.Identifier("courier.trackingSeparator")
        static let environment = NSToolbarItem.Identifier("courier.environment")
        static let newRequest = NSToolbarItem.Identifier("courier.newRequest")
        static let search = NSToolbarItem.Identifier("courier.search")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            ItemID.trackingSeparator,
            ItemID.newRequest,
            .flexibleSpace,
            ItemID.environment,
            ItemID.search,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space, .flexibleSpace, .sidebarTrackingSeparator]
    }

    // MARK: - Items

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ItemID.trackingSeparator:
            // Keeps the toolbar's separator aligned with the sidebar divider as
            // the user drags it. Without this the unified sidebar looks almost,
            // but not quite, right. See REQUIREMENTS.md §7.1.
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 0
            )

        case ItemID.newRequest:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "New Request"
            item.paletteLabel = "New Request"
            item.toolTip = "New request"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New request")
            item.isBordered = true
            item.target = self
            item.action = #selector(newRequestTapped)
            return item

        case ItemID.environment:
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
            popUp.addItem(withTitle: "No Environment")
            // Populated in Phase 6, when environments exist.
            popUp.isEnabled = false

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Environment"
            item.paletteLabel = "Environment"
            item.toolTip = "Active environment"
            item.view = popUp
            return item

        case ItemID.search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Filter"
            item.paletteLabel = "Filter"
            item.toolTip = "Filter requests"
            item.searchField.placeholderString = "Filter"
            item.searchField.target = self
            item.searchField.action = #selector(searchChanged(_:))
            item.searchField.sendsWholeSearchString = false
            item.searchField.sendsSearchStringImmediately = true
            return item

        default:
            return nil
        }
    }

    // MARK: - Actions

    @objc private func newRequestTapped() {
        onNewRequest()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        onFilterChange(sender.stringValue)
    }
}
