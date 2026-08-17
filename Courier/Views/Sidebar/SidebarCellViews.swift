import AppKit

/// Row view for a request: colored method badge + editable name.
@MainActor
final class RequestCellView: NSTableCellView {

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("RequestCell")

    private let badge = NSTextField(labelWithString: "")
    private let name = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        // Tabular figures keep the badge column aligned regardless of method.
        badge.font = .monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        badge.alignment = .right
        badge.translatesAutoresizingMaskIntoConstraints = false

        name.font = .systemFont(ofSize: NSFont.systemFontSize)
        name.lineBreakMode = .byTruncatingTail
        name.isEditable = false
        name.isBordered = false
        name.drawsBackground = false
        name.translatesAutoresizingMaskIntoConstraints = false

        addSubview(badge)
        addSubview(name)
        textField = name

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 42),

            name.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 6),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(node: SidebarNode) {
        badge.stringValue = node.method ?? ""
        badge.textColor = Theme.color(forMethod: node.method ?? "")
        name.stringValue = node.name
    }

    /// Puts the name field into edit mode for inline rename.
    func beginEditing() {
        name.isEditable = true
        window?.makeFirstResponder(name)
    }

    func endEditing() {
        name.isEditable = false
    }
}

/// Row view for a folder: symbol + editable name.
@MainActor
final class FolderCellView: NSTableCellView {

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FolderCell")

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        name.font = .systemFont(ofSize: NSFont.systemFontSize)
        name.lineBreakMode = .byTruncatingTail
        name.isEditable = false
        name.isBordered = false
        name.drawsBackground = false
        name.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(name)
        imageView = icon
        textField = name

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),

            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(node: SidebarNode) {
        name.stringValue = node.name
    }

    func beginEditing() {
        name.isEditable = true
        window?.makeFirstResponder(name)
    }

    func endEditing() {
        name.isEditable = false
    }
}
