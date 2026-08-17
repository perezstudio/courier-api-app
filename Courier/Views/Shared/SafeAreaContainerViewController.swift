import AppKit

/// Hosts a child controller inset to the safe area.
///
/// `NSTabViewController` lays its tab view out to `view.bounds` and ignores
/// `safeAreaInsets`, so under a unified toolbar its section picker slides
/// beneath the toolbar. Overriding `viewDidLayout` to set the frame there
/// *seems* like the fix and is not: assigning a frame during layout marks the
/// window as needing layout again, and AppKit aborts the process with
/// "more Layout Window passes than there are views in the window".
///
/// Constraints against the safe-area guide do the same job declaratively, with
/// nothing mutated mid-pass.
@MainActor
final class SafeAreaContainerViewController: NSViewController {

    private let child: NSViewController

    init(child: NSViewController) {
        self.child = child
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

        addChild(child)
        let childView = child.view
        childView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(childView)

        NSLayoutConstraint.activate([
            childView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            childView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
