import AppKit

/// Request editor (left) | response (right). Both are ordinary split items —
/// neither is a sidebar — and the response pane collapses to give the editor
/// the full width.
@MainActor
final class EditorResponseSplitViewController: NSSplitViewController {

    private let editorViewController = RequestSectionsTabViewController()
    private let responseViewController = ResponseSectionsTabViewController()

    private var responseItem: NSSplitViewItem!

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let editorItem = NSSplitViewItem(viewController: editorViewController)
        editorItem.minimumThickness = Theme.Metrics.editorMinWidth
        editorItem.holdingPriority = .defaultLow
        addSplitViewItem(editorItem)

        responseItem = NSSplitViewItem(viewController: responseViewController)
        responseItem.minimumThickness = Theme.Metrics.responseMinWidth
        responseItem.canCollapse = true
        responseItem.holdingPriority = .defaultLow - 1
        addSplitViewItem(responseItem)

        splitView.autosaveName = "CourierEditorResponseSplit"
    }

    func toggleResponsePane() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            responseItem.animator().isCollapsed.toggle()
        }
    }
}
