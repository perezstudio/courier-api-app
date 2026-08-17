import AppKit

/// Status bar above Body · Headers · Cookies · Timeline · History.
@MainActor
final class ResponseSectionsTabViewController: NSViewController {

    private let statusBadge = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let statusBar = NSView()

    private let tabs = NSTabViewController()
    private let bodyViewController = ResponseBodyViewController()
    private let headersViewController = PairTableViewController(
        firstColumn: "Header",
        secondColumn: "Value"
    )
    private let cookiesViewController = CookiesViewController()
    private let timelineViewController = TimelineViewController()
    private let historyViewController: RunHistoryViewController

    var onSelectRun: ((UUID) -> Void)?

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
        setupTabs()
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
            statusBar.heightAnchor.constraint(equalToConstant: 32),

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

    private func setupTabs() {
        tabs.tabStyle = .segmentedControlOnTop
        tabs.transitionOptions = []

        addSection(bodyViewController, label: "Body")
        addSection(headersViewController, label: "Headers")
        addSection(cookiesViewController, label: "Cookies")
        addSection(timelineViewController, label: "Timeline")
        addSection(historyViewController, label: "History")

        addChild(tabs)
        let tabsView = tabs.view
        tabsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabsView)

        NSLayoutConstraint.activate([
            tabsView.topAnchor.constraint(equalTo: statusBar.bottomAnchor),
            tabsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func addSection(_ controller: NSViewController, label: String) {
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        tabs.addTabViewItem(item)
    }

    // MARK: - States

    func showIdle() {
        progress.stopAnimation(nil)
        statusBadge.stringValue = ""
        durationLabel.stringValue = ""
        sizeLabel.stringValue = ""
        bodyViewController.setBody(nil, contentType: nil)
        headersViewController.setPairs([])
        cookiesViewController.setCookies([])
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

        bodyViewController.setBody(result.body, contentType: contentType)
        headersViewController.setPairs(result.headers.map { (key: $0.name, value: $0.value) })
        cookiesViewController.setCookies(ResponseFormatter.parseCookies(from: result.headers))
        timelineViewController.setTiming(result.timing)
    }

    func showError(_ message: String) {
        progress.stopAnimation(nil)
        statusBadge.stringValue = "Failed"
        statusBadge.textColor = .systemRed
        durationLabel.stringValue = ""
        sizeLabel.stringValue = ""

        bodyViewController.setBody(Data(message.utf8), contentType: "text/plain")
        headersViewController.setPairs([])
        cookiesViewController.setCookies([])
        timelineViewController.setTiming(nil)
    }

    /// Restores a stored run, which has headers as JSON rather than live values.
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

        bodyViewController.setBody(body, contentType: contentType)
        headersViewController.setPairs(headers.map { (key: $0.name, value: $0.value) })
        cookiesViewController.setCookies(ResponseFormatter.parseCookies(from: headers))
        timelineViewController.setTiming(TimingBreakdown.decode(from: timingJSON))
    }
}

/// Timeline tab: the chart plus its own scroll container.
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
