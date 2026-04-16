import AppKit

/// Pure AppKit inspector panel. Observes InspectorViewModel via withObservationTracking
/// and updates views imperatively — no SwiftUI diffing overhead.
final class InspectorViewController: NSViewController {
    var viewModel: InspectorViewModel
    var onToggleInspector: (() -> Void)?

    // MARK: - Subviews

    private let toolbarView = InspectorToolbarView()
    private let separator = NSBox()
    private let bodyScrollView: NSScrollView
    private let bodyTextView: NSTextView
    private let headersVC = InspectorHeadersViewController()

    // State views
    private let loadingContainer = NSView()
    private let errorContainer = NSView()
    private let emptyContainer = NSView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let errorIcon = NSImageView()

    // MARK: - Text view state (transplanted from ResponseTextView.Coordinator)

    private var lastRunId: UUID?
    private var lastAppearance: NSAppearance.Name?
    private var highlighter: SyntaxHighlighter?
    private var highlightedRanges = IndexSet()
    private var scrollObserver: NSObjectProtocol?
    private var lineStartOffsets: [Int] = [0]
    private var pendingBodyWorkItem: DispatchWorkItem?

    // MARK: - Init

    init(viewModel: InspectorViewModel) {
        self.viewModel = viewModel

        // Create text view + scroll view
        let scrollView = NSTextView.scrollableTextView()
        self.bodyScrollView = scrollView
        self.bodyTextView = scrollView.documentView as! NSTextView

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    deinit {
        removeScrollObserver()
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        setupTextView()
        setupStateViews()
        setupLayout()
        setupToolbarActions()

        addChild(headersVC)
        headersVC.view.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateContent()
        startObserving()
    }

    // MARK: - Observation

    private func startObserving() {
        withObservationTracking {
            // Only observe ViewModel's own properties — NOT SwiftData model properties.
            // SwiftData @Model properties can fire spurious change notifications on auto-save,
            // causing infinite observation loops. The version counter is bumped explicitly
            // by code that changes the run or its status.
            _ = self.viewModel.version
            _ = self.viewModel.selectedTab
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateContent()
                self?.startObserving()
            }
        }
    }

    // MARK: - Content Update

    private func updateContent() {
        let run = viewModel.activeRun

        // Determine which state to show
        if let run {
            switch run.status {
            case .completed, .failed:
                if run.statusCode != nil {
                    showResponseState(run)
                } else {
                    showErrorState(run.errorMessage ?? "Unknown error")
                }
            case .pending, .running:
                showLoadingState()
            }
        } else {
            showEmptyState()
        }
    }

    private func showResponseState(_ run: APICallRun) {
        hideAllStates()
        toolbarView.isHidden = false
        separator.isHidden = false
        toolbarView.update(run: run, selectedTab: viewModel.selectedTab)

        switch viewModel.selectedTab {
        case .body:
            showBodyContent(run)
            headersVC.view.isHidden = true
        case .headers:
            bodyScrollView.isHidden = true
            headersVC.view.isHidden = false
            let headers = run.responseHeaders?.decoded ?? [:]
            headersVC.setHeaders(headers)
        }
    }

    private func showBodyContent(_ run: APICallRun) {
        let newRunId = run.id
        let currentAppearance = NSApp.effectiveAppearance.name
        let appearanceChanged = lastAppearance != currentAppearance

        if newRunId != lastRunId {
            // New run — load text off main thread
            lastRunId = newRunId
            lastAppearance = currentAppearance

            // Cancel any in-flight body preparation
            pendingBodyWorkItem?.cancel()

            if let body = run.responseBody, let bodyString = body.bodyString {
                let contentType = run.responseHeaders?.decoded["Content-Type"]

                // Show body scroll view with a temporary "loading" text while we prepare
                bodyScrollView.isHidden = false
                let loadingAttr = NSAttributedString(
                    string: "Loading response…",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                    ]
                )
                bodyTextView.textStorage?.setAttributedString(loadingAttr)

                // Prepare text data on background thread
                let workItem = DispatchWorkItem { [weak self] in
                    // Heavy work: build line index + attributed string off main thread
                    let offsets = Self.buildLineIndex(for: bodyString)
                    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    let attrString = NSAttributedString(string: bodyString, attributes: [
                        .font: font,
                        .foregroundColor: NSColor.labelColor,
                    ])

                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.lastRunId == newRunId else { return }
                        self.applyPreparedContent(
                            attrString,
                            lineOffsets: offsets,
                            contentType: contentType
                        )
                    }
                }
                pendingBodyWorkItem = workItem
                DispatchQueue.global(qos: .userInitiated).async(execute: workItem)

            } else if let body = run.responseBody, let rawBody = body.rawBody {
                bodyScrollView.isHidden = false
                let plain = NSAttributedString(
                    string: "\(rawBody.count) bytes (binary)",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
                bodyTextView.textStorage?.setAttributedString(plain)
            } else {
                bodyScrollView.isHidden = false
                let plain = NSAttributedString(
                    string: "No body",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                    ]
                )
                bodyTextView.textStorage?.setAttributedString(plain)
            }
        } else if appearanceChanged {
            // Same run, appearance changed — re-highlight
            lastAppearance = currentAppearance
            bodyScrollView.isHidden = false
            let contentType = run.responseHeaders?.decoded["Content-Type"]
            resetHighlighting(contentType: contentType)

            if let textStorage = bodyTextView.textStorage {
                let theme = SyntaxTheme.current()
                textStorage.beginEditing()
                textStorage.addAttributes([
                    .foregroundColor: theme.defaultColor,
                    .font: theme.font,
                ], range: NSRange(location: 0, length: textStorage.length))
                textStorage.endEditing()
            }
            highlightVisibleRange()
        } else {
            // Same run, same appearance — just make sure body is visible
            bodyScrollView.isHidden = false
        }
    }

    private func showLoadingState() {
        hideAllStates()
        loadingContainer.isHidden = false
    }

    private func showErrorState(_ error: String) {
        hideAllStates()
        errorLabel.stringValue = error
        errorContainer.isHidden = false
    }

    private func showEmptyState() {
        hideAllStates()
        clearBodyState()
        emptyContainer.isHidden = false
    }

    private func hideAllStates() {
        toolbarView.isHidden = true
        separator.isHidden = true
        bodyScrollView.isHidden = true
        headersVC.view.isHidden = true
        loadingContainer.isHidden = true
        errorContainer.isHidden = true
        emptyContainer.isHidden = true
    }

    /// Release all heavy text content and associated state.
    private func clearBodyState() {
        pendingBodyWorkItem?.cancel()
        pendingBodyWorkItem = nil
        removeScrollObserver()
        lastRunId = nil
        lastAppearance = nil
        highlighter = nil
        highlightedRanges = IndexSet()
        lineStartOffsets = [0]
        bodyTextView.textStorage?.setAttributedString(NSAttributedString())
        headersVC.setHeaders([:])
    }

    // MARK: - Text View Setup (transplanted from ResponseTextView)

    private func setupTextView() {
        bodyTextView.isEditable = false
        bodyTextView.isSelectable = true
        bodyTextView.isRichText = true
        bodyTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        bodyTextView.backgroundColor = .clear
        bodyTextView.drawsBackground = false
        bodyTextView.textContainerInset = NSSize(width: 4, height: 8)
        bodyTextView.isAutomaticQuoteSubstitutionEnabled = false
        bodyTextView.isAutomaticDashSubstitutionEnabled = false
        bodyTextView.isAutomaticTextReplacementEnabled = false
        bodyTextView.isAutomaticSpellingCorrectionEnabled = false
        bodyTextView.isAutomaticTextCompletionEnabled = false
        bodyTextView.isAutomaticLinkDetectionEnabled = false

        // Text wrapping
        bodyTextView.isHorizontallyResizable = false
        bodyTextView.textContainer?.widthTracksTextView = true
        bodyTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        bodyTextView.textContainer?.lineFragmentPadding = 4
        bodyTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Critical: lazy layout — only lay out visible portion, not entire document
        bodyTextView.layoutManager?.allowsNonContiguousLayout = true

        bodyScrollView.hasVerticalScroller = true
        bodyScrollView.hasHorizontalScroller = false
        bodyScrollView.autohidesScrollers = true
        bodyScrollView.drawsBackground = false
        bodyScrollView.borderType = .noBorder

        // Line number gutter
        let gutterView = LineNumberGutterView(textView: bodyTextView)
        bodyScrollView.verticalRulerView = gutterView
        bodyScrollView.hasVerticalRuler = true
        bodyScrollView.rulersVisible = true
    }

    // MARK: - State View Setup

    private func setupStateViews() {
        // Separator
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Loading state
        loadingContainer.translatesAutoresizingMaskIntoConstraints = false
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let loadingLabel = NSTextField(labelWithString: "Sending...")
        loadingLabel.font = .systemFont(ofSize: 13)
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false

        loadingContainer.addSubview(spinner)
        loadingContainer.addSubview(loadingLabel)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: loadingContainer.centerYAnchor, constant: -12),
            loadingLabel.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
        ])

        // Error state
        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
        errorIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        errorIcon.contentTintColor = .systemRed
        errorIcon.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.alignment = .center
        errorLabel.maximumNumberOfLines = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        errorContainer.addSubview(errorIcon)
        errorContainer.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorIcon.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            errorIcon.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor, constant: -20),
            errorLabel.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            errorLabel.topAnchor.constraint(equalTo: errorIcon.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: errorContainer.leadingAnchor, constant: 12),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: errorContainer.trailingAnchor, constant: -12),
        ])

        // Empty state
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        let emptyIcon = NSImageView()
        emptyIcon.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: nil)
        emptyIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        emptyIcon.contentTintColor = .tertiaryLabelColor
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false

        let emptyLabel = NSTextField(labelWithString: "Send a request to see the response")
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyContainer.addSubview(emptyIcon)
        emptyContainer.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyIcon.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            emptyIcon.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: 12),
        ])
    }

    // MARK: - Layout

    private func setupLayout() {
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        bodyScrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(toolbarView)
        view.addSubview(separator)
        view.addSubview(bodyScrollView)
        view.addSubview(headersVC.view)
        view.addSubview(loadingContainer)
        view.addSubview(errorContainer)
        view.addSubview(emptyContainer)

        NSLayoutConstraint.activate([
            // Toolbar
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Separator
            separator.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Body scroll view
            bodyScrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            bodyScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bodyScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bodyScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Headers view
            headersVC.view.topAnchor.constraint(equalTo: separator.bottomAnchor),
            headersVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headersVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headersVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Loading
            loadingContainer.topAnchor.constraint(equalTo: view.topAnchor),
            loadingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Error
            errorContainer.topAnchor.constraint(equalTo: view.topAnchor),
            errorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Empty
            emptyContainer.topAnchor.constraint(equalTo: view.topAnchor),
            emptyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Per-Tab VM Switching

    func setViewModel(_ newVM: InspectorViewModel) {
        viewModel = newVM
        clearBodyState()
        updateContent()
        startObserving()
    }

    private func setupToolbarActions() {
        toolbarView.onTabChanged = { [weak self] tab in
            self?.viewModel.selectedTab = tab
        }
        toolbarView.onToggleInspector = { [weak self] in
            self?.onToggleInspector?()
        }
    }

    // MARK: - Text Content

    /// Called on main thread with data prepared in background.
    private func applyPreparedContent(
        _ attrString: NSAttributedString,
        lineOffsets: [Int],
        contentType: String?
    ) {
        removeScrollObserver()

        lineStartOffsets = lineOffsets
        bodyTextView.textStorage?.setAttributedString(attrString)
        bodyTextView.scrollToBeginningOfDocument(nil)

        if let gutter = bodyScrollView.verticalRulerView as? LineNumberGutterView {
            gutter.lineStartOffsets = lineStartOffsets
            gutter.needsDisplay = true
        }

        resetHighlighting(contentType: contentType)

        guard attrString.length > 0 else { return }

        highlightVisibleRange()

        // Observe scroll for lazy highlighting
        if let contentView = bodyScrollView.contentView as? NSClipView {
            contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self] _ in
                self?.highlightVisibleRange()
            }
        }
    }

    private func highlightVisibleRange() {
        guard let highlighter,
              let layoutManager = bodyTextView.layoutManager,
              let textContainer = bodyTextView.textContainer,
              let textStorage = bodyTextView.textStorage,
              textStorage.length > 0 else { return }

        let visibleRect = bodyScrollView.contentView.bounds
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let bufferSize = 2000
        let start = max(0, visibleCharRange.location - bufferSize)
        let end = min(textStorage.length, NSMaxRange(visibleCharRange) + bufferSize)
        let bufferedRange = NSRange(location: start, length: end - start)

        let bufferedSet = IndexSet(integersIn: bufferedRange.location..<NSMaxRange(bufferedRange))
        let unhighlighted = bufferedSet.subtracting(highlightedRanges)

        guard !unhighlighted.isEmpty else { return }

        for range in unhighlighted.rangeView {
            let nsRange = NSRange(location: range.lowerBound, length: range.count)
            highlighter.highlight(bodyTextView.textStorage!, in: nsRange)
        }

        highlightedRanges.formUnion(bufferedSet)
    }

    /// Build sorted array of line-start character offsets. Thread-safe (pure function).
    private static func buildLineIndex(for text: String) -> [Int] {
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
        return offsets
    }

    private func resetHighlighting(contentType: String?) {
        highlightedRanges = IndexSet()
        let theme = SyntaxTheme.current()
        let language = SyntaxLanguage.detect(from: contentType ?? "")
        highlighter = SyntaxHighlighter(theme: theme, language: language)
    }

    private func removeScrollObserver() {
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollObserver = nil
        }
    }
}
