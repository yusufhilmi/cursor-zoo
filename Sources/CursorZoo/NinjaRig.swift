import AppKit
import QuartzCore

/// Shadow Ninja: an original chibi in all-black with glowing eyes and a purple
/// headband. The point of the hood is the pointer.
///
/// - left click: left jab — the fist lands on the spot you clicked, comic star
/// - right click: right punch, same target
/// - double click: full spin about the hotspot, smoke ring, four shuriken fly out
/// - scroll: a twirl that springs back
/// - move: headband tails stream behind; fast dashes leave after-images
/// - idle: fighter's bounce, blinks
final class NinjaRig: CharacterRig {
    let root = Draw.root(space: CGRect(x: -62, y: -112, width: 124, height: 150))

    private enum Palette {
        static let suit = Ink.rgb(0.12, 0.11, 0.15)
        // A step lighter than the suit, so the face and gloves separate from the body.
        static let mask = Ink.rgb(0.31, 0.29, 0.37)
        static let glowSoft = Ink.rgb(1.0, 0.82, 0.25, 0.28)
        static let band = Ink.rgb(0.55, 0.36, 0.96)
        static let glow = Ink.rgb(1.0, 0.82, 0.25)
        static let star = Ink.rgb(1.0, 0.82, 0.25)
        static let steel = Ink.rgb(0.67, 0.70, 0.75)
    }

    private struct Arm {
        let shoulder: CGPoint
        let rest: CGPoint
        let control: CGPoint
        let target: CGPoint
    }
    // Guard beside the head; the jab goes straight to the hotspot.
    private static let leftArm = Arm(shoulder: CGPoint(x: -13, y: -40), rest: CGPoint(x: -17, y: -29),
                                     control: CGPoint(x: -17, y: -10), target: CGPoint(x: -5, y: 1))
    private static let rightArm = Arm(shoulder: CGPoint(x: 13, y: -40), rest: CGPoint(x: 17, y: -29),
                                      control: CGPoint(x: 17, y: -10), target: CGPoint(x: 5, y: 1))
    private static let bodyCentre = CGPoint(x: 0, y: -50)
    private static let eyeLine = CGPoint(x: 0, y: -14.5)

    private let shadow = Draw.group()
    private let tailsInk = Draw.shape(nil, fill: nil, stroke: Ink.ink, width: 6.6)
    private let tailsBand = Draw.shape(nil, fill: nil, stroke: Palette.band, width: 3.6)
    private let eyes = Draw.group(pivot: eyeLine)
    private let leftLimb: Limb
    private let rightLimb: Limb

    // State.
    private var leftAt: CFTimeInterval = -1
    private var rightAt: CFTimeInterval = -1
    private var spinAt: CFTimeInterval = -1
    private var lean: CGFloat = 0
    private var twirl: CGFloat = 0
    private var twirlVelocity: CGFloat = 0
    private var blinker = Blinker()
    private var lastGhost: CGPoint?
    private var heading = restHeading

    init() {
        func fist() -> CAShapeLayer {
            Draw.shape(Draw.ellipse(0, 0, 6, 6), fill: Palette.mask, stroke: Ink.ink, width: 2.2)
        }
        let ghost = Draw.ellipse(0, 0, 6, 6)
        leftLimb = Limb(shoulder: Self.leftArm.shoulder, thickness: 6, armColor: Palette.suit,
                        hand: fist(), ghostPath: ghost, ghostColor: Palette.suit)
        rightLimb = Limb(shoulder: Self.rightArm.shoulder, thickness: 6, armColor: Palette.suit,
                         hand: fist(), ghostPath: ghost, ghostColor: Palette.suit)
        build()
    }

    // MARK: - Geometry

    /// A hood drawn to a point: the point is the hotspot.
    private static func headPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: -16, y: -20), control1: CGPoint(x: -6, y: -4), control2: CGPoint(x: -16, y: -10))
        p.addCurve(to: CGPoint(x: 0, y: -36), control1: CGPoint(x: -16, y: -30), control2: CGPoint(x: -9, y: -36))
        p.addCurve(to: CGPoint(x: 16, y: -20), control1: CGPoint(x: 9, y: -36), control2: CGPoint(x: 16, y: -30))
        p.addCurve(to: .zero, control1: CGPoint(x: 16, y: -10), control2: CGPoint(x: 6, y: -4))
        p.closeSubpath()
        return p
    }
    private static func bodyPath() -> CGPath { Draw.ellipse(0, -50, 15, 16.5) }

    // MARK: - Construction

    private func build() {
        shadow.addSublayer(Draw.shape(Draw.ellipse(5, -46, 21, 28), fill: Ink.shadow))
        root.addSublayer(shadow)
        root.addSublayer(Draw.halo([Self.headPath(), Self.bodyPath(),
                                    Draw.ellipse(-8, -66, 5.5, 4), Draw.ellipse(8, -66, 5.5, 4),
                                    Draw.ellipse(-17, -29, 6.5, 6.5), Draw.ellipse(17, -29, 6.5, 6.5)]))
        root.addSublayer(tailsInk)
        root.addSublayer(tailsBand)
        for x in [CGFloat(-8), 8] {
            root.addSublayer(Draw.shape(Draw.ellipse(x, -66, 5.5, 4), fill: Palette.suit, stroke: Ink.ink, width: 2))
        }
        root.addSublayer(Draw.outlined([Self.bodyPath()], fill: Palette.suit))
        root.addSublayer(Draw.shape(Draw.roundedRect(0, -51, 29, 4.5, 2), fill: Palette.band))
        root.addSublayer(Draw.outlined([Self.headPath()], fill: Palette.suit))
        root.addSublayer(Draw.shape(Draw.roundedRect(0, -14.5, 27, 10.5, 5.2), fill: Palette.mask))
        for side in [CGFloat(-1), 1] {
            // A soft halo behind each eye so the glow carries at cursor size.
            eyes.addSublayer(Draw.shape(Draw.ellipse(side * 6, -14.5, 5.5, 4), fill: Palette.glowSoft))
            eyes.addSublayer(Draw.shape(Draw.polygon([
                CGPoint(x: side * 2, y: -12.3), CGPoint(x: side * 10, y: -14.2), CGPoint(x: side * 2.4, y: -17.2)
            ]), fill: Palette.glow))
            let brow = CGMutablePath()
            brow.move(to: CGPoint(x: side * 10.5, y: -9.6))
            brow.addLine(to: CGPoint(x: side * 2, y: -11.6))
            root.addSublayer(Draw.shape(brow, fill: nil, stroke: Palette.suit, width: 2.4))
        }
        root.addSublayer(eyes)
        root.addSublayer(Draw.shape(Draw.roundedRect(0, -25, 30, 5, 2.5), fill: Palette.band, stroke: Ink.ink, width: 1.6))
        root.addSublayer(Draw.shape(Draw.ellipse(0, -36, 3, 3), fill: Palette.band, stroke: Ink.ink, width: 1.4))
        leftLimb.install(in: root)
        rightLimb.install(in: root)
    }

    // MARK: - Reactions

    func react(to reaction: Reaction, motion: Motion, fx: Effects) {
        let now = motion.now
        let size = root.affineTransform().scaleMagnitude * 100
        switch reaction {
        case .leftClick, .rightClick:
            if reaction == .leftClick { leftAt = now } else { rightAt = now }
            fx.over.emit(Draw.star(points: 8, outer: size * 0.11, inner: size * 0.05), at: motion.position,
                         now: now, life: 0.24, fill: Palette.star, stroke: Ink.ink, width: 1.3,
                         rotation: .random(in: -0.6...0.6), scale: (0.3, 1.1), alpha: (1, 0))
            Burst.impact(fx, at: motion.position, size: size, color: Ink.impact, now: now, count: 6)
        case .doubleClick:
            leftAt = -1
            rightAt = -1
            spinAt = now
            let centre = root.convert(Self.bodyCentre, to: fx.over.layer)
            for i in 0..<10 {
                let a = CGFloat(i) * 2 * .pi / 10
                Burst.puff(fx, at: CGPoint(x: centre.x + cos(a) * size * 0.3, y: centre.y + sin(a) * size * 0.3),
                           size: size, now: now,
                           velocity: CGVector(dx: cos(a) * size * 1.6, dy: sin(a) * size * 1.6),
                           life: 0.55, alpha: 0.5, growth: 2)
            }
            let shuriken = Draw.star(points: 4, outer: size * 0.08, inner: size * 0.028)
            for i in 0..<4 {
                let a = .pi / 4 + CGFloat(i) * .pi / 2
                fx.over.emit(shuriken, at: centre, now: now, life: 0.5,
                             fill: Palette.steel, stroke: Ink.ink, width: 1.2,
                             velocity: CGVector(dx: cos(a) * size * 7, dy: sin(a) * size * 7),
                             drag: 2.5, spin: 28, alpha: (1, 0))
            }
        case .scroll:
            break
        }
    }

    // MARK: - Frame

    func update(_ motion: Motion, size: CGFloat, fx: Effects) {
        let now = motion.now
        let dt = motion.dt

        let leanTarget = max(-0.25, min(0.25, -motion.velocity.dx / 4000))
        lean += (leanTarget - lean) * min(1, dt * 10)

        // A scroll twirl on a spring, so it always settles back.
        twirlVelocity += motion.scroll * 0.05
        twirlVelocity += (-twirl * 40 - twirlVelocity * 6) * dt
        twirl = max(-0.5, min(0.5, twirl + twirlVelocity * dt))

        var spin: CGFloat = 0
        var pulse: CGFloat = 1
        if let u = Ease.progress(since: spinAt, over: 0.55, now: now) {
            spin = 2 * .pi * Ease.outCubic(u)
            pulse = 1 + 0.12 * sin(.pi * u)
        }
        heading = restHeading + lean + spin + twirl
        let bounce = 1 + 0.025 * sin(CGFloat(now) * 8)
        let scale = size / 100 * pulse * bounce
        root.setAffineTransform(CGAffineTransform(rotationAngle: heading).scaledBy(x: scale, y: scale))

        for (limb, arm, start) in [(leftLimb, Self.leftArm, leftAt), (rightLimb, Self.rightArm, rightAt)] {
            if let u = Ease.progress(since: start, over: 0.24, now: now) {
                let s = Ease.strike(u)
                let trail = [0.25, 0.5].map { Ease.bezier(arm.rest, arm.control, arm.target, max(0, s - $0)) }
                limb.place(hand: Ease.bezier(arm.rest, arm.control, arm.target, s), scale: 1 + 0.15 * s,
                           trail: trail, trailAlpha: u < 0.3 ? 1 - u / 0.3 : 0)
            } else {
                limb.place(hand: arm.rest, scale: 1, trail: [], trailAlpha: 0)
            }
        }

        eyes.setAffineTransform(CGAffineTransform(scaleX: 1, y: blinker.openness(at: now)))

        // Headband tails stream against the direction of travel, in body space.
        let k = max(scale, 0.01)
        let c = cos(-heading), n = sin(-heading)
        let bvx = (motion.velocity.dx * c - motion.velocity.dy * n) / k
        let bvy = (motion.velocity.dx * n + motion.velocity.dy * c) / k
        let length = hypot(bvx, bvy) * 0.02
        let cap = length > 18 ? 18 / length : 1
        let trail = CGPoint(x: -bvx * 0.02 * cap, y: -bvy * 0.02 * cap)
        let tails = CGMutablePath()
        for (side, offset) in [(CGFloat(-1), CGFloat(0)), (1, 1.3)] {
            let end = CGPoint(x: side * 9 + trail.x + sin(CGFloat(now) * 14 + offset) * 2.5, y: -56 + trail.y)
            tails.move(to: CGPoint(x: side * 2, y: -36))
            tails.addQuadCurve(to: end, control: CGPoint(x: side * 6, y: -46))
        }
        tailsInk.path = tails
        tailsBand.path = tails

        // After-images on fast dashes.
        if motion.speed > 600 {
            let far = lastGhost.map { hypot(motion.position.x - $0.x, motion.position.y - $0.y) > size * 0.3 } ?? true
            if far {
                lastGhost = motion.position
                let t = CGAffineTransform(rotationAngle: heading).scaledBy(x: scale, y: scale)
                let silhouette = CGMutablePath()
                silhouette.addPath(Self.headPath(), transform: t)
                silhouette.addPath(Self.bodyPath(), transform: t)
                fx.under.emit(silhouette, at: motion.position, now: now, life: 0.22,
                              fill: Palette.suit, alpha: (0.32, 0))
            }
        }
    }
}
