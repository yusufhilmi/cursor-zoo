import AppKit

/// A click-through, always-on-top sheet of glass over one display.
final class OverlayWindow: NSWindow {
    let characterView = CharacterView()
    private(set) var screenFrame: CGRect

    init(screen: NSScreen) {
        screenFrame = screen.frame
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        displaysWhenScreenProfileChanges = true
        // Above the screen saver so it survives full-screen apps and Mission Control.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        characterView.frame = CGRect(origin: .zero, size: screen.frame.size)
        characterView.autoresizingMask = [.width, .height]
        contentView = characterView
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns one overlay per display and routes each frame to whichever one the pointer is over.
final class OverlayController {
    private var windows: [OverlayWindow] = []

    private(set) var character: Character = .tinyMouse
    private(set) var size: CharacterSize = .medium
    /// True when the sprite stands in for the real pointer rather than escorting it.
    private(set) var replaceMode = true

    var isPaused = false {
        didSet {
            windows.forEach { $0.characterView.isHidden = isPaused }
            // Paused means we are not drawing, so the real pointer must come back.
            if isPaused { CursorHider.shared.suspend("paused") }
            else { CursorHider.shared.resume("paused") }
        }
    }

    init() { rebuild() }

    func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen)
            window.characterView.configure(character: character, size: size, replaceMode: replaceMode)
            window.characterView.isHidden = isPaused
            return window
        }
    }

    func select(character: Character) {
        self.character = character
        reconfigure()
    }

    func select(size: CharacterSize) {
        self.size = size
        reconfigure()
    }

    func setReplaceMode(_ enabled: Bool) {
        replaceMode = enabled
        reconfigure()
        CursorHider.shared.setReplaceMode(enabled)
    }

    private func reconfigure() {
        windows.forEach {
            $0.characterView.configure(character: character, size: size, replaceMode: replaceMode)
        }
    }

    func update(_ state: PointerState) {
        guard !isPaused else { return }
        // `contains` on the frame would double-claim the shared edge between displays,
        // so the first match wins and every other overlay hides itself.
        var claimed = false
        for window in windows {
            let hit = !claimed && window.screenFrame.contains(state.location)
            if hit { claimed = true }
            window.characterView.update(state, origin: window.screenFrame.origin, onThisScreen: hit)
        }
    }
}
