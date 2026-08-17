import AppKit

/// Builds the unified toolbar.
///
/// The toolbar is divided into three regions by two tracking separators, so it
/// reads as a header for whatever sits beneath it:
///
///     [◫] ······ [+] ‖ [GET ▾] [URL……] [Send] ‖ [Results|Timeline|History] ··· [◨]
///       sidebar            content region              results
///
/// Everything the user needs lives *before* the second separator. Putting an
/// item after it would look reasonable until the response pane collapses — the
/// separator then jumps to the window's right edge and squeezes those items
/// into the overflow menu.
@MainActor
final class MainToolbarDelegate: NSObject, NSToolbarDelegate {

    struct Callbacks {
        var newRequest: () -> Void
        var methodChange: (String) -> Void
        var urlChange: (String) -> Void
        var send: () -> Void
        var toggleInspector: () -> Void
        var responseModeChange: (ResponseViewController.Mode) -> Void
        var resultsSectionChange: (ResultsViewController.Section) -> Void
    }

    /// Both separators track the same split view now that the window is a flat
    /// three-column layout: divider 0 is sidebar|settings, divider 1 is
    /// settings|results.
    private let splitView: NSSplitView
    private let callbacks: Callbacks

    private weak var methodItem: NSMenuToolbarItem?
    private var currentMethod = Theme.Method.get.rawValue
    private weak var urlField: VariableHighlightingTextField?
    private weak var sendItem: NSToolbarItem?
    private weak var inspectorItem: NSToolbarItem?
    private weak var resultsSectionGroup: NSToolbarItemGroup?
    private weak var statusItem: NSToolbarItem?
    private var itemCache: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private var currentStatus: ResponseStatus?
    private var isResultsCollapsed = false
    private weak var responseModeControl: NSSegmentedControl?
    weak var toolbar: NSToolbar?

    init(splitView: NSSplitView, callbacks: Callbacks) {
        self.splitView = splitView
        self.callbacks = callbacks
        super.init()
    }

    // MARK: - Identifiers

    private enum ItemID {
        static let newRequest = NSToolbarItem.Identifier("courier.newRequest")
        static let sidebarSeparator = NSToolbarItem.Identifier("courier.sidebarSeparator")
        static let method = NSToolbarItem.Identifier("courier.method")
        static let url = NSToolbarItem.Identifier("courier.url")
        static let send = NSToolbarItem.Identifier("courier.send")
        static let responseStatus = NSToolbarItem.Identifier("courier.responseStatus")
        static let responseMode = NSToolbarItem.Identifier("courier.responseMode")
        static let resultsSection = NSToolbarItem.Identifier("courier.resultsSection")
        static let toggleInspector = NSToolbarItem.Identifier("courier.toggleInspector")
        static let contentSeparator = NSToolbarItem.Identifier("courier.contentSeparator")
    }

    /// The single source of truth for what the toolbar contains right now.
    ///
    /// Both the delegate callback and the live rebuild read this. Writing the
    /// list out twice is exactly how the sidebar's toggle and add buttons
    /// silently swapped back to their old order — the rebuild carried a stale
    /// copy.
    private func currentIdentifiers() -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = [
            // Sidebar region: toggle at the left, add pushed to the right edge.
            .toggleSidebar,
            .flexibleSpace,
            ItemID.newRequest,
            ItemID.sidebarSeparator,
            // Settings region.
            ItemID.method,
            .space,
            ItemID.url,
            .space,
            ItemID.send,
        ]

        if isResultsCollapsed {
            // No divider to track and no region to fill; just the toggle.
            identifiers.append(.flexibleSpace)
        } else {
            identifiers.append(ItemID.contentSeparator)
            if currentStatus != nil { identifiers.append(ItemID.responseStatus) }
            identifiers.append(ItemID.responseMode)
            identifiers.append(.flexibleSpace)
            if responseModeControl?.selectedSegment == ResponseViewController.Mode.results.rawValue {
                identifiers.append(ItemID.resultsSection)
            }
        }
        identifiers.append(ItemID.toggleInspector)
        return identifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        currentIdentifiers()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, ItemID.newRequest, ItemID.sidebarSeparator,
            ItemID.method, ItemID.url, ItemID.send,
            ItemID.contentSeparator, ItemID.responseStatus, ItemID.responseMode,
            ItemID.resultsSection, ItemID.toggleInspector,
            .flexibleSpace, .space,
        ]
    }

    // MARK: - Items

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        // Reused, not rebuilt. A rebuild re-asks for every item, and returning
        // fresh ones would recreate the URL field — losing its text, its
        // highlighting, and the user's insertion point mid-edit.
        if let cached = itemCache[itemIdentifier] { return cached }
        let item = makeItem(itemIdentifier)
        itemCache[itemIdentifier] = item
        return item
    }

    private func makeItem(_ itemIdentifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch itemIdentifier {
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

        case ItemID.sidebarSeparator:
            // Keeps the toolbar's separator aligned with the sidebar divider as
            // the user drags it (REQUIREMENTS.md §7.1).
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 0
            )

        case ItemID.contentSeparator:
            // Same idea one level in: the toolbar splits where the editor and
            // response panes do.
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 1
            )

        case ItemID.method:
            // An NSMenuToolbarItem, not a bordered NSPopUpButton inside a glass
            // capsule. Wrapping a popup meant stripping its bezel to avoid
            // double chrome, which left bare text and a chevron on a coloured
            // pill — not a picker. A menu item is a real toolbar control: it
            // gets the system's glass and takes the prominent tint directly,
            // the same construction as Admiral's PR chip.
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Method"
            item.paletteLabel = "Method"
            item.toolTip = "HTTP method"
            item.showsIndicator = true
            item.isBordered = true
            item.menu = Self.makeMethodMenu(target: self, action: #selector(methodPicked(_:)))
            methodItem = item
            applyMethod(Theme.Method.get.rawValue)
            return item

        case ItemID.url:
            let field = VariableHighlightingTextField()
            field.placeholderString = "https://api.example.com/path"
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.delegate = self
            field.setAccessibilityLabel("Request URL")
            field.lineBreakMode = .byTruncatingTail
            field.usesSingleLineMode = true
            // Borderless, sitting on a real glass capsule below — the same
            // approach Admiral uses for its chat input. An NSTextField cannot
            // opt into the glass material itself.
            field.isBezeled = false
            field.drawsBackground = false
            field.focusRingType = .none
            // Low hugging and compression resistance so the item's max size,
            // not the text, decides the width.
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            urlField = field

            // Inside `contentView`, not as a sibling subview: the header is
            // explicit that only the content view is guaranteed to sit within
            // the glass effect.
            // The inset view is framed by the glass; only the field inside it
            // uses constraints.
            let inset = NSView()
            field.translatesAutoresizingMaskIntoConstraints = false
            inset.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: inset.leadingAnchor, constant: 10),
                field.trailingAnchor.constraint(equalTo: inset.trailingAnchor, constant: -10),
                field.centerYAnchor.constraint(equalTo: inset.centerYAnchor),
            ])

            let glass = Self.makeGlass(cornerRadius: 12, content: inset)
            glass.frame = NSRect(x: 0, y: 0, width: 320, height: 26)

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "URL"
            item.paletteLabel = "URL"
            item.view = glass
            // Stretching comes from min/max size rather than a width
            // constraint: a constraint derived from the layout fed back into
            // the toolbar's minimum width and froze window resizing.
            item.minSize = NSSize(width: 180, height: 26)
            item.maxSize = NSSize(width: 10_000, height: 26)
            return item

        case ItemID.send:
            // Tinted with the system's own prominent (Liquid Glass) treatment
            // rather than a hand-drawn layer: `NSToolbarItem.style = .prominent`
            // plus `backgroundTintColor` is how Admiral tints its PR chip, and
            // it keeps the item's default styling and behavior intact.
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Send"
            item.paletteLabel = "Send"
            item.toolTip = "Send this request"
            // Title as well as image: Admiral's PR chip sets both, and the
            // prominent style draws its tinted chip around the pair. An
            // image-only item renders untinted.
            item.title = "Send"
            item.image = NSImage(
                systemSymbolName: "paperplane.fill",
                accessibilityDescription: "Send"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            )
            item.isBordered = true
            item.target = self
            item.action = #selector(sendTapped)
            if #available(macOS 26.0, *) {
                item.style = .prominent
                item.backgroundTintColor = .controlAccentColor
            }
            sendItem = item
            return item

        case ItemID.responseStatus:
            // The same class as the method picker, with its chevron suppressed.
            // That is what makes the two chips match exactly: only a real
            // toolbar control takes `style = .prominent`, and the toolbar runs
            // in `.iconOnly`, where a plain NSToolbarItem carrying just a title
            // draws nothing at all. A hosted NSButton renders, but cannot take
            // the prominent treatment — its title had to be coloured by hand.
            //
            // The menu is empty and validation is off: the chip reports status
            // and has nothing to invoke, and an autovalidating item with no
            // target dims itself.
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Status"
            item.paletteLabel = "Response Status"
            item.showsIndicator = false
            item.isBordered = true
            item.autovalidates = false
            item.isEnabled = true
            item.menu = NSMenu()
            statusItem = item
            if let status = currentStatus { apply(status) }
            return item

        case ItemID.responseMode:
            let modes = ResponseViewController.Mode.allCases
            let control = NSSegmentedControl(
                images: modes.map {
                    NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: $0.label)
                        ?? NSImage()
                },
                trackingMode: .selectOne,
                target: self,
                action: #selector(responseModeChanged)
            )
            control.selectedSegment = 0
            control.controlSize = .regular
            control.setAccessibilityLabel("Results view")
            // Icons alone are ambiguous; the tooltip carries the name.
            for (index, mode) in modes.enumerated() {
                control.setToolTip(mode.label, forSegment: index)
            }
            responseModeControl = control

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "View"
            item.paletteLabel = "Results View"
            item.toolTip = "Results, timeline, or history"
            item.view = control
            return item

        case ItemID.resultsSection:
            // Built with the titles initialiser, which backs the group with a
            // real segmented control and picks up the toolbar's standard
            // (glass) styling. Constructing it by hand with
            // `controlRepresentation = .expanded` produced separate flat
            // buttons instead.
            let sections = ResultsViewController.Section.allCases
            let group = NSToolbarItemGroup(
                itemIdentifier: itemIdentifier,
                images: sections.map {
                    NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: $0.label)
                        ?? NSImage()
                },
                selectionMode: .selectOne,
                // Labels still supplied: they carry the names for
                // accessibility and the toolbar's text display mode.
                labels: sections.map(\.label),
                target: self,
                action: #selector(resultsSectionChanged(_:))
            )
            group.label = "Section"
            group.paletteLabel = "Response Section"
            group.toolTip = "Body, headers, or cookies"
            group.controlRepresentation = .automatic
            group.isBordered = true
            group.setSelected(true, at: 0)
            resultsSectionGroup = group
            return group

        case ItemID.toggleInspector:
            // A bordered NSToolbarItem, matching the + button and the system's
            // own toggles. A hand-built NSButton in a view renders subtly
            // differently from every other toolbar item.
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Results"
            item.paletteLabel = "Toggle Results"
            item.toolTip = "Show or hide the results pane"
            item.image = NSImage(
                systemSymbolName: "sidebar.right",
                accessibilityDescription: "Toggle results"
            )
            item.isBordered = true
            item.target = self
            item.action = #selector(toggleInspectorTapped)
            inspectorItem = item
            return item

        default:
            return nil
        }
    }


    // MARK: - State

    /// Points the toolbar at the request currently open in this window.
    func updateRequest(method: String, url: String, hasRequest: Bool) {
        applyMethod(method)
        methodItem?.isEnabled = hasRequest

        if urlField?.stringValue != url {
            urlField?.stringValue = url
        }
        urlField?.isEnabled = hasRequest
        urlField?.applyHighlighting()

        sendItem?.isEnabled = hasRequest
    }

    func setUnresolvedVariables(_ names: Set<String>) {
        urlField?.unresolvedNames = names
    }

    /// Send becomes Cancel while a request is in flight — the only way to stop
    /// one (§8.3).
    func setSending(_ isSending: Bool) {
        sendItem?.title = isSending ? "Cancel" : "Send"
        sendItem?.image = NSImage(
            systemSymbolName: isSending ? "stop.fill" : "paperplane.fill",
            accessibilityDescription: isSending ? "Cancel" : "Send"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        sendItem?.toolTip = isSending ? "Cancel this request" : "Send this request"
        if #available(macOS 26.0, *) {
            sendItem?.backgroundTintColor = isSending ? .systemRed : .controlAccentColor
        }
    }

    func setResponseCollapsed(_ isCollapsed: Bool) {
        inspectorItem?.image = NSImage(
            systemSymbolName: isCollapsed ? "sidebar.right" : "sidebar.squares.right",
            accessibilityDescription: isCollapsed ? "Show results" : "Hide results"
        )
        isResultsCollapsed = isCollapsed
        rebuildResultsRegion()
    }

    /// Reconciles the toolbar against `currentIdentifiers()`.
    ///
    /// Items that come and go — separator, status chip, mode picker, section
    /// group — are handled by recomputing the whole list rather than by
    /// case-by-case inserts, which previously produced a negative index and a
    /// separator that stranded the toggle in the overflow menu.
    private func rebuildResultsRegion() {
        guard let toolbar else { return }

        let desired = currentIdentifiers()
        guard toolbar.items.map(\.itemIdentifier) != desired else { return }

        for index in stride(from: toolbar.items.count - 1, through: 0, by: -1) {
            toolbar.removeItem(at: index)
        }
        for (index, identifier) in desired.enumerated() {
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
    }

    func setResponseMode(_ mode: ResponseViewController.Mode) {
        responseModeControl?.selectedSegment = mode.rawValue
        rebuildResultsRegion()
    }

    /// `nil` removes the chip from the toolbar entirely.
    func setStatus(_ status: ResponseStatus?) {
        currentStatus = status
        if let status { apply(status) }
        rebuildResultsRegion()
    }

    private func apply(_ status: ResponseStatus) {
        guard let item = statusItem else { return }

        // The same treatment the method picker gets: the system's prominent
        // (Liquid Glass) style tinted by the status class, so the two chips at
        // either end of the toolbar read as one family. The item sizes itself
        // to the title, so no explicit min/max is needed.
        item.title = status.title
        item.style = .prominent
        item.backgroundTintColor = status.color
        item.toolTip = "Response status \(status.title)"
    }

    /// A glass capsule wrapping `content`.
    ///
    /// No availability fallback: the deployment target is macOS 26, so the
    /// pre-26 branch Admiral carries would be dead code here.
    private static func makeGlass(cornerRadius: CGFloat, content: NSView) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        return glass
    }

    private static func makeMethodMenu(target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for method in Theme.Method.allCases {
            let entry = NSMenuItem(title: method.rawValue, action: action, keyEquivalent: "")
            entry.target = target
            entry.representedObject = method.rawValue
            entry.attributedTitle = NSAttributedString(
                string: method.rawValue,
                attributes: [
                    .foregroundColor: method.color,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                ]
            )
            menu.addItem(entry)
        }
        return menu
    }

    /// Shows the verb and tints the item with its colour.
    private func applyMethod(_ method: String) {
        currentMethod = method
        methodItem?.title = method
        if #available(macOS 26.0, *) {
            methodItem?.style = .prominent
            methodItem?.backgroundTintColor = Theme.color(forMethod: method)
        }
    }

    // MARK: - Actions

    @objc private func newRequestTapped() {
        callbacks.newRequest()
    }

    @objc private func methodPicked(_ sender: NSMenuItem) {
        guard let method = sender.representedObject as? String else { return }
        applyMethod(method)
        callbacks.methodChange(method)
    }

    @objc private func sendTapped() {
        callbacks.send()
    }

    @objc private func toggleInspectorTapped() {
        callbacks.toggleInspector()
    }

    @objc private func responseModeChanged(_ sender: NSSegmentedControl) {
        guard let mode = ResponseViewController.Mode(rawValue: sender.selectedSegment) else { return }
        rebuildResultsRegion()
        callbacks.responseModeChange(mode)
    }

    @objc private func resultsSectionChanged(_ sender: NSToolbarItemGroup) {
        guard let section = ResultsViewController.Section(rawValue: sender.selectedIndex) else { return }
        callbacks.resultsSectionChange(section)
    }

}

extension MainToolbarDelegate: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === urlField else { return }
        urlField?.applyHighlighting()
        callbacks.urlChange(field.stringValue)
    }
}
