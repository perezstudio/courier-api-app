import AppKit
import SwiftData
import SwiftUI

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let modelContainer: ModelContainer
    private var splitViewController: MainSplitViewController?

    private static let defaultSize = NSSize(width: 1200, height: 800)

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("CourierMainWindow")
        window.center()

        super.init(window: window)
        window.delegate = self

        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        let splitVC = MainSplitViewController(modelContainer: modelContainer)
        self.splitViewController = splitVC

        guard let contentView = window?.contentView else { return }

        // Single window-wide sidebar-material backdrop. Both split panes sit on top of
        // this transparently, so the split divider seam reveals the same material instead
        // of two independently-blurred NSVisualEffectViews meeting at a line.
        let backdrop = NSVisualEffectView(frame: contentView.bounds)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.material = .sidebar
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        contentView.addSubview(backdrop)

        splitVC.view.frame = contentView.bounds
        splitVC.view.autoresizingMask = [.width, .height]
        contentView.addSubview(splitVC.view)
    }

    // MARK: - NSWindowDelegate

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let screen = sender.screen ?? NSScreen.main else { return frameSize }
        let visibleFrame = screen.visibleFrame
        var size = frameSize
        size.height = min(size.height, visibleFrame.height)
        size.width = min(size.width, visibleFrame.width)
        return size
    }
}
