import AppKit

/// URL field that tints `{{variable}}` placeholders.
///
/// While the field is being edited the highlighting is applied to the field
/// editor's text storage — swapping in a whole attributed string on every
/// keystroke would reset the insertion point. When it is *not* being edited
/// there is no field editor, so the attributed value is set directly; without
/// that branch the URL would lose its coloring the moment focus left, which is
/// most of the time now that it lives in the toolbar.
@MainActor
final class VariableHighlightingTextField: NSTextField {

    var unresolvedNames: Set<String> = [] {
        didSet {
            guard unresolvedNames != oldValue else { return }
            applyHighlighting()
        }
    }

    func applyHighlighting() {
        if let editor = currentEditor() as? NSTextView, let storage = editor.textStorage {
            apply(to: storage, text: storage.string)
        } else {
            let attributed = NSMutableAttributedString(string: stringValue)
            attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))
            apply(to: attributed, text: stringValue)
            attributedStringValue = attributed
        }
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.labelColor,
            .font: font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        ]
    }

    private func apply(to storage: NSMutableAttributedString, text: String) {
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

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        // Re-apply against the attributed value now that the field editor is
        // gone, or the text reverts to plain.
        applyHighlighting()
    }
}
