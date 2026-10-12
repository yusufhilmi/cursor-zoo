import AppKit
import QuartzCore

/// Draws one character and runs its reactions. The personality lives here.
///
/// In replace mode the sprite *is* the cursor, so its hotspot sits exactly on the
/// pointer and no animation is ever allowed to move it off: see `TinyMouseNode`,
/// whose anchor point is the mouse's nose.
final class CharacterView: NSView {
    private let sprite = CALayer()       // emoji characters
    private let bubble = CALayer()
    private let mouse = TinyMouseNode()  // the real, fully articulated Tiny Mouse

    private var character: Character = .tinyMouse
    private var size: CharacterSize = .medium
    private var replaceMode = true
    private var glyphKey = ""
    private var bubbleKey = ""

    // Animation state.
    private var leftPawAt: CFTimeInterval = -1
    private var rightPawAt: CFTimeInterval = -1
    private var squishAt: CFTimeInterval = -1
    private var recoilAt: CFTimeInterval = -1
    private var hopAt: CFTimeInterval = -1
    private var spin: CGFloat = 0
    private var spinVelocity: CGFloat = 0
    private var leanAngle: CGFloat = 0
    private var bubbleUntil: CFTimeInterval = 0
    private var facing: CGFloat = 1

    private let pawDuration: CFTimeInterval = 0.2
    private let squishDuration: CFTimeInterval = 0.22
    private let recoilDuration: CFTimeInterval = 0.26
    private let hopDuration: CFTimeInterval = 0.45
    private let bubbleDuration: CFTimeInterval = 0.75

    private var usesVectorMouse: Bool { character.id == Character.tinyMouse.id }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(bubble)
        layer?.addSublayer(sprite)
        layer?.addSublayer(mouse.root)
        for l in [sprite, bubble] {
            l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            l.contentsGravity = .resizeAspect
            l.isHidden = true
        }
        mouse.root.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    func configure(character: Character, size: CharacterSize, replaceMode: Bool) {
        self.character = character
        self.size = size
        self.replaceMode = replaceMode
    }

    /// `origin` is this view's screen frame origin in global coordinates.
    func update(_ state: PointerState, origin: CGPoint, onThisScreen: Bool) {
        guard onThisScreen else {
            if !mouse.root.isHidden || !sprite.isHidden { setHidden(true) }
            return
        }

        let now = CACurrentMediaTime()
        apply(reaction: state.reaction, state: state, now: now)
        advance(state: state, now: now)

        let points = size.points

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // In replace mode the hotspot is the pointer itself, so no offset at all.
        let shift = replaceMode ? CGSize.zero : character.offset
        let base = CGPoint(x: state.location.x - origin.x + shift.width,
                           y: state.location.y - origin.y + shift.height)

        if usesVectorMouse {
            sprite.isHidden = true
            mouse.root.isHidden = false
            mouse.root.position = base
            mouse.apply(pose(now: now), size: points)
        } else {
            mouse.root.isHidden = true
            refreshGlyphIfNeeded(points: points)
            if sprite.isHidden { sprite.isHidden = false }
            layoutSprite(at: base, points: points, now: now)
        }
        layoutBubble(at: base, points: points, now: now)
    }

    // MARK: - Reactions

    private func apply(reaction: Reaction?, state: PointerState, now: CFTimeInterval) {
        guard let reaction else { return }

        if usesVectorMouse {
            // The mouse has real limbs, so map clicks straight onto them.
            switch reaction {
            case .leftClick:
                leftPawAt = now
                squishAt = now
            case .rightClick:
                rightPawAt = now
                squishAt = now
            case .doubleClick:
                hopAt = now
                leftPawAt = now
                rightPawAt = now
            case .scroll:
                spinVelocity += state.scrollDelta * 0.9
            }
        } else {
            switch character.move(for: reaction) {
            case .squish: squishAt = now
            case .recoil: recoilAt = now
            case .hop:    hopAt = now
            case .spin:   spinVelocity += state.scrollDelta * 0.9
            case .none:   break
            }
        }

        if let text = character.bubble(for: reaction) {
            if bubbleKey != text, let image = Sprite.bubble(text, points: max(11, size.points * 0.38)) {
                bubbleKey = text
                bubble.contents = image
                bubble.bounds = CGRect(origin: .zero,
                                       size: CGSize(width: CGFloat(image.width) / 3,
                                                    height: CGFloat(image.height) / 3))
            }
            bubbleUntil = now + bubbleDuration
        }
    }

    private func advance(state: PointerState, now: CFTimeInterval) {
        // Spin decays towards rest so scroll feels like real momentum.
        spin += spinVelocity * CGFloat(state.dt)
        spinVelocity *= CGFloat(pow(0.02, state.dt))
        if abs(spinVelocity) < 0.01 { spinVelocity = 0 }

        // Lean into travel, smoothed so it does not jitter.
        let target = max(-0.45, min(0.45, -state.velocity.dx / 3500)) * character.lean
        leanAngle += (target - leanAngle) * min(1, CGFloat(state.dt) * 12)

        if abs(state.velocity.dx) > 60 { facing = state.velocity.dx < 0 ? -1 : 1 }
    }

    private func pose(now: CFTimeInterval) -> MousePose {
        var pose = MousePose()
        if let t = progress(since: leftPawAt, over: pawDuration, now: now) {
            pose.leftPaw = sin(.pi * t)
        }
        if let t = progress(since: rightPawAt, over: pawDuration, now: now) {
            pose.rightPaw = sin(.pi * t)
        }
        if let t = progress(since: squishAt, over: squishDuration, now: now) {
            pose.squash = sin(.pi * t)
        }
        if let t = progress(since: hopAt, over: hopDuration, now: now) {
            pose.hop = t
        }
        // Tail idles with a slow wag and whips when the wheel is spun.
        pose.tailPhase = CGFloat(now * 2.2) + spin * 0.6
        pose.lean = leanAngle * 0.5
        return pose
    }

    // MARK: - Layout

    private func layoutSprite(at base: CGPoint, points: CGFloat, now: CFTimeInterval) {
        var position = base
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var angle = character.restAngle + leanAngle + spin

        if let t = progress(since: squishAt, over: squishDuration, now: now) {
            let amount = (1 - t) * (1 - t)
            scaleX = 1 + 0.38 * amount
            scaleY = 1 - 0.32 * amount
            position.y -= points * 0.14 * amount
        }
        if let t = progress(since: recoilAt, over: recoilDuration, now: now) {
            let amount = sin(.pi * t)
            position.x -= facing * points * 0.42 * amount
            angle -= facing * 0.55 * amount
        }
        if let t = progress(since: hopAt, over: hopDuration, now: now) {
            position.y += sin(.pi * t) * points * 0.95
            angle += sin(.pi * 2 * t) * 0.35
        } else {
            position.y += sin(now * 2.6) * points * 0.035
        }

        sprite.bounds = CGRect(x: 0, y: 0, width: points, height: points)
        sprite.position = position
        var transform = CGAffineTransform(rotationAngle: angle)
        transform = transform.scaledBy(x: scaleX * facing, y: scaleY)
        sprite.setAffineTransform(transform)
    }

    private func layoutBubble(at base: CGPoint, points: CGFloat, now: CFTimeInterval) {
        guard now < bubbleUntil, bubble.bounds.width > 0 else {
            bubble.isHidden = true
            return
        }
        let remaining = bubbleUntil - now
        let t = 1 - (remaining / bubbleDuration)
        bubble.isHidden = false
        bubble.opacity = Float(min(1, remaining / 0.25))
        // Anchor the bubble's left edge beside the sprite rather than its centre,
        // otherwise a long word grows back over the character.
        bubble.position = CGPoint(x: base.x + points * 0.45 + bubble.bounds.width / 2,
                                  y: base.y + points * 0.3 + CGFloat(t) * 10)
    }

    // MARK: - Helpers

    private func refreshGlyphIfNeeded(points: CGFloat) {
        let key = "\(character.glyph):\(points)"
        guard key != glyphKey, let image = Sprite.glyph(character.glyph, points: points) else { return }
        glyphKey = key
        sprite.contents = image
        sprite.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Normalised 0...1 progress, or nil when the animation is finished.
    private func progress(since start: CFTimeInterval,
                          over duration: CFTimeInterval,
                          now: CFTimeInterval) -> CGFloat? {
        guard start > 0 else { return nil }
        let elapsed = now - start
        guard elapsed >= 0, elapsed < duration else { return nil }
        return CGFloat(elapsed / duration)
    }

    private func setHidden(_ hidden: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.isHidden = hidden
        bubble.isHidden = hidden
        mouse.root.isHidden = hidden
        CATransaction.commit()
    }
}
