import AppKit
import QuartzCore

/// Pocket Dragon: an original chibi dragon. The snout is the pointer.
///
/// - left click: chomp — the head snaps shut, two teeth meet on the spot you clicked
/// - right click: wing gust — one big flap, wind curls off behind
/// - double click: fire breath — a short cone of flame from the snout
/// - scroll: tail whip and a flutter
/// - move: wings beat faster, embers drift off the tail
/// - idle: slow wingbeat, blinks, the odd puff of smoke from the nostrils
final class DragonRig: CharacterRig {
    let root = Draw.root(space: CGRect(x: -72, y: -126, width: 144, height: 160))

    private enum Palette {
        static let scales = Ink.rgb(0.36, 0.73, 0.50)
        static let dark = Ink.rgb(0.23, 0.54, 0.36)
        static let wing = Ink.rgb(0.65, 0.88, 0.78)
        static let cream = Ink.rgb(0.98, 0.93, 0.75)
        static let cheek = Ink.rgb(0.94, 0.55, 0.63, 0.7)
        static let flames = [Ink.rgb(1.0, 0.82, 0.40), Ink.rgb(1.0, 0.55, 0.16), Ink.rgb(0.94, 0.29, 0.14)]
        static let ember = Ink.rgb(1.0, 0.55, 0.16)
    }

    private static let headCentre = CGPoint(x: 0, y: -20)
    private static let shoulders = [CGPoint(x: -12, y: -40), CGPoint(x: 12, y: -40)]
    private static let wingPoints: [CGPoint] = [
        CGPoint(x: 0, y: 2), CGPoint(x: -26, y: 14), CGPoint(x: -36, y: -2), CGPoint(x: -29, y: -6),
        CGPoint(x: -27, y: -13), CGPoint(x: -19, y: -12), CGPoint(x: -15, y: -18), CGPoint(x: -6, y: -11),
        CGPoint(x: 0, y: -4)
    ]
    private static let wingBones: [CGPoint] = [CGPoint(x: -26, y: 14), CGPoint(x: -36, y: -2), CGPoint(x: -27, y: -13)]

    private let wings: [CALayer]
    private let tailHalo = Draw.shape(nil, fill: nil, stroke: Ink.halo, width: 13)
    private let tailInk = Draw.shape(nil, fill: nil, stroke: Ink.ink, width: 10)
    private let tailFill = Draw.shape(nil, fill: nil, stroke: Palette.scales, width: 6)
    private let spade = Draw.group()
    private let head = Draw.group(pivot: headCentre)
    private let lids = [CGPoint(x: -6.5, y: -20), CGPoint(x: 6.5, y: -20)].map { Draw.group(pivot: $0) }

    // State.
    private var chompAt: CFTimeInterval = -1
    private var gustAt: CFTimeInterval = -1
    private var fireAt: CFTimeInterval = -1
    private var flap: CGFloat = 0
    private var lean: CGFloat = 0
    private var tailSpin: CGFloat = 0
    private var tailVelocity: CGFloat = 0
    private var blinker = Blinker()
    private var heading = restHeading
    private var lastEmberAt: CFTimeInterval = 0
    private var lastSmokeAt: CFTimeInterval = 0

    init() {
        wings = Self.shoulders.map { shoulder in
            let group = Draw.group(pivot: shoulder)
            let mirror: CGFloat = shoulder.x < 0 ? 1 : -1
            let points = Self.wingPoints.map { CGPoint(x: shoulder.x + $0.x * mirror, y: shoulder.y + $0.y) }
            let membrane = Draw.polygon(points)
            group.addSublayer(Draw.shape(membrane, fill: Ink.halo, stroke: Ink.halo, width: 7))
            group.addSublayer(Draw.shape(membrane, fill: Palette.wing, stroke: Ink.ink, width: 2))
            let bones = CGMutablePath()
            for b in Self.wingBones {
                bones.move(to: shoulder)
                bones.addLine(to: CGPoint(x: shoulder.x + b.x * mirror, y: shoulder.y + b.y))
            }
            group.addSublayer(Draw.shape(bones, fill: nil, stroke: Ink.ink, width: 1.4))
            return group
        }
        build()
    }

    private func snoutPath() -> CGPath { Draw.ellipse(0, -9, 7.5, 9.5) }
    private func headPath() -> CGPath { Draw.ellipse(0, -23, 15, 13.5) }
    private func bodyPath() -> CGPath { Draw.ellipse(1, -52, 17, 22, rotation: .pi / 24) }

    private func tailPath(wag: CGFloat) -> (CGPath, CGPoint, CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 3, y: -72))
        path.addCurve(to: CGPoint(x: 14 + wag, y: -98),
                      control1: CGPoint(x: 8, y: -86), control2: CGPoint(x: 18 + wag, y: -88))
        let end = CGPoint(x: 8 + wag * 0.5, y: -104)
        path.addQuadCurve(to: end, control: CGPoint(x: 11 + wag, y: -103))
        let angle = atan2(end.y - (-103), end.x - (11 + wag))
        return (path, end, angle)
    }

    private func build() {
        root.addSublayer(Draw.shape(Draw.ellipse(6, -55, 22, 26), fill: Ink.shadow))
        wings.forEach { root.addSublayer($0) }
        root.addSublayer(Draw.halo([snoutPath(), headPath(), bodyPath(),
                                    Draw.ellipse(-11, -68, 5.5, 4), Draw.ellipse(11, -68, 5.5, 4)]))
        root.addSublayer(tailHalo)
        root.addSublayer(tailInk)
        root.addSublayer(tailFill)
        let spadePath = Draw.polygon([CGPoint(x: 6, y: 0), CGPoint(x: -1, y: 5), CGPoint(x: -4, y: 0), CGPoint(x: -1, y: -5)])
        spade.addSublayer(Draw.shape(spadePath, fill: Ink.halo, stroke: Ink.halo, width: 4))
        spade.addSublayer(Draw.shape(spadePath, fill: Palette.dark, stroke: Ink.ink, width: 1.6))
        root.addSublayer(spade)
        for x in [CGFloat(-11), 11] {
            root.addSublayer(Draw.shape(Draw.ellipse(x, -68, 5.5, 4), fill: Palette.dark, stroke: Ink.ink, width: 2))
        }
        root.addSublayer(Draw.outlined([bodyPath()], fill: Palette.scales))
        for y in [CGFloat(-38), -50, -62] {
            root.addSublayer(Draw.shape(Draw.polygon([CGPoint(x: -3.5, y: y + 3), CGPoint(x: 3.5, y: y + 3),
                                                      CGPoint(x: 0, y: y - 4)]),
                                        fill: Palette.dark, stroke: Ink.ink, width: 1.2))
        }
        for side in [CGFloat(-1), 1] {
            root.addSublayer(Draw.shape(Draw.polygon([CGPoint(x: side * 6, y: -31), CGPoint(x: side * 11, y: -31),
                                                      CGPoint(x: side * 15, y: -44)]),
                                        fill: Palette.cream, stroke: Ink.ink, width: 2))
        }
        root.addSublayer(head)
        head.addSublayer(Draw.outlined([headPath(), snoutPath()], fill: Palette.scales))
        for side in [CGFloat(-1), 1] {
            head.addSublayer(Draw.shape(Draw.ellipse(side * 10.5, -14, 2.6, 1.8), fill: Palette.cheek))
            head.addSublayer(Draw.shape(Draw.ellipse(side * 2.4, -3.5, 1, 1), fill: Ink.ink))
        }
        for lid in lids {
            let c = lid.position
            lid.addSublayer(Draw.shape(Draw.ellipse(c.x, c.y, 3.6, 3.6), fill: Ink.ink))
            lid.addSublayer(Draw.shape(Draw.ellipse(c.x - 1, c.y + 1, 1.2, 1.2), fill: Ink.halo))
            head.addSublayer(lid)
        }
    }

    // MARK: - Reactions

    func react(to reaction: Reaction, motion: Motion, fx: Effects) {
        let now = motion.now
        let size = root.affineTransform().scaleMagnitude * 100
        let forward = Angle.forward(heading)
        switch reaction {
        case .leftClick:
            chompAt = now
            Burst.impact(fx, at: motion.position, size: size, color: Ink.impact, now: now, count: 6)
            // Two teeth close on the click point from either side.
            let tooth = Draw.polygon([CGPoint(x: 0, y: size * 0.04), CGPoint(x: -size * 0.035, y: -size * 0.03),
                                      CGPoint(x: size * 0.035, y: -size * 0.03)])
            for side in [CGFloat(-1), 1] {
                let across = forward + side * .pi / 2
                let start = CGPoint(x: motion.position.x + cos(across) * size * 0.1,
                                    y: motion.position.y + sin(across) * size * 0.1)
                fx.over.emit(tooth, at: start, now: now, life: 0.14,
                             fill: Ink.halo, stroke: Ink.ink, width: 1,
                             velocity: CGVector(dx: -cos(across) * size * 0.7, dy: -sin(across) * size * 0.7),
                             rotation: across + .pi / 2, alpha: (1, 0))
            }
        case .rightClick:
            gustAt = now
            let back = forward + .pi
            for (i, shoulder) in Self.shoulders.enumerated() {
                let tip = CGPoint(x: shoulder.x + (i == 0 ? -34 : 34), y: shoulder.y)
                for j in 0..<2 {
                    let at = root.convert(CGPoint(x: tip.x, y: tip.y - CGFloat(j) * 8), to: fx.under.layer)
                    let out: CGFloat = i == 0 ? 1 : -1
                    fx.under.emit(Draw.arc(radius: size * 0.1, spread: 1.4), at: at, now: now, life: 0.45,
                                  fill: nil, stroke: Ink.ink, width: max(1.2, size * 0.025),
                                  velocity: CGVector(dx: cos(back) * size * 2 + out * .random(in: 6...20),
                                                     dy: sin(back) * size * 2),
                                  drag: 2.5, rotation: back, scale: (0.8, 1.5), alpha: (0.45, 0))
                }
            }
        case .doubleClick:
            chompAt = -1
            fireAt = now
            Burst.impact(fx, at: motion.position, size: size, color: Ink.orange, now: now, count: 10)
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
        flap += dt * (4 + min(motion.speed, 1500) * 0.006) + abs(motion.scroll) * 0.15
        tailVelocity += motion.scroll * 0.9
        tailSpin += tailVelocity * dt
        tailVelocity *= pow(0.02, dt)

        let fire = Ease.progress(since: fireAt, over: 0.6, now: now)
        let recoil = fire.map { 1 + 0.04 * sin(.pi * $0) } ?? 1
        heading = restHeading + lean
        let scale = size / 100 * recoil
        root.setAffineTransform(CGAffineTransform(rotationAngle: heading).scaledBy(x: scale, y: scale))

        // Wings: a steady beat, one big sweep on a gust.
        var sweep = 0.22 * sin(flap)
        var span = 0.85 + 0.15 * cos(flap)
        if let u = Ease.progress(since: gustAt, over: 0.45, now: now) {
            sweep += 0.75 * sin(.pi * u)
            span = 1.1
        }
        wings[0].setAffineTransform(CGAffineTransform(rotationAngle: sweep).scaledBy(x: span, y: 1))
        wings[1].setAffineTransform(CGAffineTransform(rotationAngle: -sweep).scaledBy(x: span, y: 1))

        let wag = sin(CGFloat(now) * 2.6 + tailSpin) * 5
        let (tail, end, angle) = tailPath(wag: wag)
        tailHalo.path = tail
        tailInk.path = tail
        tailFill.path = tail
        spade.position = end
        spade.setAffineTransform(CGAffineTransform(rotationAngle: angle))

        let chomp = Ease.progress(since: chompAt, over: 0.22, now: now).map { sin(.pi * $0) } ?? 0
        head.setAffineTransform(CGAffineTransform(scaleX: 1 + 0.08 * chomp, y: 1 - 0.14 * chomp))
        let open = blinker.openness(at: now)
        lids.forEach { $0.setAffineTransform(CGAffineTransform(scaleX: 1, y: open)) }

        // Fire stays short: it starts on the snout and burns out within about a
        // body length, so it reads as coming from the click, not landing elsewhere.
        let forward = Angle.forward(heading)
        if fire != nil {
            let disc = Draw.ellipse(0, 0, size * 0.05, size * 0.05)
            for _ in 0..<3 {
                let a = forward + .random(in: -0.25...0.25)
                let speed = size * .random(in: 2.4...3.4)
                fx.over.emit(disc, at: motion.position, now: now, life: .random(in: 0.3...0.42),
                             fill: Palette.flames.randomElement()!,
                             velocity: CGVector(dx: cos(a) * speed, dy: sin(a) * speed),
                             drag: 3, gravity: CGVector(dx: 0, dy: size * 0.8),
                             scale: (0.5, 1.8), alpha: (0.95, 0))
            }
        }

        if motion.speed > 250 && now - lastEmberAt > 0.04 {
            lastEmberAt = now
            let at = root.convert(end, to: fx.under.layer)
            fx.under.emit(Draw.ellipse(0, 0, size * 0.018, size * 0.018), at: at, now: now, life: 0.45,
                          fill: Palette.ember,
                          velocity: CGVector(dx: .random(in: -1...1) * size * 0.8, dy: .random(in: -1...1) * size * 0.8),
                          gravity: CGVector(dx: 0, dy: size * 0.8), alpha: (1, 0))
        }

        if motion.idle > 1.5 && now - lastSmokeAt > 3.2 {
            lastSmokeAt = now
            for x in [CGFloat(-2.4), 2.4] {
                let at = root.convert(CGPoint(x: x, y: -3.5), to: fx.over.layer)
                Burst.puff(fx, at: at, size: size * 0.6, now: now,
                           velocity: CGVector(dx: cos(forward) * size * 0.6, dy: sin(forward) * size * 0.6),
                           life: 0.9, alpha: 0.4, growth: 2, above: true)
            }
        }
    }
}
