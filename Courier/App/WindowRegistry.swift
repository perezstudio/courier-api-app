import AppKit

/// Tracks open windows and drives the native tab group.
///
/// One request per window; macOS stacks them into tabs (REQUIREMENTS.md §7.2).
/// Navigation follows Finder and Safari: selecting a request navigates the
/// *current* tab, and Cmd+click or Cmd+T opens a new one.
@MainActor
final class WindowRegistry {

    static let tabbingIdentifier = NSWindow.TabbingIdentifier("com.perezstudio.Courier.request")

    private let libraryController: LibraryController
    private(set) var controllers: [MainWindowController] = []

    init(libraryController: LibraryController) {
        self.libraryController = libraryController
    }

    /// The frontmost Courier window, if any.
    var activeController: MainWindowController? {
        if let key = NSApp.keyWindow ?? NSApp.mainWindow,
           let match = controllers.first(where: { $0.window === key }) {
            return match
        }
        return controllers.last
    }

    // MARK: - Opening

    /// Opens the first window at launch.
    @discardableResult
    func openInitialWindow() -> MainWindowController {
        let controller = makeController()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return controller
    }

    /// Opens a request in a new tab alongside the current window.
    @discardableResult
    func openInNewTab(requestID: UUID?) -> MainWindowController {
        let controller = makeController()
        controller.show(requestID: requestID)

        if let host = activeController?.window, let newWindow = controller.window, host !== newWindow {
            // addTabbedWindow is what actually joins the group; matching
            // tabbingIdentifier alone only makes them *eligible* to group.
            host.addTabbedWindow(newWindow, ordered: .above)
        }

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return controller
    }

    /// Navigates the current tab, opening a window if none exists.
    func navigateCurrentTab(to requestID: UUID) {
        if let controller = activeController {
            controller.show(requestID: requestID)
        } else {
            let controller = makeController()
            controller.show(requestID: requestID)
            controller.showWindow(nil)
        }
    }

    // MARK: - Lifecycle

    private func makeController() -> MainWindowController {
        let controller = MainWindowController(
            libraryController: libraryController,
            registry: self
        )
        controllers.append(controller)
        return controller
    }

    func controllerWillClose(_ controller: MainWindowController) {
        controllers.removeAll { $0 === controller }
    }

    /// Pushes a change through every open window. Used for state that must look
    /// identical across tabs.
    func forEachController(_ body: (MainWindowController) -> Void) {
        for controller in controllers {
            body(controller)
        }
    }
}
