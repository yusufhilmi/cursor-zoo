import AppKit
import QuartzCore

/// Hosts one character rig, its screen-space effects, and (optionally) bubbles.
///
/// Layer order, bottom to top: tyre marks, ground effects (prints, smoke), the rig,
/// air effects (impacts, fire, shuriken), bubbles.
final class CharacterView: NSView {
    private let fx = Effects()
    private var rig: CharacterRig

    private struct Bubble {
        let layer = CALayer()
        var shownAt: CFTimeInterval = 0
        var until: CFTimeInterval = 0
        var anchor = CGPoint.zero
        var visible: Bool { until > 0 }
    }
    private var current = Bubble()
    private var echo = Bubble()

    private var character: Character = .tinyMouse
    private var size: CharacterSize = .medium
    private var replaceMode = true
    private var showBubbles = false
    /// Lets the self-test render bigger than any menu size.
    var sizeOverride: CGFloat?
    private var points: CGFloat { sizeOverride ?? size.points }

    private var velocity = CGVector.zero
    private var lastActiveAt: CFTimeInterval = 0

    private let bubbleDuration: CFTimeInterval = 0.8
    /// In companion mode the real arrow is still drawn, so sit just past its tail.
    private static let companionOffset = CGSize(width: 16, height: -20)

    override init(frame frameRect: NSRect) {
        rig = Character.tinyMouse.makeRig()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(fx.ground.layer)
        layer?.addSublayer(fx.under.layer)
        layer?.addSublayer(rig.root)
        layer?.addSublayer(fx.over.layer)
        for bubble in [echo, current] {
            bubble.layer.contentsGravity = .resizeAspect
            bubble.layer.isHidden = true
            layer?.addSublayer(bubble.layer)
        }
        rig.root.isHidden = true
        layoutLanes()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLanes()
    }

    private func layoutLanes() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fx.ground.layer.frame = bounds
        fx.under.layer.frame = bounds
        fx.over.layer.frame = bounds
        CATransaction.commit()
    }

    func configure(character: Character, size: CharacterSize, replaceMode: Bool, bubbles: Bool) {
        if character.id != self.character.id {
            let wasHidden = rig.root.isHidden
            rig.root.removeFromSuperlayer()
            rig = character.makeRig()
            rig.root.isHidden = wasHidden
            layer?.insertSublayer(rig.root, above: fx.under.layer)
        }
        self.character = character
        self.size = size
        self.replaceMode = replaceMode
        self.showBubbles = bubbles
    }

    /// `origin` is this view's screen frame origin in global coordinates. Views for
    /// displays the pointer is not on still tick, so their trails keep fading.
    func update(_ state: PointerState, origin: CGPoint, onThisScreen: Bool) {
        let now = state.time
        let dt = CGFloat(state.dt)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if onThisScreen {
            var position = CGPoint(x: state.location.x - origin.x, y: state.location.y - origin.y)
            if !replaceMode {
                position.x += Self.companionOffset.width
                position.y += Self.companionOffset.height
            }

            // Raw pointer deltas are jittery at 120Hz; everything downstream wants
            // a calm velocity.
            let k = min(1, dt * 18)
            velocity.dx += (state.velocity.dx - velocity.dx) * k
            velocity.dy += (state.velocity.dy - velocity.dy) * k
            let speed = hypot(velocity.dx, velocity.dy)
            if speed > 30 || state.reaction != nil { lastActiveAt = now }

            let motion = Motion(position: position, velocity: velocity, speed: speed,
                                dt: dt, now: now, idle: now - lastActiveAt,
                                scroll: state.scrollDelta)

            rig.root.isHidden = false
            rig.root.position = position
            if let reaction = state.reaction {
                rig.react(to: reaction, motion: motion, fx: fx)
                if showBubbles, let text = character.bubble(for: reaction) {
                    show(bubble: text, style: reaction == .doubleClick ? .loud : .soft,
                         at: now, base: position)
                }
            }
            rig.update(motion, size: points, fx: fx)
        } else if !rig.root.isHidden {
            rig.root.isHidden = true
        }

        fx.tick(now: now, dt: dt)
        layout(&current, now: now)
        layout(&echo, now: now)
    }

    // MARK: - Bubbles

    private func show(bubble text: String, style: Sprite.BubbleStyle,
                      at now: CFTimeInterval, base: CGPoint) {
        guard let image = Sprite.bubble(text, points: max(11, points * 0.4), style: style) else { return }
        // Whatever is showing becomes the echo and keeps fading where it is.
        if current.visible && now < current.until { swap(&current, &echo) }
        current.shownAt = now
        current.until = now + bubbleDuration
        current.layer.contents = image
        current.layer.bounds = CGRect(origin: .zero, size: CGSize(width: CGFloat(image.width) / 3,
                                                                  height: CGFloat(image.height) / 3))
        current.anchor = CGPoint(x: base.x + points * 0.3, y: base.y + points * 0.7)
        current.layer.zPosition = 2
        echo.layer.zPosition = 1
    }

    private func layout(_ bubble: inout Bubble, now: CFTimeInterval) {
        guard bubble.visible, now < bubble.until else {
            bubble.layer.isHidden = true
            bubble.until = 0
            return
        }
        let age = now - bubble.shownAt
        let remaining = bubble.until - now
        let pop = min(1, age / 0.12)
        let scale = 0.6 + 0.4 * (1 - pow(1 - pop, 3)) + sin(pop * .pi) * 0.08
        bubble.layer.isHidden = false
        bubble.layer.opacity = Float(min(1, remaining / 0.25))
        bubble.layer.position = CGPoint(x: bubble.anchor.x, y: bubble.anchor.y + CGFloat(age) * 14)
        bubble.layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }
}
