import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Placeholder window for Phase 0. Phase 2 replaces this with
    /// `MainWindowController` — unified toolbar, source-list sidebar,
    /// and native window tabs. See REQUIREMENTS.md §7.
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // URLSession writes to a closed socket when a request is cancelled
        // mid-flight; without this the process takes SIGPIPE and dies.
        signal(SIGPIPE, SIG_IGN)

        NSApp.mainMenu = MainMenu.build()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Courier"
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "com.perezstudio.Courier.request"
        window.setFrameAutosaveName("MainWindow")
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
