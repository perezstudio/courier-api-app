import SwiftUI

@main
struct CourierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Window is managed by MainWindowController via AppDelegate.
        // We use Settings as a placeholder scene — the main window is AppKit-driven.
        Settings {
            EmptyView()
        }
    }
}
