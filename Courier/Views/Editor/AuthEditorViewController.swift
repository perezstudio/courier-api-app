import AppKit

/// Auth type selector with a form per type.
///
/// Secret fields are `NSSecureTextField` and their values go to the Keychain,
/// never to Core Data (REQUIREMENTS.md §6).
@MainActor
final class AuthEditorViewController: NSViewController {

    /// Called with the configuration and, when the user typed one, a new secret.
    var onChange: ((AuthConfiguration, String?) -> Void)?

    private let kindPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formStack = NSStackView()

    private let usernameField = NSTextField()
    private let secretField = NSSecureTextField()
    private let apiKeyNameField = NSTextField()
    private let apiKeyLocationPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let secretNote = NSTextField(wrappingLabelWithString: "")

    private var configuration = AuthConfiguration.empty

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
        setupLayout()
        rebuildForm()
    }

    private func setupControls() {
        for kind in AuthConfiguration.Kind.allCases {
            kindPopUp.addItem(withTitle: kind.displayName)
            kindPopUp.lastItem?.representedObject = kind.rawValue
        }
        kindPopUp.target = self
        kindPopUp.action = #selector(kindChanged)
        kindPopUp.translatesAutoresizingMaskIntoConstraints = false
        kindPopUp.setAccessibilityLabel("Auth type")

        for field in [usernameField, apiKeyNameField] {
            field.delegate = self
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
        }
        secretField.delegate = self
        usernameField.placeholderString = "Username"
        apiKeyNameField.placeholderString = "Key name"
        secretField.placeholderString = "Value"

        for location in AuthConfiguration.APIKeyLocation.allCases {
            apiKeyLocationPopUp.addItem(withTitle: location.displayName)
            apiKeyLocationPopUp.lastItem?.representedObject = location.rawValue
        }
        apiKeyLocationPopUp.target = self
        apiKeyLocationPopUp.action = #selector(fieldChanged)

        secretNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        secretNote.textColor = .tertiaryLabelColor
        secretNote.stringValue = "Stored in your Keychain, not in the Courier library."
    }

    private func setupLayout() {
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = Theme.Metrics.tightPadding
        formStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(kindPopUp)
        view.addSubview(formStack)

        NSLayoutConstraint.activate([
            kindPopUp.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: Theme.Metrics.standardPadding
            ),
            kindPopUp.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Theme.Metrics.standardPadding
            ),
            kindPopUp.widthAnchor.constraint(equalToConstant: 180),

            formStack.topAnchor.constraint(
                equalTo: kindPopUp.bottomAnchor,
                constant: Theme.Metrics.standardPadding
            ),
            formStack.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Theme.Metrics.standardPadding
            ),
            formStack.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor,
                constant: -Theme.Metrics.standardPadding
            ),
            formStack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
    }

    // MARK: - Content

    func configure(_ configuration: AuthConfiguration, secret: String?) {
        self.configuration = configuration
        if let index = AuthConfiguration.Kind.allCases.firstIndex(of: configuration.kind) {
            kindPopUp.selectItem(at: index)
        }
        usernameField.stringValue = configuration.basicUsername
        apiKeyNameField.stringValue = configuration.apiKeyName
        secretField.stringValue = secret ?? ""
        if let index = AuthConfiguration.APIKeyLocation.allCases
            .firstIndex(of: configuration.apiKeyLocation) {
            apiKeyLocationPopUp.selectItem(at: index)
        }
        rebuildForm()
    }

    private func rebuildForm() {
        for subview in formStack.arrangedSubviews {
            formStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        switch configuration.kind {
        case .inherit:
            formStack.addArrangedSubview(
                label("Uses the authorization set on the parent folder or collection.")
            )
        case .none:
            formStack.addArrangedSubview(label("This request sends no authorization."))
        case .bearer:
            formStack.addArrangedSubview(labeledField("Token", secretField))
            formStack.addArrangedSubview(secretNote)
        case .basic:
            formStack.addArrangedSubview(labeledField("Username", usernameField))
            formStack.addArrangedSubview(labeledField("Password", secretField))
            formStack.addArrangedSubview(secretNote)
        case .apiKey:
            formStack.addArrangedSubview(labeledField("Key", apiKeyNameField))
            formStack.addArrangedSubview(labeledField("Value", secretField))
            formStack.addArrangedSubview(labeledField("Add to", apiKeyLocationPopUp))
            formStack.addArrangedSubview(secretNote)
        }
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        return field
    }

    private func labeledField(_ title: String, _ control: NSView) -> NSView {
        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        caption.textColor = .secondaryLabelColor

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let stack = NSStackView(views: [caption, control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    // MARK: - Actions

    @objc private func kindChanged() {
        guard
            let raw = kindPopUp.selectedItem?.representedObject as? String,
            let kind = AuthConfiguration.Kind(rawValue: raw)
        else { return }

        configuration.kind = kind
        rebuildForm()
        emit()
    }

    @objc private func fieldChanged() {
        configuration.basicUsername = usernameField.stringValue
        configuration.apiKeyName = apiKeyNameField.stringValue
        if let raw = apiKeyLocationPopUp.selectedItem?.representedObject as? String,
           let location = AuthConfiguration.APIKeyLocation(rawValue: raw) {
            configuration.apiKeyLocation = location
        }
        emit()
    }

    private func emit() {
        let secret = configuration.usesSecret ? secretField.stringValue : nil
        onChange?(configuration, secret)
    }
}

extension AuthEditorViewController: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ notification: Notification) {
        fieldChanged()
    }
}
