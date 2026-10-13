import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private let tracker = MouseTracker()
    private var statusItem: NSStatusItem!

    private enum Key {
        static let character = "character"
        static let size = "size"
        static let replaceMode = "replaceMode"
        static let bubbles = "bubbles"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        restorePreferences()

        tracker.onTick = { [weak self] state in
            self?.overlay.update(state)
            CursorHider.shared.heartbeat()
        }
        tracker.start()

        buildStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.stop()
        // Last line of defence on a normal quit; the signal and atexit handlers in
        // CursorHider cover every other way this process can end.
        CursorHider.shared.restoreNow()
    }

    @objc private func screensChanged() {
        overlay.rebuild()
        tracker.retarget()
    }

    // MARK: - Preferences

    private func restorePreferences() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Key.character) {
            overlay.select(character: .named(id))
        }
        if let raw = defaults.string(forKey: Key.size),
           let size = CharacterSize(rawValue: raw) {
            overlay.select(size: size)
        }
        // Replacing the pointer is the whole point, so it is on unless turned off.
        let replace = defaults.object(forKey: Key.replaceMode) as? Bool ?? true
        overlay.setReplaceMode(replace)
        overlay.setBubbles(defaults.bool(forKey: Key.bubbles))
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = overlay.character.glyph
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Cursor Zoo", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for character in Character.all {
            let item = NSMenuItem(title: "\(character.glyph)  \(character.name)",
                                  action: #selector(pickCharacter(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = character.id
            item.state = character.id == overlay.character.id ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let replace = NSMenuItem(title: "Replace system cursor",
                                 action: #selector(toggleReplaceMode),
                                 keyEquivalent: "")
        replace.target = self
        replace.state = overlay.replaceMode ? .on : .off
        menu.addItem(replace)

        let bubbles = NSMenuItem(title: "Speech bubbles",
                                 action: #selector(toggleBubbles),
                                 keyEquivalent: "")
        bubbles.target = self
        bubbles.state = overlay.bubbles ? .on : .off
        menu.addItem(bubbles)

        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for size in CharacterSize.allCases {
            let item = NSMenuItem(title: size.label,
                                  action: #selector(pickSize(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = size == overlay.size ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let pause = NSMenuItem(title: overlay.isPaused ? "Resume" : "Pause",
                               action: #selector(togglePause),
                               keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Cursor Zoo", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func pickCharacter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        overlay.select(character: .named(id))
        UserDefaults.standard.set(id, forKey: Key.character)
        statusItem.button?.title = overlay.character.glyph
        statusItem.menu = buildMenu()
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = CharacterSize(rawValue: raw) else { return }
        overlay.select(size: size)
        UserDefaults.standard.set(raw, forKey: Key.size)
        statusItem.menu = buildMenu()
    }

    @objc private func toggleReplaceMode() {
        let enabled = !overlay.replaceMode
        overlay.setReplaceMode(enabled)
        UserDefaults.standard.set(enabled, forKey: Key.replaceMode)
        statusItem.menu = buildMenu()
    }

    @objc private func toggleBubbles() {
        let enabled = !overlay.bubbles
        overlay.setBubbles(enabled)
        UserDefaults.standard.set(enabled, forKey: Key.bubbles)
        statusItem.menu = buildMenu()
    }

    @objc private func togglePause() {
        overlay.isPaused.toggle()
        statusItem.menu = buildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
