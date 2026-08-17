import AppKit

/// Builds the unified toolbar.
@MainActor
final class MainToolbarDelegate: NSObject, NSToolbarDelegate {

    private let splitView: NSSplitView
    private let onNewRequest: () -> Void
    private let onFilterChange: (String) -> Void
    private let onEnvironmentChange: (UUID?) -> Void
    private let onEditEnvironments: () -> Void

    private weak var environmentPopUp: NSPopUpButton?

    /// Sentinel for the "Manage Environments…" row, which is a command rather
    /// than a selectable environment.
    private static let manageTag = -99

    init(
        splitView: NSSplitView,
        onNewRequest: @escaping () -> Void,
        onFilterChange: @escaping (String) -> Void,
        onEnvironmentChange: @escaping (UUID?) -> Void,
        onEditEnvironments: @escaping () -> Void
    ) {
        self.splitView = splitView
        self.onNewRequest = onNewRequest
        self.onFilterChange = onFilterChange
        self.onEnvironmentChange = onEnvironmentChange
        self.onEditEnvironments = onEditEnvironments
        super.init()
    }

    /// Repopulates the environment picker.
    func updateEnvironments(_ environments: [EnvironmentSnapshot], activeID: UUID?) {
        guard let popUp = environmentPopUp else { return }

        popUp.removeAllItems()
        popUp.addItem(withTitle: "No Environment")
        popUp.lastItem?.representedObject = nil

        for environment in environments {
            popUp.addItem(withTitle: environment.name)
            popUp.lastItem?.representedObject = environment.id
        }

        popUp.menu?.addItem(.separator())
        popUp.addItem(withTitle: "Manage Environments…")
        popUp.lastItem?.tag = Self.manageTag

        if let activeID, let index = environments.firstIndex(where: { $0.id == activeID }) {
            popUp.selectItem(at: index + 1)
        } else {
            popUp.selectItem(at: 0)
        }
        popUp.isEnabled = true
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
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 190, height: 24))
            popUp.addItem(withTitle: "No Environment")
            popUp.target = self
            popUp.action = #selector(environmentChanged(_:))
            popUp.setAccessibilityLabel("Active environment")
            environmentPopUp = popUp

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

    @objc private func environmentChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }

        if item.tag == Self.manageTag {
            // Not a selection — restore the previous one and open the editor.
            onEditEnvironments()
            return
        }
        onEnvironmentChange(item.representedObject as? UUID)
    }
}
