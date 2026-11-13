import AppKit
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    static let openClaude = Self("openClaude")
}

/// option c: what the keychron key sends. there is no recorder in the app, so this is set at every
/// launch: a stored older shortcut never outlives a change here.
private let openClaudeShortcut = KeyboardShortcuts.Shortcut(.c, modifiers: [.option])

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var palette: PaletteController?

    /// the app was "Abrir Claude" (com.aaangelmartin.abrir-claude) before: its recent folders come along once
    private static func bringOverRecents() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "recentFolders") == nil,
              let old = UserDefaults(suiteName: "com.aaangelmartin.abrir-claude") else { return }
        for key in ["recentFolders", "recentFolderDates", "barTopLeft", "theme"] {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.editMenu()
        Self.bringOverRecents()
        let palette = PaletteController()
        self.palette = palette
        KeyboardShortcuts.setShortcut(openClaudeShortcut, for: .openClaude)
        // on key down, as claude's own quick entry: it opens while the key is still going down
        KeyboardShortcuts.onKeyDown(for: .openClaude) { [weak palette] in
            MainActor.assumeIsolated { palette?.hotkey() }
        }

        // the first launch: start at login from now on, and show the palette once so it is clear it works
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didFirstLaunch") {
            defaults.set(true, forKey: "didFirstLaunch")
            try? SMAppService.mainApp.register()
            palette.show()
        }
    }

    // opening the app again while it runs (finder, spotlight) shows the palette
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        palette?.show()
        return false
    }

    /// the app shows no menu bar, but ⌘A ⌘C ⌘V ⌘X ⌘Z only reach a text field through an edit menu's key
    /// equivalents: this one is never seen, it is there for the keys
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no dock icon, no menu bar
        app.run()
    }
}
