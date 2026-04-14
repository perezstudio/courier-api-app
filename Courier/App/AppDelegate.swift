import AppKit
import SwiftData

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    lazy var modelContainer: ModelContainer = {
        let schema = Schema([
            Workspace.self,
            Folder.self,
            APIRequest.self,
            Header.self,
            QueryParam.self,
            Environment.self,
            EnvironmentVariable.self,
        ])

        let modelConfiguration = ModelConfiguration(
            "Courier",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("SwiftData failed to open store, resetting: \(error)")
            let storeURL = modelConfiguration.url
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: storeURL.path + suffix)
                )
            }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.regular)

        let wc = MainWindowController(modelContainer: modelContainer)
        self.windowController = wc
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
