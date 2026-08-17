import AppKit

/// Page dots for the workspace pager, plus the control that adds a workspace.
///
/// The dots are the pager's only persistent affordance: a swipe leaves no trace
/// once it settles, so without them there is nothing to say how many workspaces
/// exist or which one is showing.
@MainActor
final class WorkspaceDotsView: NSView {

    var onSelect: ((UUID) -> Void)?
    var onAdd: (() -> Void)?

    private let stack = NSStackView()
    private var dots: [DotButton] = []
    private let addButton = NSButton()

    private var workspaceIDs: [UUID] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        addSubview(stack)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .accessoryBarAction
        addButton.isBordered = false
        addButton.image = NSImage(
            systemSymbolName: "plus.circle",
            accessibilityDescription: "Add workspace"
        )
        addButton.contentTintColor = .secondaryLabelColor
        addButton.toolTip = "New workspace"
        addButton.target = self
        addButton.action = #selector(addTapped)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    /// Rebuilds only when the workspace list itself changes. The library
    /// notifies on every mutation, including each request edit, and rebuilding
    /// the dots on those would drop the button being clicked.
    func update(workspaces: [WorkspaceSnapshot], activeID: UUID?) {
        let ids = workspaces.map(\.id)
        if ids != workspaceIDs {
            workspaceIDs = ids
            rebuild(workspaces)
        }
        for (index, dot) in dots.enumerated() {
            dot.isActive = workspaceIDs.indices.contains(index)
                && workspaceIDs[index] == activeID
        }
    }

    private func rebuild(_ workspaces: [WorkspaceSnapshot]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        dots = workspaces.map { workspace in
            let dot = DotButton(workspaceID: workspace.id)
            dot.toolTip = workspace.name
            dot.setAccessibilityLabel(workspace.name)
            dot.onTap = { [weak self] id in self?.onSelect?(id) }
            stack.addArrangedSubview(dot)
            return dot
        }
        stack.addArrangedSubview(addButton)
    }

    @objc private func addTapped() {
        onAdd?()
    }
}

/// One dot. Drawn rather than assembled from an image so the active and
/// inactive states differ only by fill, which keeps them the same size and
/// stops the row from reflowing as the page changes.
@MainActor
private final class DotButton: NSView {

    var onTap: ((UUID) -> Void)?

    var isActive = false {
        didSet { if oldValue != isActive { needsDisplay = true } }
    }

    private let workspaceID: UUID

    init(workspaceID: UUID) {
        self.workspaceID = workspaceID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 7),
            heightAnchor.constraint(equalToConstant: 7),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = isActive ? .controlAccentColor : .tertiaryLabelColor
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(workspaceID)
    }
}
