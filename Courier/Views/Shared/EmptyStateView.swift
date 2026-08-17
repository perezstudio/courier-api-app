import AppKit

/// Centered symbol, title, optional subtitle and button.
///
/// One of the three custom views the plan allows (REQUIREMENTS.md §7.4): macOS
/// ships no empty-state control. This is `NSStackView` composition rather than
/// custom drawing, so it inherits appearance handling for free.
final class EmptyStateView: NSView {

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton()
    private let stack = NSStackView()

    private var action: (() -> Void)?

    init(
        symbolName: String,
        title: String,
        subtitle: String? = nil,
        buttonTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        super.init(frame: .zero)
        self.action = action
        setup(symbolName: symbolName, title: title, subtitle: subtitle, buttonTitle: buttonTitle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(symbolName: String, title: String, subtitle: String?, buttonTitle: String?) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        imageView.contentTintColor = .tertiaryLabelColor

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.stringValue = title
        titleLabel.alignment = .center

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Theme.Metrics.tightPadding
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(titleLabel)

        if let subtitle {
            subtitleLabel.stringValue = subtitle
            subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            subtitleLabel.textColor = .tertiaryLabelColor
            subtitleLabel.alignment = .center
            subtitleLabel.preferredMaxLayoutWidth = 260
            stack.addArrangedSubview(subtitleLabel)
        }

        if let buttonTitle {
            button.title = buttonTitle
            button.bezelStyle = .push
            button.target = self
            button.action = #selector(buttonTapped)
            stack.setCustomSpacing(Theme.Metrics.standardPadding, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(button)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])
    }

    @objc private func buttonTapped() {
        action?()
    }

    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
    }
}
