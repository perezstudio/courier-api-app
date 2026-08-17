import AppKit

/// The inspector column: one of three modes, filling the pane.
///
/// The mode is chosen from the toolbar rather than from a tab bar inside the
/// pane, and the response status now lives in the toolbar too — so this
/// controller is purely a container that swaps children.
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

        var symbolName: String {
            switch self {
            case .results: "doc.plaintext"
            case .timeline: "chart.bar.xaxis"
            case .history: "clock.arrow.circlepath"
            }
        }
    }

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
        setupContainer()

        for child in [resultsViewController, timelineViewController, historyViewController]
            as [NSViewController] {
            addChild(child)
        }
        setMode(.results)
        showIdle()
    }

    private func setupContainer() {
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            // Deliberately the view's own top, not the safe-area guide: under a
            // unified toolbar the scroll views are meant to run *underneath* it.
            // Their `automaticallyAdjustsContentInsets` keeps the text itself
            // clear of the toolbar, while the overlap is what makes AppKit draw
            // the titlebar separator and the glass edge. Pinning to the safe
            // area instead leaves nothing under the toolbar, and the separator
            // never appears no matter what `titlebarSeparatorStyle` asks for.
            container.topAnchor.constraint(equalTo: view.topAnchor),
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
        // Only scroll-backed modes may underlap the toolbar. The timeline is a
        // plain chart with no content inset of its own, so it is held to the
        // safe area or its top bar would slide beneath the toolbar.
        let top = mode == .timeline
            ? container.safeAreaLayoutGuide.topAnchor
            : container.topAnchor
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: top),
            child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    func setResultsSection(_ section: ResultsViewController.Section) {
        resultsViewController.setSection(section)
    }

    // MARK: - States
    //
    // The status line itself is reported to the toolbar chip by
    // RequestSessionController; these only drive the pane's contents.

    func showIdle() {
        resultsViewController.setBody(nil, contentType: nil)
        resultsViewController.setHeaders([])
        timelineViewController.setTiming(nil)
    }

    func showSending() {
        // The spinner lives in the toolbar chip; nothing to change here.
    }

    func showResult(_ result: ExecutionResult) {
        let contentType = result.headers
            .first { $0.name.lowercased() == "content-type" }?
            .value

        resultsViewController.setBody(result.body, contentType: contentType)
        resultsViewController.setHeaders(result.headers)
        timelineViewController.setTiming(result.timing)
    }

    func showError(_ message: String) {
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
