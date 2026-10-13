import AppKit
import QuartzCore

/// Everything a rig needs to know about the pointer on one frame, already in the
/// overlay view's coordinate space.
struct Motion {
    /// The hotspot. The view has already put the rig's root here.
    var position: CGPoint
    /// Smoothed, points per second.
    var velocity: CGVector
    var speed: CGFloat
    var dt: CGFloat
    var now: CFTimeInterval
    /// Seconds since the pointer last moved or clicked.
    var idle: CFTimeInterval
    /// This frame's wheel delta.
    var scroll: CGFloat
}

/// One character. Every rig speaks the same six-slot vocabulary — idle, move,
/// left click, right click, double click, scroll — and fills every slot.
///
/// The contract that keeps it usable as a real cursor: `root` is anchored on the
/// hotspot and the view positions it. A rig may rotate and scale `root` freely
/// (both pivot on the hotspot) but must never translate it.
protocol CharacterRig: AnyObject {
    var root: CALayer { get }
    func react(to reaction: Reaction, motion: Motion, fx: Effects)
    func update(_ motion: Motion, size: CGFloat, fx: Effects)
}

/// The default pose, shared by every character: pointing up and to the left like
/// the system arrow, body trailing down and to the right. In y-up layer space a
/// body drawn facing +y needs a positive (counter-clockwise) turn to get there.
let restHeading: CGFloat = 0.6

// MARK: - Palette

enum Ink {
    static let line: CGFloat = 3
    static let ink = rgb(0.24, 0.21, 0.20)
    static let halo = NSColor.white.cgColor
    static let shadow = rgb(0, 0, 0, 0.13)
    static let orange = rgb(0.98, 0.33, 0.09)
    static let impact = rgb(0.42, 0.39, 0.37)
    static let smoke = rgb(0.78, 0.77, 0.76)

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
    }
}

// MARK: - Drawing

enum Draw {
    /// A root layer whose coordinate system is body space and whose anchor point
    /// is body-space (0, 0) — the hotspot.
    static func root(space: CGRect) -> CALayer {
        let layer = CALayer()
        layer.bounds = space
        layer.anchorPoint = CGPoint(x: -space.minX / space.width, y: -space.minY / space.height)
        layer.allowsEdgeAntialiasing = true
        return layer
    }

    /// A container whose children draw in body coordinates and whose transforms
    /// pivot on `pivot`.
    static func group(pivot: CGPoint = .zero) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: pivot, size: .zero)
        layer.position = pivot
        return layer
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat,
                        rotation: CGFloat = 0) -> CGPath {
        var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: rotation)
        return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: &t)
    }

    static func roundedRect(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat,
                            _ r: CGFloat, rotation: CGFloat = 0) -> CGPath {
        var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: rotation)
        let radius = min(r, w / 2, h / 2)
        return CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                      cornerWidth: radius, cornerHeight: radius, transform: &t)
    }

    static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// An n-pointed star centred on the origin.
    static func star(points: Int, outer: CGFloat, inner: CGFloat) -> CGPath {
        var vertices: [CGPoint] = []
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = CGFloat(i) * .pi / CGFloat(points) + .pi / 2
            vertices.append(CGPoint(x: cos(a) * r, y: sin(a) * r))
        }
        return polygon(vertices)
    }

    /// A line from the origin along +x.
    static func dash(_ length: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: length, y: 0))
        return path
    }

    /// An arc opening along +x, like a ")" — sound waves, wind.
    static func arc(radius: CGFloat, spread: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: radius, startAngle: -spread / 2, endAngle: spread / 2,
                    clockwise: false)
        return path
    }

    static func heart(_ s: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -s * 0.9))
        path.addCurve(to: CGPoint(x: -s, y: s * 0.15),
                      control1: CGPoint(x: -s * 0.55, y: -s * 0.45), control2: CGPoint(x: -s, y: -s * 0.3))
        path.addCurve(to: CGPoint(x: 0, y: s * 0.35),
                      control1: CGPoint(x: -s, y: s * 0.8), control2: CGPoint(x: -s * 0.15, y: s * 0.75))
        path.addCurve(to: CGPoint(x: s, y: s * 0.15),
                      control1: CGPoint(x: s * 0.15, y: s * 0.75), control2: CGPoint(x: s, y: s * 0.8))
        path.addCurve(to: CGPoint(x: 0, y: -s * 0.9),
                      control1: CGPoint(x: s, y: -s * 0.3), control2: CGPoint(x: s * 0.55, y: -s * 0.45))
        path.closeSubpath()
        return path
    }

    static func shape(_ path: CGPath?, fill: CGColor?, stroke: CGColor? = nil,
                      width: CGFloat = 0) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = fill
        layer.strokeColor = stroke
        layer.lineWidth = width
        layer.lineJoin = .round
        layer.lineCap = .round
        return layer
    }

    /// Several overlapping paths drawn as one outlined region: a fat ink stroke
    /// under a fill, so the seams where parts overlap disappear.
    static func outlined(_ paths: [CGPath], fill: CGColor, width: CGFloat = Ink.line) -> CALayer {
        let group = CALayer()
        let combined = CGMutablePath()
        paths.forEach { combined.addPath($0) }
        group.addSublayer(shape(combined, fill: nil, stroke: Ink.ink, width: width * 2))
        group.addSublayer(shape(combined, fill: fill))
        return group
    }

    /// The white sticker edge around a silhouette.
    static func halo(_ paths: [CGPath], width: CGFloat = 7) -> CAShapeLayer {
        let combined = CGMutablePath()
        paths.forEach { combined.addPath($0) }
        return shape(combined, fill: Ink.halo, stroke: Ink.halo, width: width)
    }
}

// MARK: - Limb

/// An arm that reaches from a fixed shoulder to a moving hand: an ink stroke
/// under a coloured one, so it reads as an outlined capsule at any length, plus a
/// round hand on the end and two after-images for motion blur.
final class Limb {
    let shoulder: CGPoint
    private let armInk = Draw.shape(nil, fill: nil, stroke: Ink.ink, width: 0)
    private let armFill = Draw.shape(nil, fill: nil, stroke: nil, width: 0)
    private let ghosts: [CAShapeLayer]
    private let hand: CALayer

    init(shoulder: CGPoint, thickness: CGFloat, armColor: CGColor,
         hand: CALayer, ghostPath: CGPath, ghostColor: CGColor) {
        self.shoulder = shoulder
        self.hand = hand
        armInk.lineWidth = thickness + Ink.line * 2
        armFill.lineWidth = thickness
        armFill.strokeColor = armColor
        ghosts = (0..<2).map { _ in
            let g = Draw.shape(ghostPath, fill: ghostColor)
            g.opacity = 0
            return g
        }
    }

    func install(in parent: CALayer) {
        ghosts.forEach { parent.addSublayer($0) }
        parent.addSublayer(armInk)
        parent.addSublayer(armFill)
        parent.addSublayer(hand)
    }

    /// `trail` are earlier positions along the strike, newest first.
    func place(hand point: CGPoint, scale: CGFloat, trail: [CGPoint], trailAlpha: CGFloat) {
        let path = CGMutablePath()
        path.move(to: shoulder)
        path.addLine(to: point)
        armInk.path = path
        armFill.path = path
        hand.position = point
        hand.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        for (i, ghost) in ghosts.enumerated() {
            if i < trail.count && trailAlpha > 0 {
                ghost.position = trail[i]
                ghost.opacity = Float(trailAlpha * (i == 0 ? 0.45 : 0.22))
            } else {
                ghost.opacity = 0
            }
        }
    }
}

// MARK: - Timing

enum Ease {
    static func outCubic(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }

    static func inOutCubic(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// 0...1 progress through an animation started at `start`, or nil when it is
    /// not running.
    static func progress(since start: CFTimeInterval, over duration: CFTimeInterval,
                         now: CFTimeInterval) -> CGFloat? {
        guard start > 0 else { return nil }
        let elapsed = now - start
        guard elapsed >= 0, elapsed < duration else { return nil }
        return CGFloat(elapsed / duration)
    }

    /// A hit: out fast, hold on the target, ease home.
    static func strike(_ u: CGFloat) -> CGFloat {
        if u < 0.28 { return outCubic(u / 0.28) }
        if u < 0.45 { return 1 }
        return 1 - inOutCubic((u - 0.45) / 0.55)
    }

    static func bezier(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let m = 1 - t
        return CGPoint(x: m * m * a.x + 2 * m * t * c.x + t * t * b.x,
                       y: m * m * a.y + 2 * m * t * c.y + t * t * b.y)
    }
}

/// Random blinks, two to five seconds apart.
struct Blinker {
    private var next: CFTimeInterval = 0
    private var started: CFTimeInterval = -1

    /// 1 = open, ~0.1 = shut.
    mutating func openness(at now: CFTimeInterval) -> CGFloat {
        if next == 0 { next = now + .random(in: 1.5...3) }
        if now >= next {
            started = now
            next = now + .random(in: 2...5)
        }
        guard let t = Ease.progress(since: started, over: 0.14, now: now) else { return 1 }
        return 1 - 0.9 * sin(.pi * t)
    }
}

/// Angle helpers.
enum Angle {
    /// Signed shortest turn from `a` to `b`.
    static func delta(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var d = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }

    /// The heading a body drawn facing +y needs to face along `v`.
    static func heading(of v: CGVector) -> CGFloat { atan2(v.dy, v.dx) - .pi / 2 }

    /// The direction a body drawn facing +y faces after turning by `heading`.
    static func forward(_ heading: CGFloat) -> CGFloat { heading + .pi / 2 }
}

/// Little reusable effects every character draws on.
enum Burst {
    /// A tight ring of ticks around the click point: "I hit exactly here". Starts
    /// almost on the point and travels a few points, so it never reads as
    /// happening somewhere else.
    static func impact(_ fx: Effects, at point: CGPoint, size: CGFloat,
                       color: CGColor, now: CFTimeInterval, count: Int = 8) {
        let path = Draw.dash(size * 0.09)
        for i in 0..<count {
            let a = (CGFloat(i) + 0.5) / CGFloat(count) * 2 * .pi
            let start = CGPoint(x: point.x + cos(a) * size * 0.04, y: point.y + sin(a) * size * 0.04)
            fx.over.emit(path, at: start, now: now, life: 0.22,
                         fill: nil, stroke: color, width: max(1.4, size * 0.03),
                         velocity: CGVector(dx: cos(a) * size * 1.3, dy: sin(a) * size * 1.3),
                         drag: 9, rotation: a, scale: (1, 0.5), alpha: (0.95, 0))
        }
    }

    static func puff(_ fx: Effects, at point: CGPoint, size: CGFloat, now: CFTimeInterval,
                     velocity: CGVector = .zero, color: CGColor = Ink.smoke,
                     life: CFTimeInterval = 0.6, alpha: CGFloat = 0.5, growth: CGFloat = 2.2,
                     above: Bool = false) {
        let lane = above ? fx.over : fx.under
        lane.emit(Draw.ellipse(0, 0, size * 0.06, size * 0.06), at: point, now: now, life: life,
                  fill: color, velocity: velocity, drag: 3,
                  gravity: CGVector(dx: 0, dy: size * 0.5),
                  scale: (0.6, growth), alpha: (alpha, 0))
    }
}
