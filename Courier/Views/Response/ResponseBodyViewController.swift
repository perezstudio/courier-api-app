import AppKit

/// Renders a response body: pretty, raw, or preview.
@MainActor
final class ResponseBodyViewController: NSViewController {

    private enum Mode: Int {
        case pretty
        case raw
        case preview
    }

    private let modeControl = NSSegmentedControl(
        labels: ["Pretty", "Raw", "Preview"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let searchField = NSSearchField()
    private let container = NSView()

    private let codeView = CodeTextView()
    private let imageView = NSImageView()
    private let emptyState = EmptyStateView(
        symbolName: "doc.text",
        title: "No Response Yet",
        subtitle: "Send the request to see its response here."
    )

    private var body: Data?
    private var presentation: ResponseFormatter.Presentation = .text
    private var prettyText: String?
    private var rawText: String?
    private var mode: Mode = .pretty

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
        setupLayout()
        render()
    }

    private func setupControls() {
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.controlSize = .small
        modeControl.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Find in response"
        searchField.controlSize = .small
        searchField.target = self
        searchField.action = #selector(findInResponse)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        codeView.isEditable = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
    }

    private func setupLayout() {
        let bar = NSStackView(views: [modeControl, searchField])
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
                equalTo: view.trailingAnchor,
                constant: -Theme.Metrics.standardPadding
            ),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),

            container.topAnchor.constraint(
                equalTo: bar.bottomAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Content

    func setBody(_ body: Data?, contentType: String?) {
        self.body = body

        guard let body else {
            prettyText = nil
            rawText = nil
            render()
            return
        }

        presentation = ResponseFormatter.presentation(contentType: contentType, body: body)
        let encoding = ResponseFormatter.charset(from: contentType)

        switch presentation {
        case .image:
            prettyText = nil
            rawText = nil
        case .binary:
            // Undecodable bytes still deserve to be inspectable.
            prettyText = ResponseFormatter.hexDump(body)
            rawText = prettyText
        default:
            rawText = ResponseFormatter.decodeText(body, encoding: encoding)
            prettyText = ResponseFormatter.prettyPrinted(body, presentation: presentation) ?? rawText
        }

        render()
    }

    private func render() {
        for subview in container.subviews {
            subview.removeFromSuperview()
        }

        guard let body, !body.isEmpty else {
            embed(emptyState)
            modeControl.isEnabled = false
            searchField.isEnabled = false
            return
        }

        modeControl.isEnabled = true
        searchField.isEnabled = presentation != .image

        if presentation == .image, mode != .raw {
            imageView.image = NSImage(data: body)
            embed(imageView)
            return
        }

        let text: String
        switch mode {
        case .pretty: text = prettyText ?? rawText ?? ""
        case .raw: text = rawText ?? ""
        case .preview: text = prettyText ?? rawText ?? ""
        }

        // Highlighting a huge body would stall the main thread; the size guard
        // in CodeTextView also applies, this just avoids the pretty-print.
        codeView.language = body.count <= ResponseFormatter.largeBodyThreshold
            ? syntaxLanguage
            : nil
        codeView.string = text
        embed(codeView)
    }

    private var syntaxLanguage: SyntaxHighlighter.Language? {
        switch presentation {
        case .json: .json
        case .xml, .html: .xml
        case .text, .image, .binary: nil
        }
    }

    private func embed(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: container.topAnchor),
            child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        mode = Mode(rawValue: modeControl.selectedSegment) ?? .pretty
        render()
    }

    @objc private func findInResponse() {
        let needle = searchField.stringValue
        guard !needle.isEmpty else { return }

        let haystack = codeView.textView.string as NSString
        let selectedEnd = NSMaxRange(codeView.textView.selectedRange())

        // Search forward from the selection, then wrap — the behavior every
        // find field on the platform has.
        var range = haystack.range(
            of: needle,
            options: [.caseInsensitive],
            range: NSRange(location: selectedEnd, length: haystack.length - selectedEnd)
        )
        if range.location == NSNotFound {
            range = haystack.range(of: needle, options: [.caseInsensitive])
        }

        guard range.location != NSNotFound else {
            NSSound.beep()
            return
        }
        codeView.textView.setSelectedRange(range)
        codeView.textView.scrollRangeToVisible(range)
        view.window?.makeFirstResponder(codeView.textView)
    }
}
