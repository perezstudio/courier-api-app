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
///
/// It also draws the hairline between the toolbar and the content. That should
/// be the window's job — but `titlebarSeparatorStyle = .line` is set on the
/// window *and* on all three split items, and confirmed at runtime to still
/// read `.line`, and AppKit declines to draw anything. Since each column is
/// already held to the safe area, a hairline at the column's top edge lands
/// exactly where the titlebar separator belongs.
@MainActor
final class SafeAreaContainerViewController: NSViewController {

    private let child: NSViewController
    private let separator = NSBox()

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

        // An NSBox separator rather than a coloured one-point view: it renders
        // a true hairline at the display's scale, where a one-point view is two
        // pixels on Retina and reads heavier than the system's own dividers.
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            childView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            childView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
