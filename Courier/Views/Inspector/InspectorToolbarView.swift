import AppKit

/// Pure AppKit toolbar showing status code, timing, size, and Body/Headers tab selector.
final class InspectorToolbarView: NSView {
    var onTabChanged: ((InspectorTab) -> Void)?

    // Left side
    private let statusCodeLabel = NSTextField(labelWithString: "")
    private let statusTextLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")

    // Right side
    private let segmentedControl = NSSegmentedControl()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupViews() {
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

        // Segmented control
        segmentedControl.segmentCount = InspectorTab.allCases.count
        for (i, tab) in InspectorTab.allCases.enumerated() {
            segmentedControl.setLabel(tab.rawValue, forSegment: i)
            segmentedControl.setWidth(0, forSegment: i) // auto-size
        }
        segmentedControl.segmentStyle = .roundRect
        segmentedControl.selectedSegment = 0
        segmentedControl.target = self
        segmentedControl.action = #selector(segmentChanged(_:))
        segmentedControl.controlSize = .small
        segmentedControl.font = .systemFont(ofSize: 11, weight: .regular)

        // Layout
        let mainStack = NSStackView(views: [leftStack, segmentedControl])
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

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        let tabs = InspectorTab.allCases
        guard sender.selectedSegment < tabs.count else { return }
        let tab = tabs[sender.selectedSegment]
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
        if let index = InspectorTab.allCases.firstIndex(of: selectedTab) {
            segmentedControl.selectedSegment = index
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
