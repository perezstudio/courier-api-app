import AppKit

/// The "Results" mode of the inspector: body, response headers, and cookies.
///
/// These were three toolbar tabs before. The toolbar now carries the coarse
/// Results / Timeline / History choice, so headers and cookies live one level
/// in — reachable in a click, without widening the toolbar control.
@MainActor
final class ResultsViewController: NSViewController {

    private enum Section: Int {
        case body
        case headers
        case cookies
    }

    private let picker = NSSegmentedControl(
        labels: ["Body", "Headers", "Cookies"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let container = NSView()

    private let bodyViewController = ResponseBodyViewController()
    private let headersViewController = PairTableViewController(
        firstColumn: "Header",
        secondColumn: "Value",
        emptyTitle: "No Headers"
    )
    private let cookiesViewController = CookiesViewController()

    private var section: Section = .body

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        picker.selectedSegment = 0
        picker.controlSize = .small
        picker.target = self
        picker.action = #selector(sectionChanged)
        picker.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(picker)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.topAnchor, constant: Theme.Metrics.tightPadding),
            picker.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Theme.Metrics.standardPadding
            ),

            container.topAnchor.constraint(
                equalTo: picker.bottomAnchor,
                constant: Theme.Metrics.tightPadding
            ),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        for child in [bodyViewController, headersViewController, cookiesViewController] {
            addChild(child)
        }
        showSection(.body)
    }

    // MARK: - Content

    func setBody(_ body: Data?, contentType: String?) {
        bodyViewController.setBody(body, contentType: contentType)
    }

    func setHeaders(_ headers: [(name: String, value: String)]) {
        headersViewController.setPairs(headers.map { (key: $0.name, value: $0.value) })
        cookiesViewController.setCookies(ResponseFormatter.parseCookies(from: headers))
    }

    private func showSection(_ section: Section) {
        self.section = section

        for subview in container.subviews {
            subview.removeFromSuperview()
        }

        let child: NSView
        switch section {
        case .body: child = bodyViewController.view
        case .headers: child = headersViewController.view
        case .cookies: child = cookiesViewController.view
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

    @objc private func sectionChanged() {
        guard let next = Section(rawValue: picker.selectedSegment) else { return }
        showSection(next)
    }
}
