import AppKit

/// A code editor: monospaced `NSTextView` on TextKit 2, line-number ruler, and
/// syntax highlighting applied through the text storage.
@MainActor
final class CodeTextView: NSView {

    /// Bodies past this size are left unhighlighted. Tokenizing a multi-megabyte
    /// minified payload on every keystroke would stall the main thread, and the
    /// text is still fully editable without color.
    private static let highlightSizeLimit = 200_000

    let textView: NSTextView
    private let scrollView = NSScrollView()
    private var ruler: LineNumberRulerView?

    var onTextChange: ((String) -> Void)?

    var language: SyntaxHighlighter.Language? {
        didSet { rehighlight() }
    }

    var isEditable: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    var string: String {
        get { textView.string }
        set {
            guard textView.string != newValue else { return }
            textView.string = newValue
            rehighlight()
            ruler?.needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        scrollView.documentView = textView
        super.init(frame: frameRect)
        setup(scroll)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(_ providedScroll: NSScrollView) {
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.backgroundColor = .textBackgroundColor
        textView.delegate = self
        textView.autoresizingMask = [.width]

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        self.ruler = ruler

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Highlighting

    private func rehighlight() {
        guard let storage = textView.textStorage else { return }
        let text = storage.string
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: fullRange)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        if let language, text.utf16.count <= Self.highlightSizeLimit {
            let highlighter = SyntaxHighlighter(language: language)
            for token in highlighter.tokens(in: text) {
                guard NSMaxRange(token.range) <= storage.length else { continue }
                storage.addAttribute(
                    .foregroundColor,
                    value: SyntaxHighlighter.color(for: token.kind),
                    range: token.range
                )
            }
        }
        storage.endEditing()
    }

    /// Re-applies colors after an appearance change; system colors resolve
    /// differently in light and dark, and stored attributes do not update
    /// themselves.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rehighlight()
    }
}

extension CodeTextView: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        rehighlight()
        ruler?.needsDisplay = true
        onTextChange?(textView.string)
    }
}

/// Line numbers down the left edge.
@MainActor
final class LineNumberRulerView: NSRulerView {

    private weak var codeTextView: NSTextView?

    init(textView: NSTextView) {
        self.codeTextView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 34
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            let textView = codeTextView,
            let layoutManager = textView.layoutManager,
            let container = textView.textContainer
        else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        let content = textView.string as NSString
        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let inset = textView.textContainerInset.height

        // Walk only the lines actually on screen — numbering the whole document
        // would make scrolling a large body quadratic.
        var lineNumber = 1
        var characterIndex = 0
        while characterIndex < content.length {
            let lineRange = content.lineRange(for: NSRange(location: characterIndex, length: 0))
            if NSLocationInRange(lineRange.location, visibleGlyphs)
                || NSLocationInRange(NSMaxRange(lineRange) - 1, visibleGlyphs) {
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: lineRange.location, length: 0),
                    actualCharacterRange: nil
                )
                let lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphRange.location,
                    effectiveRange: nil
                )
                let y = lineRect.minY + inset - visibleRect.minY
                let label = "\(lineNumber)" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(x: ruleThickness - size.width - 6, y: y + 1),
                    withAttributes: attributes
                )
            }

            characterIndex = NSMaxRange(lineRange)
            lineNumber += 1
            if lineRange.length == 0 { break }
        }
    }
}
