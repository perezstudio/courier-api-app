import AppKit

/// Builds the application menu bar.
///
/// Phase 0 provides only what the app needs to be usable and quittable, plus
/// the standard Edit and Window menus that AppKit expects to exist. Phase 2
/// fills in File, View, and the Courier-specific commands with proper
/// `validateMenuItem(_:)` handling. See REQUIREMENTS.md §8.8 for the full
/// shortcut map.
enum MainMenu {

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(editMenuItem())

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

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
