import AppKit

/// Builds the app's main menu.
///
/// An `LSUIElement` app has no menu bar of its own, which is why ⌘W and Esc
/// used to be hand-wired through an `NSEvent` monitor. That monitor was a
/// symptom: the moment the settings window is up, ⌘Q and — as soon as any
/// text field exists — ⌘X/⌘C/⌘V are all dispatched through menu items too, and
/// none of them existed. Installing a real menu is both smaller and complete.
///
/// The menu is only ever visible while the settings window is open and the app
/// is temporarily `.regular`; the rest of the time nothing renders it.
@MainActor
enum AppMenu {
    static func install(appName: String = "Claudette") {
        let main = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = appSubmenu(appName: appName)
        main.addItem(appItem)

        let editItem = NSMenuItem()
        editItem.submenu = editSubmenu()
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    private static func appSubmenu(appName: String) -> NSMenu {
        let menu = NSMenu(title: appName)
        menu.addItem(
            withTitle: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        return menu
    }

    /// Present so the standard clipboard shortcuts work in any text field the
    /// settings window grows. Without an Edit menu they are simply dead keys.
    private static func editSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }
}
