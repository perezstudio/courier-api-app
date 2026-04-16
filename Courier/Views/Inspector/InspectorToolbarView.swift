import AppKit

/// Pure AppKit toolbar showing status code, timing, size, and Body/Headers tab selector.
final class InspectorToolbarView: NSView {
    var onTabChanged: ((InspectorTab) -> Void)?
    var onToggleInspector: (() -> Void)?

    // Left side
    private let collapseButton = HoverIconButtonView(
        symbolName: "sidebar.trailing",
        accessibilityLabel: "Hide Inspector",
        tooltip: "Hide Inspector"
    )
    private let statusCodeLabel = NSTextField(labelWithString: "")
    private let statusTextLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")

    // Right side — custom tab buttons matching RequestSectionTabBar style
    private var tabButtonViews: [InspectorTabButtonView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupViews() {
        // Collapse button — matches courierHover style from SwiftUI
        collapseButton.onTap = { [weak self] in
            self?.onToggleInspector?()
        }

        // Status code
        statusCodeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        statusCodeLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Status text
        statusTextLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusTextLabel.textColor = .labelColor
        statusTextLabel.setContentHuggingPriority(.required, for: .horizontal)

        let statusRow = NSStackView(views: [statusCodeLabel, statusTextLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 4

        // Duration + size
        durationLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        sizeLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let metaRow = NSStackView(views: [durationLabel, sizeLabel])
        metaRow.orientation = .horizontal
        metaRow.spacing = 6

        let leftStack = NSStackView(views: [statusRow, metaRow])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 1

        // Tab buttons — matching RequestSectionTabBar visual style
        tabButtonViews = InspectorTab.allCases.map { tab in
            let button = InspectorTabButtonView(title: tab.rawValue)
            button.isSelected = (tab == .body)
            button.onTap = { [weak self] in
                self?.selectTab(tab)
            }
            return button
        }

        let tabStack = NSStackView(views: tabButtonViews)
        tabStack.orientation = .horizontal
        tabStack.spacing = 4

        // Flexible spacer between status info and tab buttons
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)

        // Layout
        let mainStack = NSStackView(views: [collapseButton, leftStack, spacer, tabStack])
        mainStack.orientation = .horizontal
        mainStack.distribution = .fill
        mainStack.spacing = 8
        mainStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func selectTab(_ tab: InspectorTab) {
        for (i, t) in InspectorTab.allCases.enumerated() {
            tabButtonViews[i].isSelected = (t == tab)
        }
        onTabChanged?(tab)
    }

    func update(run: APICallRun, selectedTab: InspectorTab) {
        // Status code
        if let code = run.statusCode {
            statusCodeLabel.stringValue = "\(code)"
            statusCodeLabel.textColor = statusColor(code)
            statusCodeLabel.isHidden = false
        } else {
            statusCodeLabel.isHidden = true
        }

        // Status text
        if let text = run.statusText {
            statusTextLabel.stringValue = text
            statusTextLabel.isHidden = false
        } else {
            statusTextLabel.isHidden = true
        }

        // Duration
        if let duration = run.duration {
            durationLabel.stringValue = "\(Int(duration * 1000))ms"
            durationLabel.isHidden = false
        } else {
            durationLabel.isHidden = true
        }

        // Size
        if let size = run.size {
            sizeLabel.stringValue = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .memory)
            sizeLabel.isHidden = false
        } else {
            sizeLabel.isHidden = true
        }

        // Tab selection
        for (i, tab) in InspectorTab.allCases.enumerated() {
            tabButtonViews[i].isSelected = (tab == selectedTab)
        }
    }

    private func statusColor(_ code: Int) -> NSColor {
        switch code {
        case 200..<300: return .systemGreen
        case 300..<400: return .systemYellow
        case 400..<500: return .systemOrange
        case 500..<600: return .systemRed
        default: return .secondaryLabelColor
        }
    }
}

// MARK: - Hover Icon Button (matches courierHover SwiftUI style)

private final class HoverIconButtonView: NSView {
    var onTap: (() -> Void)?

    private let imageView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    init(symbolName: String, accessibilityLabel: String, tooltip: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = tooltip
        setContentHuggingPriority(.required, for: .horizontal)

        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 30)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let opacity: CGFloat = isPressed ? 0.15 : isHovered ? 0.08 : 0
        if opacity > 0 {
            let bgColor = NSColor.labelColor.withAlphaComponent(opacity)
            let path = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
            bgColor.setFill()
            path.fill()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onTap?()
        }
    }
}

// MARK: - Custom Tab Button (matches RequestSectionTabBar style)

private final class InspectorTabButtonView: NSView {
    let title: String
    var isSelected: Bool = false { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: NSSize {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let size = (title as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(size.width) + 24, height: 30)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isSelected {
            let bgColor = NSColor.labelColor.withAlphaComponent(0.08)
            let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
            bgColor.setFill()
            path.fill()
        }

        let font: NSFont = isSelected
            ? .systemFont(ofSize: 12, weight: .semibold)
            : .systemFont(ofSize: 12, weight: .regular)
        let color: NSColor = isSelected ? .labelColor : .secondaryLabelColor

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (title as NSString).size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        (title as NSString).draw(at: point, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }
}
