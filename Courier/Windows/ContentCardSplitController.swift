import AppKit
import SwiftUI

/// NSSplitViewController replacing ContentCardView.
/// Left pane: SwiftUI request editor via NSHostingController.
/// Right pane: Pure AppKit InspectorViewController.
final class ContentCardSplitController: NSSplitViewController {
    private let requestEditorVM: RequestEditorViewModel
    private let inspectorVM: InspectorViewModel
    private var onSend: (() -> Void)?

    private var editorItem: NSSplitViewItem!
    private var inspectorItem: NSSplitViewItem!
    private let inspectorVC: InspectorViewController
    private var isSyncingCollapse = false

    init(
        requestEditorVM: RequestEditorViewModel,
        inspectorVM: InspectorViewModel,
        onSend: (() -> Void)?
    ) {
        self.requestEditorVM = requestEditorVM
        self.inspectorVM = inspectorVM
        self.onSend = onSend
        self.inspectorVC = InspectorViewController(viewModel: inspectorVM)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.dividerStyle = .thin
        splitView.isVertical = true

        view.wantsLayer = true
        view.layer?.cornerRadius = ContentCardMetrics.cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        setupPanes()
    }

    private func setupPanes() {
        // Left: SwiftUI request editor — observes inspectorVM.isCollapsed directly
        let editorView = RequestEditorView(
            requestEditorVM: requestEditorVM,
            inspectorVM: inspectorVM,
            onSend: onSend,
            onToggleInspector: { [weak self] in
                self?.toggleInspector()
            }
        )
        let editorHC = NSHostingController(rootView: editorView)
        if #available(macOS 13.0, *) {
            editorHC.sizingOptions = []
        }

        editorItem = NSSplitViewItem(viewController: editorHC)
        editorItem.minimumThickness = 350
        editorItem.holdingPriority = .defaultLow
        addSplitViewItem(editorItem)

        // Right: AppKit inspector
        inspectorItem = NSSplitViewItem(viewController: inspectorVC)
        inspectorItem.canCollapse = true
        inspectorItem.minimumThickness = 250
        inspectorItem.holdingPriority = .defaultLow + 1
        addSplitViewItem(inspectorItem)

        // Apply initial collapse state
        inspectorItem.isCollapsed = inspectorVM.isCollapsed
    }

    private func toggleInspector() {
        isSyncingCollapse = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            inspectorItem.animator().isCollapsed.toggle()
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.inspectorVM.isCollapsed = self.inspectorItem.isCollapsed
            self.isSyncingCollapse = false
        }
    }

    // Sync collapse state when user drags divider to collapse
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard !isSyncingCollapse else { return }
        if inspectorItem.isCollapsed != inspectorVM.isCollapsed {
            inspectorVM.isCollapsed = inspectorItem.isCollapsed
        }
    }
}

// MARK: - SwiftUI Representable

/// Wraps ContentCardSplitController for use in SwiftUI.
struct ContentCardControllerView: NSViewControllerRepresentable {
    @Bindable var requestEditorVM: RequestEditorViewModel
    @Bindable var inspectorVM: InspectorViewModel
    var onSend: (() -> Void)?

    func makeNSViewController(context: Context) -> ContentCardSplitController {
        ContentCardSplitController(
            requestEditorVM: requestEditorVM,
            inspectorVM: inspectorVM,
            onSend: onSend
        )
    }

    func updateNSViewController(_ nsViewController: ContentCardSplitController, context: Context) {
        // View models are reference types — observation handles updates internally
    }
}
