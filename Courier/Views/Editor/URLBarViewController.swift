import AppKit

/// Method popup, URL field, Send button. Spans the full content width so it
/// reads as belonging to both the editor and the response (§8.3).
@MainActor
final class URLBarViewController: NSViewController {

    var onMethodChange: ((String) -> Void)?
    var onURLChange: ((String) -> Void)?
    var onSend: (() -> Void)?

    private let methodPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let urlField = VariableHighlightingTextField()
    private let sendButton = NSButton()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
        setupLayout()
    }

    private func setupControls() {
        for method in Theme.Method.allCases {
            methodPopUp.addItem(withTitle: method.rawValue)
            // Colored menu titles make the method scannable in the popup, the
            // same signal the sidebar badge gives.
            methodPopUp.lastItem?.attributedTitle = NSAttributedString(
                string: method.rawValue,
                attributes: [
                    .foregroundColor: method.color,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                ]
            )
        }
        methodPopUp.target = self
        methodPopUp.action = #selector(methodChanged)
        methodPopUp.translatesAutoresizingMaskIntoConstraints = false
        methodPopUp.setAccessibilityLabel("HTTP method")

        urlField.placeholderString = "https://api.example.com/path"
        urlField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        urlField.delegate = self
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.setAccessibilityLabel("Request URL")

        sendButton.title = "Send"
        sendButton.bezelStyle = .push
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = [.command]
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayout() {
        let stack = NSStackView(views: [methodPopUp, urlField, sendButton])
        stack.orientation = .horizontal
        stack.spacing = Theme.Metrics.tightPadding
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .horizontal)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(separator)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Theme.Metrics.standardPadding
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Theme.Metrics.standardPadding
            ),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            methodPopUp.widthAnchor.constraint(equalToConstant: 104),
            sendButton.widthAnchor.constraint(equalToConstant: 72),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Content

    func configure(method: String, url: String) {
        methodPopUp.selectItem(withTitle: method)
        urlField.stringValue = url
        urlField.applyHighlighting()
    }

    /// Names of unresolved variables, dimmed differently in the field.
    func setUnresolvedVariables(_ names: Set<String>) {
        urlField.unresolvedNames = names
    }

    var isSendEnabled: Bool {
        get { sendButton.isEnabled }
        set { sendButton.isEnabled = newValue }
    }

    // MARK: - Actions

    @objc private func methodChanged() {
        guard let title = methodPopUp.titleOfSelectedItem else { return }
        onMethodChange?(title)
    }

    @objc private func sendTapped() {
        onSend?()
    }
}

extension URLBarViewController: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === urlField else { return }
        urlField.applyHighlighting()
        onURLChange?(field.stringValue)
    }
}

/// URL field that tints `{{variable}}` placeholders.
///
/// The highlighting is applied to the field editor's text storage rather than
/// by swapping in an attributed string, which would reset the insertion point
/// on every keystroke.
@MainActor
final class VariableHighlightingTextField: NSTextField {

    var unresolvedNames: Set<String> = [] {
        didSet { applyHighlighting() }
    }

    func applyHighlighting() {
        guard
            let editor = currentEditor() as? NSTextView,
            let storage = editor.textStorage
        else { return }

        let text = storage.string
        let full = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: full)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)

        for token in VariableTokenizer.tokens(in: text) {
            let range = NSRange(token.range, in: text)
            guard NSMaxRange(range) <= storage.length else { continue }
            // Unresolved placeholders read as a warning; resolved ones are just
            // a distinct token color.
            let color: NSColor = unresolvedNames.contains(token.name) ? .systemOrange : .systemPurple
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
        storage.endEditing()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { applyHighlighting() }
        return became
    }
}
