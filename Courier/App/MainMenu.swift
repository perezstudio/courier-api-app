import AppKit

/// Builds the application menu bar.
///
/// Items use a nil target so they dispatch through the responder chain and land
/// on the frontmost `MainWindowController`, which validates them. Tab commands
/// (Show Tab Bar, Move Tab to New Window, Show Next Tab…) are added by AppKit
/// itself once `NSApp.windowsMenu` is set — they are not built here.
enum MainMenu {

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenuItem())

        let windowItem = windowMenuItem()
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowItem.submenu

        return mainMenu
    }

    // MARK: - Application

    private static func applicationMenuItem() -> NSMenuItem {
        let menu = NSMenu()

        menu.addItem(
            withTitle: "About Courier",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Settings…", action: nil, keyEquivalent: ",")
        settings.isEnabled = false  // Phase 7.

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Hide Courier",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Courier",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - File

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")

        menu.addItem(
            withTitle: "New Request",
            action: #selector(MainWindowController.newRequest(_:)),
            keyEquivalent: "n"
        )

        let newFolder = menu.addItem(
            withTitle: "New Folder",
            action: #selector(MainWindowController.newFolder(_:)),
            keyEquivalent: "n"
        )
        newFolder.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(
            withTitle: "New Tab",
            action: #selector(MainWindowController.newTab(_:)),
            keyEquivalent: "t"
        )

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Environments…",
            action: #selector(MainWindowController.showEnvironments(_:)),
            keyEquivalent: "e"
        )

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Close Tab",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Edit

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - View

    private static func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")

        let sidebar = menu.addItem(
            withTitle: "Toggle Sidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s"
        )
        sidebar.keyEquivalentModifierMask = [.command, .control]

        let response = menu.addItem(
            withTitle: "Toggle Response Pane",
            action: #selector(MainWindowController.toggleResponsePaneAction(_:)),
            keyEquivalent: "i"
        )
        response.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(.separator())
        let fullScreen = menu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Window

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")

        menu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
