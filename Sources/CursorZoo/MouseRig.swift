import AppKit
import QuartzCore

/// The Tiny Mouse, after the Polymet playground sticker. The nose is the pointer.
///
/// - left click: the **left** paw swings round and slaps the spot you clicked
/// - right click: the **right** paw does
/// - double click: a happy hop — springs up off its shadow, hearts pop, no paws
/// - scroll: the tail whips
/// - move: leans into the turn, feet patter, tiny paw prints trail behind
/// - idle: breathes, blinks, wags
final class MouseRig: CharacterRig {
    let root = Draw.root(space: CGRect(x: -66, y: -128, width: 140, height: 160))

    private enum Palette {
        static let fur = Ink.rgb(0.66, 0.61, 0.58)
        static let stripe = Ink.rgb(0.79, 0.75, 0.72)
        static let pink = Ink.rgb(0.95, 0.63, 0.70)
        static let pinkDeep = Ink.rgb(0.90, 0.50, 0.60)
    }

    // Body space: nose at the origin, body hanging in -y.
    private static let headCentre = CGPoint(x: 0, y: -19)
    private static let bodyCentre = CGPoint(x: 2, y: -55)
    /// Both ears sit behind the head, so neither can cover an eye.
    private static let ears = [CGPoint(x: -15, y: -29), CGPoint(x: 15, y: -29)]
    private static let earRadius: CGFloat = 11
    private static let eyes = [CGPoint(x: -5.8, y: -17.5), CGPoint(x: 5.8, y: -17.5)]
    private static let leftFoot = CGPoint(x: -13, y: -80)
    private static let rightFoot = CGPoint(x: 19, y: -78)

    private struct Arm {
        let shoulder: CGPoint
        let rest: CGPoint
        let control: CGPoint
        let target: CGPoint
    }
    // Each paw sweeps out and round onto the nose, so the slap lands where you clicked.
    private static let leftArm = Arm(shoulder: CGPoint(x: -13, y: -37), rest: CGPoint(x: -17, y: -41),
                                     control: CGPoint(x: -32, y: -16), target: CGPoint(x: -7, y: -3))
    private static let rightArm = Arm(shoulder: CGPoint(x: 13, y: -37), rest: CGPoint(x: 17, y: -41),
                                      control: CGPoint(x: 32, y: -16), target: CGPoint(x: 7, y: -3))

    private let shadow = Draw.group(pivot: bodyCentre)
    private let tail = Draw.shape(nil, fill: nil, stroke: Palette.pink, width: 5.5)
    private let tailHalo = Draw.shape(nil, fill: nil, stroke: Ink.halo, width: 10.5)
    private let body = Draw.group(pivot: bodyCentre)
    private let head = Draw.group(pivot: headCentre)
    private let lids = MouseRig.eyes.map { Draw.group(pivot: $0) }
    private let whiskers = Draw.group(pivot: CGPoint(x: 0, y: -9))
    private let leftFootLayer = Draw.shape(Draw.ellipse(0, 0, 6.5, 5, rotation: -0.4),
                                           fill: Palette.pink, stroke: Ink.ink, width: 2.4)
    private let rightFootLayer = Draw.shape(Draw.ellipse(0, 0, 6.5, 5, rotation: 0.3),
                                            fill: Palette.pink, stroke: Ink.ink, width: 2.4)
    private let leftLimb: Limb
    private let rightLimb: Limb

    // State.
    private var leftAt: CFTimeInterval = -1
    private var rightAt: CFTimeInterval = -1
    private var hopAt: CFTimeInterval = -1
    private var lean: CGFloat = 0
    private var tailSpin: CGFloat = 0
    private var tailVelocity: CGFloat = 0
    private var feetPhase: CGFloat = 0
    private var blinker = Blinker()
    private var lastPrint: CGPoint?
    private var printLeft = true
    private var heading = restHeading

    init() {
        func paw() -> CAShapeLayer {
            Draw.shape(Draw.ellipse(0, 0, 7.5, 7.5), fill: Palette.pink, stroke: Ink.ink, width: 2.6)
        }
        let ghost = Draw.ellipse(0, 0, 7.5, 7.5)
        leftLimb = Limb(shoulder: Self.leftArm.shoulder, thickness: 5, armColor: Palette.fur,
                        hand: paw(), ghostPath: ghost, ghostColor: Palette.pink)
        rightLimb = Limb(shoulder: Self.rightArm.shoulder, thickness: 5, armColor: Palette.fur,
                         hand: paw(), ghostPath: ghost, ghostColor: Palette.pink)
        build()
    }

    // MARK: - Geometry

    private func snoutPath() -> CGPath { Draw.ellipse(0, -8.5, 6.5, 7.5) }
    private func headPath() -> CGPath { Draw.ellipse(0, -19, 14, 14.5) }
    private func bodyPath() -> CGPath { Draw.ellipse(2, -55, 21, 30, rotation: .pi / 22) }
    private func earPath(_ c: CGPoint) -> CGPath { Draw.ellipse(c.x, c.y, Self.earRadius, Self.earRadius) }

    private func tailPath(phase: CGFloat) -> CGPath {
        let wag = sin(phase) * 3.5
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 9, y: -83))
        path.addCurve(to: CGPoint(x: 37, y: -90 + wag),
                      control1: CGPoint(x: 19, y: -91), control2: CGPoint(x: 29, y: -83 + wag))
        path.addCurve(to: CGPoint(x: 44, y: -106 + wag),
                      control1: CGPoint(x: 46, y: -97 + wag), control2: CGPoint(x: 50, y: -104 + wag))
        path.addCurve(to: CGPoint(x: 35, y: -101 + wag),
                      control1: CGPoint(x: 40, y: -108 + wag), control2: CGPoint(x: 35, y: -106 + wag))
        return path
    }

    // MARK: - Construction

    private func build() {
        shadow.addSublayer(Draw.shape(Draw.ellipse(7, -60, 23, 31, rotation: .pi / 22), fill: Ink.shadow))
        root.addSublayer(shadow)

        root.addSublayer(Draw.halo([
            snoutPath(), headPath(), bodyPath(),
            earPath(Self.ears[0]), earPath(Self.ears[1]),
            Draw.ellipse(Self.leftArm.rest.x, Self.leftArm.rest.y, 7.5, 7.5),
            Draw.ellipse(Self.rightArm.rest.x, Self.rightArm.rest.y, 7.5, 7.5),
            Draw.ellipse(Self.leftFoot.x, Self.leftFoot.y, 6.5, 5),
            Draw.ellipse(Self.rightFoot.x, Self.rightFoot.y, 6.5, 5)
        ]))

        root.addSublayer(tailHalo)
        root.addSublayer(tail)

        root.addSublayer(body)
        body.addSublayer(Draw.outlined([bodyPath()], fill: Palette.fur))
        body.addSublayer(Draw.shape(Draw.ellipse(1, -57, 6, 21, rotation: .pi / 22), fill: Palette.stripe))
        leftFootLayer.position = Self.leftFoot
        rightFootLayer.position = Self.rightFoot
        body.addSublayer(leftFootLayer)
        body.addSublayer(rightFootLayer)

        // Ears over the body but under the head.
        for c in Self.ears {
            root.addSublayer(Draw.outlined([earPath(c)], fill: Palette.fur))
            let inner = Self.earRadius * 0.62
            root.addSublayer(Draw.shape(Draw.ellipse(c.x + (c.x < 0 ? -0.4 : 0.4), c.y - 0.4, inner, inner),
                                        fill: Palette.pink))
        }

        root.addSublayer(head)
        head.addSublayer(Draw.outlined([headPath(), snoutPath()], fill: Palette.fur))
        for (lid, eye) in zip(lids, Self.eyes) {
            lid.addSublayer(Draw.shape(Draw.ellipse(eye.x, eye.y, 2.6, 2.6), fill: Ink.ink))
            lid.addSublayer(Draw.shape(Draw.ellipse(eye.x - 0.9, eye.y + 0.9, 0.9, 0.9), fill: Ink.halo))
            head.addSublayer(lid)
        }
        head.addSublayer(Draw.shape(Draw.ellipse(0, -3.4, 2.7, 2.3), fill: Palette.pinkDeep,
                                    stroke: Ink.ink, width: 1.5))
        let whiskerPath = CGMutablePath()
        for side in [CGFloat(-1), 1] {
            for (dy, length) in [(CGFloat(3), CGFloat(13)), (-1, 14), (-5, 12)] {
                whiskerPath.move(to: CGPoint(x: side * 6, y: -9))
                whiskerPath.addLine(to: CGPoint(x: side * (6 + length), y: -9 + dy))
            }
        }
        let whiskerLayer = Draw.shape(whiskerPath, fill: nil, stroke: Ink.ink, width: 1.2)
        whiskerLayer.opacity = 0.55
        whiskers.addSublayer(whiskerLayer)
        head.addSublayer(whiskers)

        // Arms on top of everything: a slap reaches across the face.
        leftLimb.install(in: root)
        rightLimb.install(in: root)
    }

    // MARK: - Reactions

    func react(to reaction: Reaction, motion: Motion, fx: Effects) {
        let now = motion.now
        let size = root.affineTransform().scaleMagnitude * 100
        switch reaction {
        case .leftClick:
            leftAt = now
            Burst.impact(fx, at: motion.position, size: size, color: Ink.impact, now: now)
        case .rightClick:
            rightAt = now
            Burst.impact(fx, at: motion.position, size: size, color: Ink.impact, now: now)
        case .doubleClick:
            // The first press already slapped; the second is pure joy, no paws.
            leftAt = -1
            rightAt = -1
            hopAt = now
            Burst.impact(fx, at: motion.position, size: size, color: Ink.orange, now: now, count: 10)
            let top = root.convert(Self.headCentre, to: fx.over.layer)
            let heart = Draw.heart(size * 0.085)
            for i in 0..<3 {
                let dx = CGFloat(i - 1) * size * 1.4 + .random(in: -8...8)
                fx.over.emit(heart, at: top, now: now, life: 0.8,
                             fill: Palette.pink, stroke: Ink.ink, width: 1.1,
                             velocity: CGVector(dx: dx, dy: size * .random(in: 2.8...3.6)),
                             drag: 2.2, rotation: CGFloat(i - 1) * -0.35,
                             scale: (0.4, 1.05), alpha: (1, 0))
            }
        case .scroll:
            break
        }
    }

    // MARK: - Frame

    func update(_ motion: Motion, size: CGFloat, fx: Effects) {
        let now = motion.now
        let dt = motion.dt
        let scale = size / 100

        // Lean into horizontal travel.
        let leanTarget = max(-0.28, min(0.28, -motion.velocity.dx / 4000))
        lean += (leanTarget - lean) * min(1, dt * 10)

        // Happy hop: rise, hang, land with a squash.
        var lift: CGFloat = 0
        var landing: CGFloat = 0
        var wobble: CGFloat = 0
        if let t = Ease.progress(since: hopAt, over: 0.52, now: now) {
            if t < 0.78 {
                lift = sin(.pi * t / 0.78)
                wobble = sin(2 * .pi * t / 0.78) * 0.1
            } else {
                landing = sin(.pi * (t - 0.78) / 0.22)
            }
        }

        // One paw per click.
        let left = slap(since: leftAt, now: now)
        let right = slap(since: rightAt, now: now)
        place(leftLimb, arm: Self.leftArm, slap: left)
        place(rightLimb, arm: Self.rightArm, slap: right)

        // The body gives a little on every hit and a lot on landing; breathes at rest.
        let hit = max(left.map { sin(.pi * $0.u) } ?? 0, right.map { sin(.pi * $0.u) } ?? 0)
        let squash = hit * 0.45 + landing * 0.9
        let breath = 1 + sin(CGFloat(now) * 2.4) * 0.012
        body.setAffineTransform(CGAffineTransform(scaleX: (1 + 0.14 * squash) * breath,
                                                  y: (1 - 0.12 * squash) * breath))

        // Squint into the slap; blink at rest.
        let effort = max(left?.s ?? 0, right?.s ?? 0)
        let open = min(blinker.openness(at: now), 1 - effort * 0.5)
        lids.forEach { $0.setAffineTransform(CGAffineTransform(scaleX: 1, y: open)) }

        // Head ducks into a hit about its own centre.
        head.setAffineTransform(CGAffineTransform(scaleX: 1 + hit * 0.05, y: 1 - hit * 0.06))
        whiskers.setAffineTransform(CGAffineTransform(rotationAngle: sin(CGFloat(now) * 1.7) * 0.03
                                                      + hit * 0.12))

        // Feet patter with speed and tuck in mid-hop.
        let run = min(1, motion.speed / 500)
        feetPhase += dt * (8 + min(motion.speed, 1500) * 0.03)
        leftFootLayer.position = CGPoint(x: Self.leftFoot.x, y: Self.leftFoot.y + sin(feetPhase) * 4 * run)
        rightFootLayer.position = CGPoint(x: Self.rightFoot.x,
                                          y: Self.rightFoot.y + sin(feetPhase + .pi) * 4 * run)
        let tuck = 1 - 0.45 * lift
        leftFootLayer.setAffineTransform(CGAffineTransform(scaleX: tuck, y: tuck))
        rightFootLayer.setAffineTransform(CGAffineTransform(scaleX: tuck, y: tuck))

        // Tail: slow wag, whipped by the scroll wheel.
        tailVelocity += motion.scroll * 0.9
        tailSpin += tailVelocity * dt
        tailVelocity *= pow(0.02, dt)
        let tailShape = tailPath(phase: CGFloat(now) * 2.4 + tailSpin)
        tail.path = tailShape
        tailHalo.path = tailShape

        // The jump is a scale-up about the nose; the shadow left on the ground
        // shrinks and slides away, which is what sells the height.
        let rootScale = scale * (1 + 0.2 * lift)
        let shadowScale = (1 - 0.3 * lift) / (1 + 0.2 * lift)
        shadow.setAffineTransform(CGAffineTransform(translationX: 6 * lift, y: -8 * lift)
            .scaledBy(x: shadowScale, y: shadowScale))
        shadow.opacity = Float(1 - 0.55 * lift)

        heading = restHeading + lean + wobble
        root.setAffineTransform(CGAffineTransform(rotationAngle: heading)
            .scaledBy(x: rootScale, y: rootScale))

        leavePrints(motion, size: size, fx: fx)
    }

    // MARK: - Helpers

    private func slap(since start: CFTimeInterval, now: CFTimeInterval) -> (s: CGFloat, u: CGFloat)? {
        guard let u = Ease.progress(since: start, over: 0.3, now: now) else { return nil }
        return (Ease.strike(u), u)
    }

    private func place(_ limb: Limb, arm: Arm, slap: (s: CGFloat, u: CGFloat)?) {
        guard let slap else {
            limb.place(hand: arm.rest, scale: 1, trail: [], trailAlpha: 0)
            return
        }
        let point = Ease.bezier(arm.rest, arm.control, arm.target, slap.s)
        let trail = [0.22, 0.44].map { Ease.bezier(arm.rest, arm.control, arm.target, max(0, slap.s - $0)) }
        let striking = slap.u < 0.36
        limb.place(hand: point, scale: 1 + 0.2 * slap.s, trail: trail,
                   trailAlpha: striking ? 1 - slap.u / 0.36 : 0)
    }

    /// Tiny prints, alternating feet, every half a body-length of travel.
    private func leavePrints(_ motion: Motion, size: CGFloat, fx: Effects) {
        guard motion.speed > 70 else { return }
        if let last = lastPrint,
           hypot(motion.position.x - last.x, motion.position.y - last.y) < size * 0.55 { return }
        lastPrint = motion.position
        let foot = printLeft ? Self.leftFoot : Self.rightFoot
        printLeft.toggle()
        let at = root.convert(foot, to: fx.under.layer)
        let s = size / 100
        let print = CGMutablePath()
        print.addPath(Draw.ellipse(0, 0, 3.2 * s, 3.8 * s))
        for (x, y) in [(-3.0, 4.6), (0.0, 5.8), (3.0, 4.6)] as [(CGFloat, CGFloat)] {
            print.addPath(Draw.ellipse(x * s, y * s, 1.3 * s, 1.5 * s))
        }
        fx.under.emit(print, at: at, now: motion.now, life: 1.1, fill: Ink.ink,
                      rotation: Angle.heading(of: motion.velocity), alpha: (0.22, 0))
    }
}

extension CGAffineTransform {
    /// Uniform scale factor of a rotation+scale transform.
    var scaleMagnitude: CGFloat { sqrt(a * a + c * c) }
}
