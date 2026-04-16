import AppKit
import SwiftUI

/// NSSplitViewController replacing ContentCardView.
/// Left pane: SwiftUI request editor via NSHostingController.
/// Right pane: Pure AppKit InspectorViewController.
final class ContentCardSplitController: NSSplitViewController {
    private var currentEditorVM: RequestEditorViewModel
    private var currentInspectorVM: InspectorViewModel
    private var onSend: (() -> Void)?

    private var editorItem: NSSplitViewItem!
    private var inspectorItem: NSSplitViewItem!
    private var editorHostingController: NSHostingController<RequestEditorView>!
    private let inspectorVC: InspectorViewController
    private var isSyncingCollapse = false

    init(
        requestEditorVM: RequestEditorViewModel,
        inspectorVM: InspectorViewModel,
        onSend: (() -> Void)?
    ) {
        self.currentEditorVM = requestEditorVM
        self.currentInspectorVM = inspectorVM
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

    override func viewDidAppear() {
        super.viewDidAppear()
        // Set initial divider position to 50% of the split view width
        let halfWidth = splitView.bounds.width / 2
        splitView.setPosition(halfWidth, ofDividerAt: 0)
    }

    private func setupPanes() {
        // Left: SwiftUI request editor — observes inspectorVM.isCollapsed directly
        let editorView = RequestEditorView(
            requestEditorVM: currentEditorVM,
            inspectorVM: currentInspectorVM,
            onSend: onSend,
            onToggleInspector: { [weak self] in
                self?.toggleInspector()
            }
        )
        let editorHC = NSHostingController(rootView: editorView)
        if #available(macOS 13.0, *) {
            editorHC.sizingOptions = []
        }
        editorHostingController = editorHC

        editorItem = NSSplitViewItem(viewController: editorHC)
        editorItem.minimumThickness = 350
        addSplitViewItem(editorItem)

        // Right: AppKit inspector
        inspectorVC.onToggleInspector = { [weak self] in
            self?.toggleInspector()
        }
        inspectorItem = NSSplitViewItem(viewController: inspectorVC)
        inspectorItem.canCollapse = true
        inspectorItem.minimumThickness = 250
        addSplitViewItem(inspectorItem)

        // Apply initial collapse state
        inspectorItem.isCollapsed = currentInspectorVM.isCollapsed
    }

    func switchToTab(editorVM: RequestEditorViewModel, inspectorVM: InspectorViewModel) {
        guard editorVM !== currentEditorVM || inspectorVM !== currentInspectorVM else { return }
        currentEditorVM = editorVM
        currentInspectorVM = inspectorVM

        // Update SwiftUI editor with new VMs
        editorHostingController.rootView = RequestEditorView(
            requestEditorVM: editorVM,
            inspectorVM: inspectorVM,
            onSend: onSend,
            onToggleInspector: { [weak self] in
                self?.toggleInspector()
            }
        )

        // Update AppKit inspector
        inspectorVC.setViewModel(inspectorVM)

        // Sync collapse state from new VM
        isSyncingCollapse = true
        inspectorItem.isCollapsed = inspectorVM.isCollapsed
        isSyncingCollapse = false
    }

    private func toggleInspector() {
        isSyncingCollapse = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            inspectorItem.animator().isCollapsed.toggle()
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.currentInspectorVM.isCollapsed = self.inspectorItem.isCollapsed
            self.isSyncingCollapse = false
        }
    }

    // Sync collapse state when user drags divider to collapse
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard !isSyncingCollapse else { return }
        if inspectorItem.isCollapsed != currentInspectorVM.isCollapsed {
            currentInspectorVM.isCollapsed = inspectorItem.isCollapsed
        }
    }
}

// MARK: - SwiftUI Representable

/// Wraps ContentCardSplitController for use in SwiftUI.
/// Observes ActiveTabContext and calls switchToTab when VMs change.
struct ContentCardControllerView: NSViewControllerRepresentable {
    @Bindable var activeTabContext: ActiveTabContext
    var onSend: (() -> Void)?

    func makeNSViewController(context: Context) -> ContentCardSplitController {
        ContentCardSplitController(
            requestEditorVM: activeTabContext.editorVM,
            inspectorVM: activeTabContext.inspectorVM,
            onSend: onSend
        )
    }

    func updateNSViewController(_ nsViewController: ContentCardSplitController, context: Context) {
        nsViewController.switchToTab(
            editorVM: activeTabContext.editorVM,
            inspectorVM: activeTabContext.inspectorVM
        )
    }
}
