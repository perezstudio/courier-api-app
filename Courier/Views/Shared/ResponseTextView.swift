import AppKit
import SwiftUI

/// A performant read-only text view backed by NSTextView with line numbers.
/// Displays pre-formatted (syntax-highlighted) attributed strings when available,
/// falling back to plain monospaced text.
struct ResponseTextView: NSViewRepresentable {
    /// Pre-formatted NSAttributedString archived as Data (preferred)
    var formattedData: Data?
    /// Plain text fallback
    var plainText: String?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        // Text wrapping: track view width, no horizontal overflow
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 4
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Line number gutter
        let gutterView = LineNumberGutterView(textView: textView)
        scrollView.verticalRulerView = gutterView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        applyContent(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let currentText = textView.textStorage?.string ?? ""
        let newText = plainText ?? ""

        if currentText != newText {
            applyContent(to: textView)
            textView.scrollToBeginningOfDocument(nil)

            if let gutter = scrollView.verticalRulerView as? LineNumberGutterView {
                gutter.needsDisplay = true
            }
        }
    }

    private func applyContent(to textView: NSTextView) {
        // Try pre-formatted first
        if let data = formattedData,
           let attributed = SyntaxHighlighter.unarchive(data) {
            textView.textStorage?.setAttributedString(attributed)
            return
        }

        // Fall back to plain monospaced text
        let text = plainText ?? ""
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let plain = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ])
        textView.textStorage?.setAttributedString(plain)
    }
}

// MARK: - Line Number Gutter

final class LineNumberGutterView: NSRulerView {
    private weak var textView: NSTextView?
    private let gutterFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let gutterTextColor = NSColor.tertiaryLabelColor
    private let gutterPadding: CGFloat = 8

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.ruleThickness = 36
        self.clientView = textView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textDidChange(_ notification: Notification) {
        updateThickness()
        needsDisplay = true
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    private func updateThickness() {
        guard let textView else { return }
        let lineCount = max(textView.string.components(separatedBy: "\n").count, 1)
        let digits = max(String(lineCount).count, 2)
        let sampleString = String(repeating: "8", count: digits) as NSString
        let size = sampleString.size(withAttributes: [.font: gutterFont])
        let newThickness = size.width + gutterPadding * 2
        if abs(ruleThickness - newThickness) > 1 {
            ruleThickness = newThickness
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )

        let content = textView.string as NSString
        let textInset = textView.textContainerInset

        var lineNumber = 1
        content.substring(to: visibleCharRange.location)
            .enumerateLines { _, _ in lineNumber += 1 }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: gutterTextColor,
        ]

        var index = visibleCharRange.location
        while index < NSMaxRange(visibleCharRange) {
            let lineRange = content.lineRange(for: NSRange(location: index, length: 0))

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange,
                actualCharacterRange: nil
            )
            let lineRect = layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textContainer
            )

            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attrs)
            let yPos = lineRect.origin.y + textInset.height - visibleRect.origin.y
                + (lineRect.height - labelSize.height) / 2

            label.draw(
                at: NSPoint(
                    x: ruleThickness - labelSize.width - gutterPadding,
                    y: yPos
                ),
                withAttributes: attrs
            )

            lineNumber += 1
            index = NSMaxRange(lineRange)
        }
    }
}
