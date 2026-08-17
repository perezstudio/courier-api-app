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
        static let responseMode = NSToolbarItem.Identifier("courier.responseMode")
        static let toggleInspector = NSToolbarItem.Identifier("courier.toggleInspector")
        static let contentSeparator = NSToolbarItem.Identifier("courier.contentSeparator")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            // Sidebar region: toggle on the left, add pushed to the right edge.
            .toggleSidebar,
            .flexibleSpace,
            ItemID.newRequest,
            ItemID.sidebarSeparator,
            // Middle region: three separate items rather than one grouped
            // view, so each gets standard toolbar treatment. The explicit
            // spaces matter — view-based items with fixed min/max sizes get
            // packed flush against each other, so the capsules touched.
            ItemID.method,
            .space,
            ItemID.url,
            .space,
            ItemID.send,
            ItemID.contentSeparator,
            // Inspector region: mode picker left, close button right.
            ItemID.responseMode,
            .flexibleSpace,
            ItemID.toggleInspector,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace, .space]
    }

    // MARK: - Items

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
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

        case ItemID.responseMode:
            let control = NSSegmentedControl(
                labels: ResponseViewController.Mode.allCases.map(\.label),
                trackingMode: .selectOne,
                target: self,
                action: #selector(responseModeChanged)
            )
            control.selectedSegment = 0
            control.controlSize = .regular
            control.setAccessibilityLabel("Results view")
            responseModeControl = control

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "View"
            item.paletteLabel = "Results View"
            item.toolTip = "Results, timeline, or history"
            item.view = control
            return item

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

        // With the inspector closed there is no divider for the separator to
        // follow and no region for the mode picker to sit in. Left in place the
        // separator jumps to the window edge and pushes the toggle into the
        // overflow menu — stranding the user with no way to reopen the pane. So
        // both are pulled out while collapsed, leaving just the toggle.
        guard let toolbar else { return }

        func indexOf(_ identifier: NSToolbarItem.Identifier) -> Int? {
            toolbar.items.firstIndex { $0.itemIdentifier == identifier }
        }

        if isCollapsed {
            for identifier in [ItemID.responseMode, ItemID.contentSeparator] {
                if let index = indexOf(identifier) { toolbar.removeItem(at: index) }
            }
        } else if indexOf(ItemID.contentSeparator) == nil {
            guard let toggleIndex = indexOf(ItemID.toggleInspector) else { return }
            // Rebuilt in order ahead of the toggle: separator, picker, space.
            toolbar.insertItem(withItemIdentifier: ItemID.contentSeparator, at: toggleIndex - 1)
            toolbar.insertItem(withItemIdentifier: ItemID.responseMode, at: toggleIndex)
        }
    }

    func setResponseMode(_ mode: ResponseViewController.Mode) {
        responseModeControl?.selectedSegment = mode.rawValue
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
        callbacks.responseModeChange(mode)
    }
}

extension MainToolbarDelegate: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === urlField else { return }
        urlField?.applyHighlighting()
        callbacks.urlChange(field.stringValue)
    }
}
