import AppKit
import CGSPrivate

/// Takes the real pointer away so the mouse sprite can *be* the cursor.
///
/// macOS has no public API for this. `CGDisplayHideCursor` on its own only applies
/// while your app is frontmost; setting the undocumented `SetsCursorInBackground`
/// connection property first is what makes it stick for a menu-bar app.
///
/// Everything else in this file is about never stranding anyone without a pointer:
///
/// - `hide`/`show` are reference counted per window-server connection, so every
///   hide is matched exactly once.
/// - `atexit` plus handlers for every catchable fatal signal restore the cursor on
///   the way out, including on a crash.
/// - The cursor is handed back whenever the app cannot be sure it is still drawing:
///   screen locked, display asleep, machine asleep, screen saver running, paused.
///   **The lock screen is the important one** — our overlay cannot draw there, so
///   without this you would reach a login window with no pointer.
/// - If the process dies so hard that none of the above runs, the hide is released
///   when the window-server connection is torn down. That is the same mechanism
///   that gives you a pointer back when a full-screen game crashes. It is the one
///   link in the chain this app cannot itself guarantee, so `restore-cursor.sh`
///   exists as a manual escape hatch.
/// - A watchdog on a background queue covers the case none of the above can: the
///   main thread *hanging*. A hang fires no signal, but it does stop the overlay
///   drawing, which would leave you with neither pointer. Every frame bumps a
///   heartbeat; if it goes stale for two seconds the watchdog shows the cursor, and
///   the next healthy frame hides it again.
final class CursorHider {
    static let shared = CursorHider()

    /// User intent, from the menu bar.
    private(set) var replaceModeEnabled = false
    /// Conditions where we must give the pointer back regardless of intent.
    private var suspensions = Set<String>()

    // Shared with the watchdog queue, so only touched under `lock`.
    private let lock = NSLock()
    private var isHidden = false
    private var lastBeat: CFTimeInterval = 0
    private var stalled = false
    private var watchdog: DispatchSourceTimer?

    private init() {
        installSafetyNet()
        observeSystemState()
        startWatchdog()
    }

    /// Called once per drawn frame from the display link.
    func heartbeat() {
        lock.lock()
        lastBeat = CACurrentMediaTime()
        let recovering = stalled
        stalled = false
        lock.unlock()
        if recovering { sync() }
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "cursorzoo.watchdog"))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stale = self.lastBeat > 0 && CACurrentMediaTime() - self.lastBeat > 2
            let rescue = stale && self.isHidden && !self.stalled
            if rescue {
                self.stalled = true
                self.isHidden = false
                CGDisplayShowCursor(CGMainDisplayID())
            }
            self.lock.unlock()
        }
        timer.resume()
        watchdog = timer
    }

    // MARK: - Intent

    func setReplaceMode(_ enabled: Bool) {
        replaceModeEnabled = enabled
        sync()
    }

    func suspend(_ reason: String) {
        suspensions.insert(reason)
        sync()
    }

    func resume(_ reason: String) {
        suspensions.remove(reason)
        sync()
    }

    /// Hand the pointer back immediately and permanently, for quit.
    func restoreNow() {
        lock.lock()
        defer { lock.unlock() }
        if isHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            isHidden = false
        }
    }

    private func sync() {
        lock.lock()
        defer { lock.unlock() }
        let shouldHide = replaceModeEnabled && suspensions.isEmpty && !stalled
        guard shouldHide != isHidden else { return }
        if shouldHide {
            let connection = CGSMainConnectionID()
            // Without this the hide is ignored while another app is frontmost.
            _ = CGSSetConnectionProperty(connection, connection,
                                         "SetsCursorInBackground" as CFString,
                                         kCFBooleanTrue)
            CGDisplayHideCursor(CGMainDisplayID())
        } else {
            CGDisplayShowCursor(CGMainDisplayID())
        }
        isHidden = shouldHide
    }

    // MARK: - Safety

    private func installSafetyNet() {
        atexit { CGDisplayShowCursor(CGMainDisplayID()) }
        // Closures with no captures bridge to C function pointers, which is what
        // signal() requires. Only async-signal-safe work here: restore, then leave.
        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT,
                    SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP] {
            signal(sig) { _ in
                CGDisplayShowCursor(CGMainDisplayID())
                _exit(1)
            }
        }
    }

    private func observeSystemState() {
        let distributed = DistributedNotificationCenter.default()
        let locks: [(String, String)] = [
            ("com.apple.screenIsLocked", "lock"),
            ("com.apple.screensaver.didstart", "screensaver")
        ]
        for (name, reason) in locks {
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) {
                [weak self] _ in self?.suspend(reason)
            }
        }
        let unlocks: [(String, String)] = [
            ("com.apple.screenIsUnlocked", "lock"),
            ("com.apple.screensaver.didstop", "screensaver")
        ]
        for (name, reason) in unlocks {
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) {
                [weak self] _ in self?.resume(reason)
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let suspendOn: [(NSNotification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, "displaysleep"),
            (NSWorkspace.sessionDidResignActiveNotification, "fastuserswitch")
        ]
        for (name, reason) in suspendOn {
            workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.suspend(reason)
            }
        }
        let resumeOn: [(NSNotification.Name, String)] = [
            (NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidWakeNotification, "displaysleep"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "fastuserswitch")
        ]
        for (name, reason) in resumeOn {
            workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.resume(reason)
            }
        }
    }
}
