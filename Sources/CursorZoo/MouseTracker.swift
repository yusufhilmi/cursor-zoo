import AppKit
import QuartzCore

/// One frame's worth of pointer truth.
struct PointerState {
    var location: NSPoint
    var velocity: CGVector
    var leftDown: Bool
    var rightDown: Bool
    var scrollDelta: CGFloat
    /// At most one discrete reaction per frame.
    var reaction: Reaction?
    var dt: CFTimeInterval
    /// Frame timestamp. Everything animates off this rather than reading the clock
    /// itself, so the self-test can drive a whole timeline deterministically.
    var time: CFTimeInterval
}

/// Follows the pointer at the display's refresh rate.
///
/// Buttons are *polled* from `NSEvent.pressedMouseButtons` rather than read from a
/// global event monitor: polling needs no Accessibility grant, and at 60–120Hz it
/// catches every human click. Scroll has no polling equivalent, so it uses a global
/// monitor (mouse-only monitors do not require a TCC prompt either).
final class MouseTracker {
    var onTick: ((PointerState) -> Void)?

    private var displayLink: CADisplayLink?
    private var scrollMonitor: Any?

    private var lastLocation = NSEvent.mouseLocation
    private var lastTime = CACurrentMediaTime()
    private var wasLeft = false
    private var wasRight = false
    private var lastLeftDownAt: CFTimeInterval = -1
    private var pendingScroll: CGFloat = 0

    func start() {
        guard displayLink == nil else { return }
        let link = (NSScreen.main ?? NSScreen.screens[0]).displayLink(
            target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link

        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.pendingScroll += event.scrollingDeltaY
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        scrollMonitor = nil
    }

    /// Rebuild the link against the current main display after a screen change.
    func retarget() {
        guard displayLink != nil else { return }
        displayLink?.invalidate()
        let link = (NSScreen.main ?? NSScreen.screens[0]).displayLink(
            target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(0.1, max(1.0 / 240.0, now - lastTime))
        lastTime = now

        let location = NSEvent.mouseLocation
        let velocity = CGVector(dx: (location.x - lastLocation.x) / dt,
                                dy: (location.y - lastLocation.y) / dt)
        lastLocation = location

        let buttons = NSEvent.pressedMouseButtons
        let left = buttons & (1 << 0) != 0
        let right = buttons & (1 << 1) != 0

        var reaction: Reaction?
        if left && !wasLeft {
            if lastLeftDownAt > 0 && now - lastLeftDownAt <= NSEvent.doubleClickInterval {
                reaction = .doubleClick
                lastLeftDownAt = -1
            } else {
                reaction = .leftClick
                lastLeftDownAt = now
            }
        } else if right && !wasRight {
            reaction = .rightClick
        }
        wasLeft = left
        wasRight = right

        let scroll = pendingScroll
        pendingScroll = 0
        if reaction == nil && abs(scroll) > 0.5 { reaction = .scroll }

        onTick?(PointerState(location: location,
                             velocity: velocity,
                             leftDown: left,
                             rightDown: right,
                             scrollDelta: scroll,
                             reaction: reaction,
                             dt: dt,
                             time: now))
    }

    deinit { stop() }
}
