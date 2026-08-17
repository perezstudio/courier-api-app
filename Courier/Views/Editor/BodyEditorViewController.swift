import AppKit

/// Body type selector plus whichever editor that type needs.
@MainActor
final class BodyEditorViewController: NSViewController {

    var onTypeChange: ((BodyType) -> Void)?
    var onContentChange: ((String) -> Void)?
    var onFormRowsChange: (([KeyValueRow]) -> Void)?

    private let typePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let prettifyButton = NSButton()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let container = NSView()

    private let codeView = CodeTextView()
    private let formTable = KeyValueTableViewController()
    private let emptyState = EmptyStateView(
        symbolName: "nosign",
        title: "No Body",
        subtitle: "This request sends no body."
    )
    private let binaryState = EmptyStateView(
        symbolName: "doc.badge.plus",
        title: "Binary Body",
        subtitle: "Choosing a file is added in a later phase."
    )

    private var bodyType: BodyType = .none

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
        setupLayout()
        showEditor(for: .none)
    }

    private func setupControls() {
        for type in BodyType.allCases {
            typePopUp.addItem(withTitle: type.displayName)
            typePopUp.lastItem?.representedObject = type.rawValue
        }
        typePopUp.target = self
        typePopUp.action = #selector(typeChanged)
        typePopUp.translatesAutoresizingMaskIntoConstraints = false
        typePopUp.setAccessibilityLabel("Body type")

        prettifyButton.title = "Format"
        prettifyButton.bezelStyle = .push
        prettifyButton.controlSize = .small
        prettifyButton.target = self
        prettifyButton.action = #selector(prettify)
        prettifyButton.translatesAutoresizingMaskIntoConstraints = false

        sizeLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        sizeLabel.textColor = .tertiaryLabelColor

        codeView.onTextChange = { [weak self] text in
            self?.updateSizeLabel(text)
            self?.onContentChange?(text)
        }

        formTable.onChange = { [weak self] rows in
            self?.onFormRowsChange?(rows)
        }
    }

    private func setupLayout() {
        let bar = NSStackView(views: [typePopUp, prettifyButton, sizeLabel])
        bar.orientation = .horizontal
        bar.spacing = Theme.Metrics.tightPadding
        bar.translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor, constant: Theme.Metrics.tightPadding),
            bar.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Theme.Metrics.standardPadding
            ),
            bar.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor,
                constant: -Theme.Metrics.standardPadding
            ),
            typePopUp.widthAnchor.constraint(equalToConstant: 150),

            container.topAnchor.constraint(
                equalTo: bar.bottomAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        addChild(formTable)
    }

    // MARK: - Content

    func configure(type: BodyType, content: String, formRows: [KeyValueRow]) {
        bodyType = type
        if let index = BodyType.allCases.firstIndex(of: type) {
            typePopUp.selectItem(at: index)
        }
        codeView.string = content
        codeView.language = type.syntax
        formTable.setRows(formRows)
        updateSizeLabel(content)
        showEditor(for: type)
    }

    private func showEditor(for type: BodyType) {
        for subview in container.subviews {
            subview.removeFromSuperview()
        }

        let child: NSView
        switch type {
        case .none:
            child = emptyState
        case .binary:
            child = binaryState
        case .formData, .urlEncoded:
            child = formTable.view
        default:
            child = codeView
        }

        child.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: container.topAnchor),
            child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        prettifyButton.isHidden = type.syntax == nil
        sizeLabel.isHidden = !type.isTextual
    }

    private func updateSizeLabel(_ text: String) {
        let bytes = text.utf8.count
        sizeLabel.stringValue = ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .binary
        )
    }

    // MARK: - Actions

    @objc private func typeChanged() {
        guard
            let raw = typePopUp.selectedItem?.representedObject as? String,
            let type = BodyType(rawValue: raw)
        else { return }

        bodyType = type
        codeView.language = type.syntax
        showEditor(for: type)
        onTypeChange?(type)
    }

    /// Pretty-prints JSON. Invalid JSON is left untouched rather than replaced
    /// with an error — the user is likely mid-edit.
    @objc private func prettify() {
        guard bodyType.syntax == .json else { return }
        let text = codeView.string
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            ),
            let formatted = String(data: pretty, encoding: .utf8)
        else {
            NSSound.beep()
            return
        }

        codeView.string = formatted
        updateSizeLabel(formatted)
        onContentChange?(formatted)
    }
}
