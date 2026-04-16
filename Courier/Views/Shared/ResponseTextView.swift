import AppKit
import SwiftUI

/// A performant read-only text view backed by NSTextView with line numbers.
/// Uses scroll-driven lazy syntax highlighting — only the visible viewport is highlighted.
/// Large responses are truncated for display to avoid layout stalls.
struct ResponseTextView: NSViewRepresentable {
    var plainText: String?
    var contentType: String?

    static let displayCharLimit = 500_000

    var isTruncated: Bool {
        guard let text = plainText else { return false }
        return text.count > Self.displayCharLimit
    }

    private var displayText: String {
        guard let text = plainText else { return "" }
        guard text.count > Self.displayCharLimit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: Self.displayCharLimit)
        let truncated = text[text.startIndex ..< endIndex]
        if let lastNewline = truncated.lastIndex(of: "\n") {
            return String(truncated[truncated.startIndex ... lastNewline])
        }
        return String(truncated)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

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

        applyContent(to: textView, coordinator: context.coordinator)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let newText = plainText ?? ""
        let currentAppearance = NSApp.effectiveAppearance.name
        let appearanceChanged = context.coordinator.lastAppearance != currentAppearance

        // Fast-path: check length first before expensive full string comparison
        let textChanged: Bool
        if let lastText = context.coordinator.lastText {
            textChanged = lastText.count != newText.count || lastText != newText
        } else {
            textChanged = !newText.isEmpty
        }

        if textChanged {
            context.coordinator.lastAppearance = currentAppearance
            context.coordinator.lastText = newText
            applyContent(to: textView, coordinator: context.coordinator)
        } else if appearanceChanged {
            context.coordinator.lastAppearance = currentAppearance
            context.coordinator.resetHighlighting(contentType: contentType)
            if let textStorage = textView.textStorage {
                let theme = SyntaxTheme.current()
                textStorage.beginEditing()
                textStorage.addAttributes([
                    .foregroundColor: theme.defaultColor,
                    .font: theme.font,
                ], range: NSRange(location: 0, length: textStorage.length))
                textStorage.endEditing()
            }
            Self.highlightVisibleRange(textView: textView, coordinator: context.coordinator)
        }
    }

    private func applyContent(to textView: NSTextView, coordinator: Coordinator) {
        let text = displayText
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // Remove old scroll observer
        coordinator.removeScrollObserver()

        // Build line index for O(log n) gutter lookups
        coordinator.rebuildLineIndex(for: text)

        // Set plain text immediately
        let plain = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ])
        textView.textStorage?.setAttributedString(plain)
        textView.scrollToBeginningOfDocument(nil)

        if let gutter = textView.enclosingScrollView?.verticalRulerView as? LineNumberGutterView {
            gutter.lineStartOffsets = coordinator.lineStartOffsets
            gutter.needsDisplay = true
        }

        // Set up lazy highlighting
        coordinator.resetHighlighting(contentType: contentType)

        guard !text.isEmpty else { return }

        // Highlight initial visible range
        Self.highlightVisibleRange(textView: textView, coordinator: coordinator)

        // Observe scroll to highlight new ranges
        if let contentView = textView.enclosingScrollView?.contentView {
            contentView.postsBoundsChangedNotifications = true
            coordinator.scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak textView] _ in
                guard let textView else { return }
                Self.highlightVisibleRange(textView: textView, coordinator: coordinator)
            }
        }
    }

    /// Highlights only the visible range (with buffer) that hasn't been highlighted yet.
    private static func highlightVisibleRange(textView: NSTextView, coordinator: Coordinator) {
        guard let highlighter = coordinator.highlighter,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage,
              textStorage.length > 0 else { return }

        let scrollView = textView.enclosingScrollView
        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        // Add buffer of 2000 chars on each side for smooth scrolling
        let bufferSize = 2000
        let start = max(0, visibleCharRange.location - bufferSize)
        let end = min(textStorage.length, NSMaxRange(visibleCharRange) + bufferSize)
        let bufferedRange = NSRange(location: start, length: end - start)

        // Check which parts of this range haven't been highlighted yet
        let bufferedSet = IndexSet(integersIn: bufferedRange.location ..< NSMaxRange(bufferedRange))
        let unhighlighted = bufferedSet.subtracting(coordinator.highlightedRanges)

        guard !unhighlighted.isEmpty else { return }

        // Highlight each contiguous subrange
        for range in unhighlighted.rangeView {
            let nsRange = NSRange(location: range.lowerBound, length: range.count)
            highlighter.highlight(textStorage, in: nsRange)
        }

        // Mark as highlighted
        coordinator.highlightedRanges.formUnion(bufferedSet)
    }

    // MARK: - Coordinator

    final class Coordinator {
        var lastAppearance: NSAppearance.Name?
        var lastText: String?
        var highlighter: SyntaxHighlighter?
        var highlightedRanges = IndexSet()
        var scrollObserver: NSObjectProtocol?
        var lineStartOffsets: [Int] = [0]

        /// Build sorted array of character offsets for each line start.
        func rebuildLineIndex(for text: String) {
            var offsets = [0]
            let ns = text as NSString
            var index = 0
            while index < ns.length {
                let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
                let nextLineStart = NSMaxRange(lineRange)
                if nextLineStart > index, nextLineStart < ns.length {
                    offsets.append(nextLineStart)
                }
                index = nextLineStart
                if index == lineRange.location { break }
            }
            lineStartOffsets = offsets
        }

        func resetHighlighting(contentType: String?) {
            highlightedRanges = IndexSet()
            let theme = SyntaxTheme.current()
            let language = SyntaxLanguage.detect(from: contentType ?? "")
            highlighter = SyntaxHighlighter(theme: theme, language: language)
        }

        func removeScrollObserver() {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
                scrollObserver = nil
            }
        }

        deinit {
            removeScrollObserver()
        }
    }
}

// MARK: - Line Number Gutter

final class LineNumberGutterView: NSRulerView {
    private weak var textView: NSTextView?
    private let gutterFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let gutterTextColor = NSColor.tertiaryLabelColor
    private let gutterPadding: CGFloat = 8

    /// Pre-computed line start offsets for O(log n) line number lookup.
    var lineStartOffsets: [Int] = [0]

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
        let lineCount = max(lineStartOffsets.count, 1)
        let digits = max(String(lineCount).count, 2)
        let sampleString = String(repeating: "8", count: digits) as NSString
        let size = sampleString.size(withAttributes: [.font: gutterFont])
        let newThickness = size.width + gutterPadding * 2
        if abs(ruleThickness - newThickness) > 1 {
            ruleThickness = newThickness
        }
    }

    /// Binary search: find 1-based line number for a character offset.
    private func lineNumber(forCharOffset offset: Int) -> Int {
        var lo = 0, hi = lineStartOffsets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lineStartOffsets[mid] <= offset {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo // 1-based: count of offsets <= charOffset
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

        // O(log n) line number lookup instead of O(n) scan
        var currentLineNumber = lineNumber(forCharOffset: visibleCharRange.location)

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

            let label = "\(currentLineNumber)" as NSString
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

            currentLineNumber += 1
            index = NSMaxRange(lineRange)
        }
    }
}
