import AppKit
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    /// ⌥C unless another was picked in the onboarding
    static let openClaude = Self("openClaude", default: .init(.c, modifiers: [.option]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PanelController?
    private let onboarding = OnboardingController()

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
        let panel = PanelController()
        self.panel = panel
        // on key down, as claude's own quick entry: it opens while the key is still going down
        KeyboardShortcuts.onKeyDown(for: .openClaude) { [weak panel, weak self] in
            MainActor.assumeIsolated {
                // while the setup is open the shortcut answers there (its caps, then the window)
                if let onboarding = self?.onboarding, onboarding.isVisible { onboarding.hotkey() } else { panel?.hotkey() }
            }
        }

        panel.onSetup = { [weak self] in self?.onboarding.show() }
        onboarding.onFinish = { [weak panel] in panel?.show() }

        // the first launch: start at login from now on, and walk through the setup once
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didFirstLaunch") {
            defaults.set(true, forKey: "didFirstLaunch")
            try? SMAppService.mainApp.register()
        }
        if !OnboardingController.isDone { onboarding.show() }
    }

    // opening the app again while it runs (finder, spotlight) shows the window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.show()
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
