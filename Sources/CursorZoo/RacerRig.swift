import AppKit
import QuartzCore

/// Lil Racer: an original little top-down race car. The front bumper is the pointer.
///
/// - move: driven like a real car — the pointer tows the bumper and the rear axle
///   follows, so it turns through smooth arcs; front wheels steer by the bicycle
///   model and the rear tyres lay continuous tread marks that darken where they
///   would slip (hard corners, hard launches and stops)
/// - left click: honk — headlights double-flash, sound waves, a bounce on the springs
/// - right click: donut — a full spin about the front bumper in a ring of smoke and skid arcs
/// - double click: nitro — flames from both pipes, speed lines, the whole car shakes
/// - scroll: revs — wheels spin up, exhaust puffs, engine shudder
/// - idle: settles back to the arrow heading, idles with a faint shake, the odd puff
final class RacerRig: CharacterRig {
    let root = Draw.root(space: CGRect(x: -62, y: -112, width: 124, height: 170))

    private enum Palette {
        static let paint = Ink.rgb(0.95, 0.30, 0.18)
        static let stripe = Ink.rgb(1, 1, 1, 0.95)
        static let glass = Ink.rgb(0.26, 0.33, 0.46)
        static let tyre = Ink.rgb(0.17, 0.16, 0.16)
        static let tread = Ink.rgb(0.44, 0.43, 0.42)
        static let lamp = Ink.rgb(1.0, 0.95, 0.72)
        static let tailLamp = Ink.rgb(0.98, 0.18, 0.22)
        static let beam = Ink.rgb(1.0, 0.94, 0.55)
        static let flameOuter = Ink.rgb(1.0, 0.45, 0.10)
        static let flameInner = Ink.rgb(1.0, 0.88, 0.35)
        static let pipe = Ink.rgb(0.62, 0.62, 0.64)
        static let track = Ink.rgb(0.16, 0.15, 0.15)
    }

    // Body space: front bumper on the origin, car facing +y.
    private static let bodyCentre = CGPoint(x: 0, y: -35.5)
    private static let bodySize = CGSize(width: 34, height: 64)
    private static let frontWheels = [CGPoint(x: -18, y: -19), CGPoint(x: 18, y: -19)]
    private static let rearWheels = [CGPoint(x: -18, y: -53), CGPoint(x: 18, y: -53)]
    private static let pipes = [CGPoint(x: -7, y: -69), CGPoint(x: 7, y: -69)]

    /// A tyre seen from above: treads scroll inside a clipped rounded rect.
    private final class Wheel {
        let layer = CALayer()
        private let treads: [CALayer]

        init(at centre: CGPoint) {
            layer.bounds = CGRect(x: -5, y: -8.5, width: 10, height: 17)
            layer.position = centre
            layer.cornerRadius = 3.5
            layer.backgroundColor = Palette.tyre
            layer.borderColor = Ink.ink
            layer.borderWidth = 1.6
            layer.masksToBounds = true
            treads = (0..<4).map { _ in
                let t = CALayer()
                t.bounds = CGRect(x: 0, y: 0, width: 10, height: 1.8)
                t.backgroundColor = Palette.tread
                return t
            }
            treads.forEach { layer.addSublayer($0) }
        }

        func update(roll: CGFloat, steer: CGFloat) {
            for (i, tread) in treads.enumerated() {
                var y = (roll + CGFloat(i) * 5).truncatingRemainder(dividingBy: 20)
                if y < 0 { y += 20 }
                tread.position = CGPoint(x: 0, y: y - 10)
            }
            layer.setAffineTransform(CGAffineTransform(rotationAngle: steer))
        }
    }

    private let shadow = Draw.group(pivot: bodyCentre)
    private let body = Draw.group(pivot: bodyCentre)
    private let beams = Draw.group()
    private let flames: [CALayer]
    private let front = RacerRig.frontWheels.map { Wheel(at: $0) }
    private let rear = RacerRig.rearWheels.map { Wheel(at: $0) }

    // State.
    private var heading = restHeading
    private var turnRate: CGFloat = 0
    private var roll: CGFloat = 0
    private var rev: CGFloat = 0
    /// One continuous trail per rear tyre.
    private let trails = [UUID(), UUID()]
    private var honkAt: CFTimeInterval = -1
    private var driftAt: CFTimeInterval = -1
    private var driftSign: CGFloat = 1
    private var nitroAt: CFTimeInterval = -1
    private var lastPuffAt: CFTimeInterval = 0
    /// Rear-axle reference point in view space; the bumper (the hotspot) tows it.
    private var rearAxle: CGPoint?
    private var steerAngle: CGFloat = 0
    private var smoothSpeed: CGFloat = 0
    /// How hard the tyres are working, 0...1. Darkens the marks.
    private var slip: CGFloat = 0

    /// Body units from the front bumper back to the rear axle, and axle to axle.
    private static let towLength: CGFloat = 53
    private static let wheelbase: CGFloat = 34

    init() {
        flames = RacerRig.pipes.map { pipe in
            let group = Draw.group(pivot: pipe)
            for (colour, w, l) in [(Palette.flameOuter, CGFloat(3.4), CGFloat(20)),
                                   (Palette.flameInner, 1.8, 12)] {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: pipe.x - w, y: pipe.y))
                path.addQuadCurve(to: CGPoint(x: pipe.x, y: pipe.y - l),
                                  control: CGPoint(x: pipe.x - w, y: pipe.y - l * 0.6))
                path.addQuadCurve(to: CGPoint(x: pipe.x + w, y: pipe.y),
                                  control: CGPoint(x: pipe.x + w, y: pipe.y - l * 0.6))
                path.closeSubpath()
                group.addSublayer(Draw.shape(path, fill: colour))
            }
            group.opacity = 0
            return group
        }
        build()
    }

    private func build() {
        // Headlight beams reach out in front, past the hotspot. Dark until a honk.
        for x in [CGFloat(-10), 10] {
            beams.addSublayer(Draw.shape(Draw.polygon([
                CGPoint(x: x - 3, y: -4), CGPoint(x: x + 3, y: -4),
                CGPoint(x: x + 11, y: 34), CGPoint(x: x - 11, y: 34)
            ]), fill: Palette.beam))
        }
        beams.opacity = 0
        root.addSublayer(beams)

        let c = Self.bodyCentre
        let s = Self.bodySize
        shadow.addSublayer(Draw.shape(Draw.roundedRect(c.x + 5, c.y - 6, 44, s.height + 4, 14),
                                      fill: Ink.shadow))
        root.addSublayer(shadow)

        var silhouette = [Draw.roundedRect(c.x, c.y, s.width, s.height, 13),
                          Draw.roundedRect(0, -63, 44, 4.5, 2)]
        for w in Self.frontWheels + Self.rearWheels {
            silhouette.append(Draw.roundedRect(w.x, w.y, 10, 17, 3.5))
        }
        root.addSublayer(Draw.halo(silhouette))

        flames.forEach { root.addSublayer($0) }
        for p in Self.pipes {
            root.addSublayer(Draw.shape(Draw.ellipse(p.x, p.y + 1, 2.4, 2.4), fill: Palette.pipe,
                                        stroke: Ink.ink, width: 1.3))
        }
        (front + rear).forEach { root.addSublayer($0.layer) }

        root.addSublayer(body)
        body.addSublayer(Draw.outlined([Draw.roundedRect(c.x, c.y, s.width, s.height, 13)],
                                       fill: Palette.paint))
        for x in [CGFloat(-3.6), 3.6] {
            body.addSublayer(Draw.shape(Draw.roundedRect(x, c.y, 3.2, s.height - 4, 1),
                                        fill: Palette.stripe))
        }
        body.addSublayer(Draw.shape(Draw.polygon([
            CGPoint(x: -11.5, y: -19), CGPoint(x: 11.5, y: -19),
            CGPoint(x: 9.5, y: -29), CGPoint(x: -9.5, y: -29)
        ]), fill: Palette.glass, stroke: Ink.ink, width: 1.8))
        let shine = CGMutablePath()
        shine.move(to: CGPoint(x: -7, y: -21))
        shine.addLine(to: CGPoint(x: -3, y: -27))
        let shineLayer = Draw.shape(shine, fill: nil, stroke: Ink.halo, width: 1.4)
        shineLayer.opacity = 0.6
        body.addSublayer(shineLayer)
        body.addSublayer(Draw.shape(Draw.polygon([
            CGPoint(x: -9, y: -47), CGPoint(x: 9, y: -47),
            CGPoint(x: 10, y: -52), CGPoint(x: -10, y: -52)
        ]), fill: Palette.glass, stroke: Ink.ink, width: 1.6))

        // Roof roundel.
        body.addSublayer(Draw.shape(Draw.ellipse(0, -38, 6.2, 6.2), fill: Ink.halo,
                                    stroke: Ink.ink, width: 1.5))
        let number = CATextLayer()
        number.string = "7"
        number.font = NSFont.systemFont(ofSize: 9, weight: .black)
        number.fontSize = 9
        number.foregroundColor = Ink.ink
        number.alignmentMode = .center
        number.contentsScale = 6
        number.bounds = CGRect(x: 0, y: 0, width: 10, height: 11)
        number.position = CGPoint(x: 0, y: -38.6)
        body.addSublayer(number)

        for x in [CGFloat(-10), 10] {
            body.addSublayer(Draw.shape(Draw.ellipse(x, -6.5, 4, 2.4), fill: Palette.lamp,
                                        stroke: Ink.ink, width: 1.3))
            body.addSublayer(Draw.shape(Draw.roundedRect(x, -66, 7, 2.6, 1), fill: Palette.tailLamp,
                                        stroke: Ink.ink, width: 1))
        }
        // Spoiler, wider than the body, on two struts.
        for x in [CGFloat(-8), 8] {
            body.addSublayer(Draw.shape(Draw.roundedRect(x, -60.5, 2.2, 5, 0.8), fill: Ink.ink))
        }
        body.addSublayer(Draw.shape(Draw.roundedRect(0, -63, 44, 4.5, 2), fill: Ink.ink))
    }

    // MARK: - Reactions

    func react(to reaction: Reaction, motion: Motion, fx: Effects) {
        let now = motion.now
        let size = root.affineTransform().scaleMagnitude * 100
        let forward = Angle.forward(heading)
        switch reaction {
        case .leftClick:
            honkAt = now
            let wave = Draw.arc(radius: size * 0.08, spread: 1.7)
            // Waves leave right from the bumper and stay close to it.
            for speed in [0.9, 1.3, 1.7] as [CGFloat] {
                let start = CGPoint(x: motion.position.x + cos(forward) * size * 0.03,
                                    y: motion.position.y + sin(forward) * size * 0.03)
                fx.over.emit(wave, at: start, now: now, life: 0.34,
                             fill: nil, stroke: Ink.ink, width: max(1.3, size * 0.03),
                             velocity: CGVector(dx: cos(forward) * size * speed,
                                                dy: sin(forward) * size * speed),
                             drag: 4, rotation: forward, scale: (0.5, 1.4), alpha: (0.75, 0))
            }
        case .rightClick:
            driftAt = now
            // Spin the way the car is already turning, or alternate.
            driftSign = abs(turnRate) > 0.3 ? (turnRate > 0 ? 1 : -1) : -driftSign
        case .doubleClick:
            nitroAt = now
            Burst.impact(fx, at: motion.position, size: size, color: Ink.orange, now: now, count: 10)
        case .scroll:
            break
        }
    }

    // MARK: - Frame

    func update(_ motion: Motion, size: CGFloat, fx: Effects) {
        let now = motion.now
        let dt = motion.dt
        let scale = size / 100

        // Kinematics: the pointer tows the front bumper and the rear axle trails
        // behind at a fixed distance, like a bicycle or a trailer. Heading is just
        // the line from rear axle to bumper, so the car can only turn by driving
        // through an arc: the rear follows and cuts inside the curve, which is what
        // keeps the tracks smooth. Nothing ever spins the body directly.
        let tow = Self.towLength * scale
        let bumper = motion.position
        let previous = heading
        if let rear = rearAxle, hypot(bumper.x - rear.x, bumper.y - rear.y) < tow * 4 {
            if motion.speed > 5 {
                let dx = bumper.x - rear.x, dy = bumper.y - rear.y
                let length = hypot(dx, dy)
                if length > 0.001 {
                    rearAxle = CGPoint(x: bumper.x - dx / length * tow, y: bumper.y - dy / length * tow)
                    heading = atan2(dy, dx) - .pi / 2
                }
            } else if motion.idle > 1.0 {
                // Parked: swing back to the arrow pose. The tyres are lifted meanwhile.
                heading += Angle.delta(heading, restHeading) * min(1, dt * 3)
                rearAxle = point(behind: bumper, tow: tow)
            }
        } else {
            // First frame, or the pointer jumped (another display): re-seat the axle.
            rearAxle = point(behind: bumper, tow: tow)
        }
        let turn = Angle.delta(previous, heading) / max(dt, 0.001)
        turnRate += (turn - turnRate) * min(1, dt * 20)

        // Bicycle-model steering: the wheel angle that gives this turn at this speed.
        let targetSteer = motion.speed > 20 ? atan(Self.wheelbase * scale * turnRate / motion.speed) : 0
        steerAngle += (max(-0.55, min(0.55, targetSteer)) - steerAngle) * min(1, dt * 14)
        let steer = steerAngle

        // Revs from the scroll wheel, decaying.
        rev = min(1.5, rev + abs(motion.scroll) * 0.06)
        rev *= pow(0.08, dt)

        // Treads roll with distance travelled and spin with revs.
        roll += (motion.speed * dt / max(scale, 0.01)) * 0.6 + rev * 90 * dt
        front.forEach { $0.update(roll: roll, steer: steer) }
        rear.forEach { $0.update(roll: roll, steer: 0) }

        // Donut: one full turn about the front bumper, so the hotspot never moves.
        var yaw: CGFloat = 0
        let drift = Ease.progress(since: driftAt, over: 0.95, now: now)
        if let u = drift { yaw = 2 * .pi * Ease.inOutCubic(u) * driftSign }

        // Honk: two flashes and a bounce on the springs.
        var bounce: CGFloat = 0
        if let u = Ease.progress(since: honkAt, over: 0.42, now: now) {
            let flash = u < 0.5 ? sin(.pi * u / 0.5) : sin(.pi * (u - 0.5) / 0.5)
            beams.opacity = Float(flash * 0.7)
            bounce = sin(.pi * u)
        } else {
            beams.opacity = 0
        }
        body.setAffineTransform(CGAffineTransform(scaleX: 1 + 0.05 * bounce, y: 1 + 0.03 * bounce))

        // Nitro flames and shake.
        var shake: CGFloat = sin(CGFloat(now) * 55) * 0.005 + CGFloat.random(in: -1...1) * 0.012 * rev
        let nitro = Ease.progress(since: nitroAt, over: 0.8, now: now)
        if let u = nitro {
            let fade = u > 0.8 ? (1 - u) / 0.2 : 1
            for flame in flames {
                flame.opacity = Float(fade)
                let flicker = CGFloat.random(in: 0.75...1.35)
                flame.setAffineTransform(CGAffineTransform(scaleX: CGFloat.random(in: 0.85...1.1), y: flicker))
            }
            shake += CGFloat.random(in: -1...1) * 0.035
        } else {
            flames.forEach { $0.opacity = 0 }
        }

        shadow.setAffineTransform(CGAffineTransform(scaleX: 1 - 0.03 * bounce, y: 1 - 0.03 * bounce))
        root.setAffineTransform(CGAffineTransform(rotationAngle: heading + yaw + shake)
            .scaledBy(x: scale * (1 + 0.04 * bounce), y: scale * (1 + 0.04 * bounce)))

        // Everything below needs this frame's transform for body -> screen.
        let carAngle = heading + yaw
        let backward = Angle.forward(carAngle) + .pi

        // How hard the tyres are working, from the physics: sideways acceleration
        // in a turn (v times turn rate) and hard launches or stops along the car,
        // both in body units so it behaves the same at every size. Rises fast,
        // relaxes slowly, so marks darken into a corner and fade out of it.
        let previousSpeed = smoothSpeed
        smoothSpeed += (motion.speed - smoothSpeed) * min(1, dt * 10)
        let perBody = 1 / max(scale, 0.01)
        let lateral = abs(motion.speed * turnRate) * perBody
        let longitudinal = abs(smoothSpeed - previousSpeed) / max(dt, 0.001) * perBody
        // Measured on a test drive: gentle bends sit near 3000 and stay light,
        // a hairpin peaks near 9000, a hard stop near 10000.
        let corner = max(0, min(1, (lateral - 2500) / 6000))
        let launch = max(0, min(1, (longitudinal - 4000) / 7000))
        let slipTarget = max(corner, launch, nitro != nil ? 0.8 : 0, drift != nil ? 1 : 0)
        slip += (slipTarget - slip) * min(1, dt * (slipTarget > slip ? 20 : 4))

        layTracks(motion, size: size, angle: carAngle, drifting: drift != nil, fx: fx)

        if drift != nil, now - lastPuffAt > 0.035 {
            lastPuffAt = now
            for w in Self.rearWheels {
                let at = root.convert(w, to: fx.under.layer)
                Burst.puff(fx, at: at, size: size, now: now,
                           velocity: CGVector(dx: .random(in: -1...1) * size * 0.7,
                                              dy: .random(in: -1...1) * size * 0.7),
                           life: 0.75, alpha: 0.55, growth: 2.8)
            }
        }

        if nitro != nil {
            let lateral = CGFloat.random(in: -16...16)
            let at = root.convert(CGPoint(x: lateral, y: -74), to: fx.under.layer)
            fx.under.emit(Draw.dash(size * 0.28), at: at, now: now, life: 0.22,
                          fill: nil, stroke: Ink.ink, width: max(1.2, size * 0.022),
                          velocity: CGVector(dx: cos(backward) * size * 9, dy: sin(backward) * size * 9),
                          rotation: backward, alpha: (0.35, 0))
        }

        // Exhaust: on revs, and now and then at idle.
        let revving = abs(motion.scroll) > 0.3 && now - lastPuffAt > 0.07
        let idlePuff = motion.idle > 1.2 && now - lastPuffAt > 2.6
        if revving || idlePuff {
            lastPuffAt = now
            for p in Self.pipes {
                let at = root.convert(CGPoint(x: p.x, y: p.y - 3), to: fx.under.layer)
                Burst.puff(fx, at: at, size: size, now: now,
                           velocity: CGVector(dx: cos(backward) * size * 0.9, dy: sin(backward) * size * 0.9),
                           life: 0.7, alpha: revving ? 0.5 : 0.35, growth: 2)
            }
        }
    }

    private func point(behind bumper: CGPoint, tow: CGFloat) -> CGPoint {
        let forward = Angle.forward(heading)
        return CGPoint(x: bumper.x - cos(forward) * tow, y: bumper.y - sin(forward) * tow)
    }

    /// Chunky tread marks that follow each rear tyre continuously. Positions come
    /// from the physics pose, not the drawn one, so the honk bounce and nitro
    /// shake never wiggle the line. A donut — bumper fixed, tail swinging — draws
    /// its arcs because the tyres really move. Parking lifts the tyres.
    private func layTracks(_ motion: Motion, size: CGFloat, angle: CGFloat, drifting: Bool, fx: Effects) {
        let laying = motion.speed > 40 || drifting
        let scale = size / 100
        // Quantised so a chunk only splits when the darkness visibly changes.
        let alpha = ((0.28 + 0.4 * slip) * 25).rounded() / 25
        let width = size * 0.1 * (1 + 0.2 * slip)
        let c = cos(angle), n = sin(angle)
        for (id, wheel) in zip(trails, Self.rearWheels) {
            guard laying else {
                fx.ground.end(id)
                continue
            }
            let at = CGPoint(x: motion.position.x + (wheel.x * c - wheel.y * n) * scale,
                             y: motion.position.y + (wheel.x * n + wheel.y * c) * scale)
            fx.ground.extend(id, to: at, now: motion.now, width: width, alpha: alpha,
                             life: 3, maxStep: size * 1.5)
        }
    }
}
