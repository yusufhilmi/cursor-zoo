import AppKit
import QuartzCore

/// A pool of short-lived shapes — tire tracks, smoke, sparks, flame, after-images —
/// that live in screen space rather than riding on the character.
///
/// Particles are recycled oldest-first, so a burst of activity can never grow the
/// layer tree without bound: the worst case is that old tracks fade early.
final class ParticleLane {
    let layer = CALayer()

    private final class Particle {
        let node = CAShapeLayer()
        var alive = false
        var born: CFTimeInterval = 0
        var life: CFTimeInterval = 1
        var position = CGPoint.zero
        var velocity = CGVector.zero
        var drag: CGFloat = 0
        var gravity = CGVector.zero
        var rotation: CGFloat = 0
        var spin: CGFloat = 0
        var scale: (CGFloat, CGFloat) = (1, 1)
        var alpha: (CGFloat, CGFloat) = (1, 0)
        var moves = false
    }

    private let pool: [Particle]
    private var cursor = 0

    init(capacity: Int) {
        pool = (0..<capacity).map { _ in
            let p = Particle()
            p.node.isHidden = true
            p.node.lineCap = .round
            p.node.lineJoin = .round
            return p
        }
        pool.forEach { layer.addSublayer($0.node) }
    }

    func emit(_ path: CGPath, at position: CGPoint, now: CFTimeInterval, life: CFTimeInterval,
              fill: CGColor?, stroke: CGColor? = nil, width: CGFloat = 0,
              velocity: CGVector = .zero, drag: CGFloat = 0, gravity: CGVector = .zero,
              rotation: CGFloat = 0, spin: CGFloat = 0,
              scale: (CGFloat, CGFloat) = (1, 1), alpha: (CGFloat, CGFloat) = (1, 0)) {
        let p = pool[cursor]
        cursor = (cursor + 1) % pool.count
        p.alive = true
        p.born = now
        p.life = life
        p.position = position
        p.velocity = velocity
        p.drag = drag
        p.gravity = gravity
        p.rotation = rotation
        p.spin = spin
        p.scale = scale
        p.alpha = alpha
        p.moves = velocity != .zero || gravity != .zero || spin != 0
        p.node.path = path
        p.node.fillColor = fill
        p.node.strokeColor = stroke
        p.node.lineWidth = width
        p.node.isHidden = false
        apply(p, t: 0)
    }

    func tick(now: CFTimeInterval, dt: CGFloat) {
        for p in pool where p.alive {
            let age = now - p.born
            guard age >= 0, age < p.life else {
                p.alive = false
                p.node.isHidden = true
                continue
            }
            if p.moves {
                p.velocity.dx += p.gravity.dx * dt
                p.velocity.dy += p.gravity.dy * dt
                let damp = max(0, 1 - p.drag * dt)
                p.velocity.dx *= damp
                p.velocity.dy *= damp
                p.position.x += p.velocity.dx * dt
                p.position.y += p.velocity.dy * dt
                p.rotation += p.spin * dt
            }
            apply(p, t: CGFloat(age / p.life))
        }
    }

    private func apply(_ p: Particle, t: CGFloat) {
        let s = p.scale.0 + (p.scale.1 - p.scale.0) * Ease.outCubic(t)
        p.node.position = p.position
        p.node.setAffineTransform(CGAffineTransform(rotationAngle: p.rotation).scaledBy(x: s, y: s))
        p.node.opacity = Float(p.alpha.0 + (p.alpha.1 - p.alpha.0) * t)
    }
}

/// Layers, bottom to top: `ground` for continuous tyre marks, `under` beneath the
/// character (prints, smoke, after-images) and `over` above it (impacts, fire,
/// shuriken).
final class Effects {
    let ground = TrackLayer()
    let under = ParticleLane(capacity: 900)
    let over = ParticleLane(capacity: 280)

    func tick(now: CFTimeInterval, dt: CGFloat) {
        ground.tick(now: now)
        under.tick(now: now, dt: dt)
        over.tick(now: now, dt: dt)
    }
}

/// Continuous tyre marks. Each wheel's trail is one stroked path that follows
/// exactly where the tyre went, smoothed with quadratic curves through segment
/// midpoints so it never shows a corner. The path is cut into short chunks that
/// fade on their own, oldest first; each chunk is a single stroke under one group
/// opacity, so nothing overlaps and double-darkens, and the tread dash pattern is
/// carried across chunk boundaries so it stays in phase.
final class TrackLayer {
    let layer = CALayer()

    private static let band = Ink.rgb(0.36, 0.34, 0.33)
    private static let tread = Ink.rgb(0.10, 0.09, 0.09)

    private final class Chunk {
        let group = CALayer()
        let band = CAShapeLayer()
        let tread = CAShapeLayer()
        let path = CGMutablePath()
        let alpha: CGFloat
        let life: CFTimeInterval
        let born: CFTimeInterval
        var lastAt: CFTimeInterval

        init(from start: CGPoint, now: CFTimeInterval, width: CGFloat, alpha: CGFloat,
             life: CFTimeInterval, dashPhase: CGFloat) {
            self.alpha = alpha
            self.life = life
            born = now
            lastAt = now
            path.move(to: start)
            for (shape, colour) in [(band, TrackLayer.band), (tread, TrackLayer.tread)] {
                shape.fillColor = nil
                shape.strokeColor = colour
                shape.lineWidth = width
                shape.lineJoin = .round
                shape.lineCap = .butt
                group.addSublayer(shape)
            }
            // Bars across the band, dashed along its length: reads as tread.
            let on = width * 0.3, off = width * 0.45
            tread.lineDashPattern = [NSNumber(value: Double(on)), NSNumber(value: Double(off))]
            tread.lineDashPhase = dashPhase.truncatingRemainder(dividingBy: on + off)
            group.allowsGroupOpacity = true
            group.opacity = Float(alpha)
        }

        func curve(to point: CGPoint, control: CGPoint, now: CFTimeInterval) {
            path.addQuadCurve(to: point, control: control)
            band.path = path
            tread.path = path
            lastAt = now
        }
    }

    private struct Trail {
        var chunk: Chunk
        /// Latest raw sample; the drawn path ends at the midpoint before it.
        var last: CGPoint
        var drawnEnd: CGPoint
        var distance: CGFloat
    }

    private var trails: [UUID: Trail] = [:]
    private var chunks: [Chunk] = []
    private let chunkSpan: CFTimeInterval = 0.25
    private let maxChunks = 240

    /// Continue trail `id` to `point`. A step longer than `maxStep` (a teleport,
    /// a screen change) starts a fresh trail instead of drawing a line across.
    func extend(_ id: UUID, to point: CGPoint, now: CFTimeInterval, width: CGFloat,
                alpha: CGFloat, life: CFTimeInterval, maxStep: CGFloat) {
        if var trail = trails[id] {
            let step = hypot(point.x - trail.last.x, point.y - trail.last.y)
            if step < 0.5 { return }
            if step <= maxStep {
                // A new chunk when this one is old enough to fade separately, when the
                // tyre paused (so a resumed trail does not revive faded ink), or when
                // the slip changed how dark it is. It starts exactly where the drawn
                // path ended, so there is no gap.
                let chunk = trail.chunk
                if now - chunk.born > chunkSpan || now - chunk.lastAt > 0.15 || chunk.alpha != alpha {
                    trail.chunk = makeChunk(from: trail.drawnEnd, now: now, width: width, alpha: alpha,
                                            life: life, dashPhase: trail.distance)
                }
                // Through the midpoint, with the raw sample as control: a smooth curve.
                let mid = CGPoint(x: (trail.last.x + point.x) / 2, y: (trail.last.y + point.y) / 2)
                trail.chunk.curve(to: mid, control: trail.last, now: now)
                trail.distance += hypot(mid.x - trail.drawnEnd.x, mid.y - trail.drawnEnd.y)
                trail.drawnEnd = mid
                trail.last = point
                trails[id] = trail
                return
            }
        }
        let chunk = makeChunk(from: point, now: now, width: width, alpha: alpha, life: life, dashPhase: 0)
        trails[id] = Trail(chunk: chunk, last: point, drawnEnd: point, distance: 0)
    }

    /// Lift the tyre: the next `extend` starts a new trail.
    func end(_ id: UUID) { trails[id] = nil }

    func tick(now: CFTimeInterval) {
        chunks.removeAll { chunk in
            let fade = 1 - (now - chunk.lastAt) / chunk.life
            if fade <= 0 {
                chunk.group.removeFromSuperlayer()
                return true
            }
            chunk.group.opacity = Float(chunk.alpha * CGFloat(fade))
            return false
        }
    }

    private func makeChunk(from start: CGPoint, now: CFTimeInterval, width: CGFloat,
                           alpha: CGFloat, life: CFTimeInterval, dashPhase: CGFloat) -> Chunk {
        let chunk = Chunk(from: start, now: now, width: width, alpha: alpha, life: life, dashPhase: dashPhase)
        chunks.append(chunk)
        layer.addSublayer(chunk.group)
        if chunks.count > maxChunks {
            chunks.removeFirst().group.removeFromSuperlayer()
        }
        return chunk
    }
}
