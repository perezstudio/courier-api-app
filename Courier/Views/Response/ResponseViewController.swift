import AppKit

/// The inspector column: a status bar over one of three modes.
///
/// The mode is chosen from the toolbar rather than from a tab bar inside the
/// pane, so this is a plain controller that swaps children — the previous
/// `NSTabViewController` would have drawn a second row of tabs directly under
/// the toolbar control driving it.
@MainActor
final class ResponseViewController: NSViewController {

    enum Mode: Int, CaseIterable {
        case results
        case timeline
        case history

        var label: String {
            switch self {
            case .results: "Results"
            case .timeline: "Timeline"
            case .history: "History"
            }
        }
    }

    private let statusBadge = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let statusBar = NSView()
    private let container = NSView()

    private let resultsViewController = ResultsViewController()
    private let timelineViewController = TimelineViewController()
    private let historyViewController: RunHistoryViewController

    private var mode: Mode = .results

    init(historyViewController: RunHistoryViewController) {
        self.historyViewController = historyViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupStatusBar()
        setupContainer()

        for child in [resultsViewController, timelineViewController, historyViewController] as [NSViewController] {
            addChild(child)
        }
        setMode(.results)
        showIdle()
    }

    private func setupStatusBar() {
        statusBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.textColor = .secondaryLabelColor
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        sizeLabel.textColor = .secondaryLabelColor

        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        progress.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [progress, statusBadge, durationLabel, sizeLabel])
        stack.orientation = .horizontal
        stack.spacing = Theme.Metrics.standardPadding
        stack.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(stack)
        statusBar.addSubview(separator)
        view.addSubview(statusBar)

        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 30),

            stack.leadingAnchor.constraint(
                equalTo: statusBar.leadingAnchor,
                constant: Theme.Metrics.standardPadding
            ),
            stack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: statusBar.trailingAnchor,
                constant: -Theme.Metrics.standardPadding
            ),

            separator.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: statusBar.bottomAnchor),
        ])
    }

    private func setupContainer() {
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: statusBar.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Mode

    func setMode(_ mode: Mode) {
        loadViewIfNeeded()
        self.mode = mode

        for subview in container.subviews {
            subview.removeFromSuperview()
        }

        let child: NSView
        switch mode {
        case .results: child = resultsViewController.view
        case .timeline: child = timelineViewController.view
        case .history: child = historyViewController.view
        }

        child.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: container.topAnchor),
            child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - States

    func showIdle() {
        progress.stopAnimation(nil)
        statusBadge.stringValue = ""
        durationLabel.stringValue = ""
        sizeLabel.stringValue = ""
        resultsViewController.setBody(nil, contentType: nil)
        resultsViewController.setHeaders([])
        timelineViewController.setTiming(nil)
    }

    func showSending() {
        progress.startAnimation(nil)
        statusBadge.stringValue = "Sending…"
        statusBadge.textColor = .secondaryLabelColor
        durationLabel.stringValue = ""
        sizeLabel.stringValue = ""
    }

    func showResult(_ result: ExecutionResult) {
        progress.stopAnimation(nil)

        statusBadge.stringValue = "\(result.statusCode) \(result.statusText)"
        statusBadge.textColor = Theme.color(forStatusCode: result.statusCode)
        durationLabel.stringValue = String(format: "%.0f ms", result.duration * 1000)
        sizeLabel.stringValue = ByteCountFormatter.string(
            fromByteCount: Int64(result.body.count),
            countStyle: .binary
        )

        let contentType = result.headers
            .first { $0.name.lowercased() == "content-type" }?
            .value

        resultsViewController.setBody(result.body, contentType: contentType)
        resultsViewController.setHeaders(result.headers)
        timelineViewController.setTiming(result.timing)
    }

    func showError(_ message: String) {
        progress.stopAnimation(nil)
        statusBadge.stringValue = "Failed"
        statusBadge.textColor = .systemRed
        durationLabel.stringValue = ""
        sizeLabel.stringValue = ""

        resultsViewController.setBody(Data(message.utf8), contentType: "text/plain")
        resultsViewController.setHeaders([])
        timelineViewController.setTiming(nil)
    }

    /// Restores a stored run, whose headers arrive as JSON rather than live
    /// values.
    func showStoredRun(
        summary: RunSummary,
        body: Data?,
        headersJSON: String?,
        timingJSON: String?
    ) {
        progress.stopAnimation(nil)

        if let code = summary.statusCode {
            statusBadge.stringValue = "\(code) \(summary.statusText ?? "")"
            statusBadge.textColor = Theme.color(forStatusCode: code)
        } else {
            statusBadge.stringValue = summary.errorMessage == nil ? "—" : "Failed"
            statusBadge.textColor = summary.errorMessage == nil ? .secondaryLabelColor : .systemRed
        }

        durationLabel.stringValue = summary.duration.map { String(format: "%.0f ms", $0 * 1000) } ?? ""
        sizeLabel.stringValue = summary.size.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .binary)
        } ?? ""

        let headers = ExecutionResult.decodeHeaders(from: headersJSON)
        let contentType = headers.first { $0.name.lowercased() == "content-type" }?.value

        resultsViewController.setBody(body, contentType: contentType)
        resultsViewController.setHeaders(headers)
        timelineViewController.setTiming(TimingBreakdown.decode(from: timingJSON))
    }
}

/// Timeline mode: the phase chart.
@MainActor
final class TimelineViewController: NSViewController {

    private let chart = TimelineChartView()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        chart.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chart)
        NSLayoutConstraint.activate([
            chart.topAnchor.constraint(equalTo: view.topAnchor),
            chart.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chart.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func setTiming(_ timing: TimingBreakdown?) {
        chart.setTiming(timing)
    }
}
