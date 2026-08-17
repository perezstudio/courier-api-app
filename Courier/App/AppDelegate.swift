import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    nonisolated private static let logger = Logger(
        subsystem: "com.perezstudio.Courier",
        category: "app"
    )

    private var stack: CoreDataStack?
    private var libraryController: LibraryController?
    private var registry: WindowRegistry?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // URLSession writes to a closed socket when a request is cancelled
        // mid-flight; without this the process takes SIGPIPE and dies.
        signal(SIGPIPE, SIG_IGN)

        NSApp.mainMenu = MainMenu.build()

        do {
            let stack = try CoreDataStack()
            self.stack = stack

            if let report = stack.quarantineReport {
                presentQuarantineNotice(report)
            }

            let controller = LibraryController(
                stack: stack,
                secretStore: KeychainSecretStore()
            )
            controller.load()
            controller.loadExpansionState()
            self.libraryController = controller

            startMaintenance(stack: stack, library: controller)

            let registry = WindowRegistry(libraryController: controller)
            self.registry = registry
            registry.openInitialWindow()

            NSApp.activate(ignoringOtherApps: true)
        } catch {
            presentFatalStoreError(error)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Maintenance

    /// Launch-time housekeeping, off the main thread so it never delays the
    /// first window: prune run history and sweep orphaned Keychain items.
    private func startMaintenance(stack: CoreDataStack, library: LibraryController) {
        Task.detached(priority: .utility) {
            do {
                let pruned = try await stack.performBackgroundTask { context in
                    try HistoryRetention.prune(in: context)
                }
                if pruned > 0 {
                    Self.logger.info("Pruned \(pruned) run(s) at launch")
                }
            } catch {
                Self.logger.error("History pruning failed: \(error.localizedDescription)")
            }

            await MainActor.run {
                let swept = (try? library.environments.sweepOrphanedSecrets()) ?? 0
                if swept > 0 {
                    Self.logger.info("Swept \(swept) orphaned secret(s)")
                }
            }
        }
    }

    // MARK: - Errors

    /// Tells the user where their library went when a store had to be
    /// quarantined. Never silently discards data — see REQUIREMENTS.md §5.3.
    private func presentQuarantineNotice(_ report: CoreDataStack.QuarantineReport) {
        let alert = NSAlert()
        alert.messageText = "Courier couldn't open your library"
        alert.informativeText = """
            Your previous library has been kept and moved aside, and Courier has \
            started with an empty one. Nothing was deleted.

            \(report.underlyingError)
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([report.quarantinedURL])
        }
    }

    private func presentFatalStoreError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Courier can't start"
        alert.informativeText = """
            The data store could not be opened.

            \(error.localizedDescription)
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
