import AppKit
import QuartzCore

/// How the mouse is posed on a given frame. Every value is 0...1 progress.
struct MousePose {
    var leftPaw: CGFloat = 0
    var rightPaw: CGFloat = 0
    var squash: CGFloat = 0
    var hop: CGFloat = 0
    var lean: CGFloat = 0
    var tailPhase: CGFloat = 0
}

/// The Tiny Mouse, assembled from shape layers so each paw can swing on its own.
///
/// Everything is laid out in "body space": **the nose is the origin**, the body
/// hangs below it in -y, and one unit is one hundredth of the sprite's height.
/// Because the root layer's anchor point sits on the nose, rotating or scaling the
/// mouse pivots around the nose — so the hotspot stays nailed to the pointer no
/// matter what the animation does.
final class TinyMouseNode {
    let root = CALayer()

    private let leftPawPivot = CALayer()
    private let rightPawPivot = CALayer()
    private let tail = CAShapeLayer()
    private let body = CALayer()

    private enum Palette {
        static let fur = NSColor(srgbRed: 0.64, green: 0.60, blue: 0.57, alpha: 1).cgColor
        static let furLight = NSColor(srgbRed: 0.76, green: 0.73, blue: 0.70, alpha: 1).cgColor
        static let ink = NSColor(srgbRed: 0.24, green: 0.22, blue: 0.21, alpha: 1).cgColor
        static let pink = NSColor(srgbRed: 0.93, green: 0.58, blue: 0.66, alpha: 1).cgColor
        static let pinkDark = NSColor(srgbRed: 0.85, green: 0.44, blue: 0.54, alpha: 1).cgColor
        static let halo = NSColor.white.cgColor
    }

    /// Body-space bounds. Generous enough that ears and tail never clip.
    private static let space = CGRect(x: -64, y: -118, width: 140, height: 150)

    init() {
        root.bounds = Self.space
        // Anchor exactly on the nose at body-space (0, 0).
        root.anchorPoint = CGPoint(x: -Self.space.minX / Self.space.width,
                                   y: -Self.space.minY / Self.space.height)
        root.allowsEdgeAntialiasing = true

        build()
    }

    // MARK: - Construction

    /// Head and snout are one teardrop so there is no seam across the face, and so
    /// the path genuinely tapers to a point at the origin — that point is the
    /// pointer tip.
    private func headPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: -14, y: -22),
                      control1: CGPoint(x: -4, y: -6), control2: CGPoint(x: -12, y: -12))
        path.addCurve(to: CGPoint(x: 0, y: -36),
                      control1: CGPoint(x: -16, y: -31), control2: CGPoint(x: -9, y: -36))
        path.addCurve(to: CGPoint(x: 14, y: -22),
                      control1: CGPoint(x: 9, y: -36), control2: CGPoint(x: 16, y: -31))
        path.addCurve(to: CGPoint(x: 0, y: 0),
                      control1: CGPoint(x: 12, y: -12), control2: CGPoint(x: 4, y: -6))
        path.closeSubpath()
        return path
    }

    private func bodyPath() -> CGPath {
        ellipse(3, -58, 23, 30, rotation: .pi / 18)
    }

    private func build() {
        // White sticker halo behind the silhouette, so the mouse stays readable on
        // dark windows and busy backgrounds.
        let halo = CAShapeLayer()
        let silhouette = CGMutablePath()
        silhouette.addPath(headPath())
        silhouette.addPath(bodyPath())
        silhouette.addPath(ellipse(-15, -27, 11, 11))
        silhouette.addPath(ellipse(15, -27, 11, 11))
        halo.path = silhouette
        halo.fillColor = Palette.halo
        halo.strokeColor = Palette.halo
        halo.lineWidth = 10
        halo.lineJoin = .round
        root.addSublayer(halo)

        root.addSublayer(tailLayer())

        // Ears go behind the head so only the top arc shows, the way real ears read.
        root.addSublayer(earLayer(centre: CGPoint(x: -15, y: -27), radius: 11))
        root.addSublayer(earLayer(centre: CGPoint(x: 15, y: -27), radius: 11))

        root.addSublayer(body)
        body.addSublayer(shape(bodyPath(), fill: Palette.fur, stroke: Palette.ink, width: 4.5))
        // Lighter belly, the highlight the reference art has down its front.
        body.addSublayer(shape(ellipse(-2, -60, 10, 20, rotation: .pi / 16),
                               fill: Palette.furLight, stroke: nil, width: 0))

        body.addSublayer(footLayer(centre: CGPoint(x: -14, y: -80), rotation: -0.45))
        body.addSublayer(footLayer(centre: CGPoint(x: 23, y: -77), rotation: 0.35))

        root.addSublayer(limb(shoulder: CGPoint(x: -15, y: -44),
                              paw: CGPoint(x: -27, y: -52),
                              container: leftPawPivot))
        root.addSublayer(limb(shoulder: CGPoint(x: 21, y: -44),
                              paw: CGPoint(x: 33, y: -50),
                              container: rightPawPivot))

        root.addSublayer(shape(headPath(), fill: Palette.fur, stroke: Palette.ink, width: 4.5))
        root.addSublayer(shape(ellipse(-6.5, -21, 3.1, 3.1), fill: Palette.ink, stroke: nil, width: 0))
        root.addSublayer(shape(ellipse(6.5, -21, 2.7, 2.7), fill: Palette.ink, stroke: nil, width: 0))
        root.addSublayer(shape(ellipse(0, -5, 3.6, 3.1), fill: Palette.pinkDark,
                               stroke: Palette.ink, width: 1.8))
        root.addSublayer(whiskers())
    }

    private func tailLayer() -> CAShapeLayer {
        tail.fillColor = nil
        tail.strokeColor = Palette.pink
        tail.lineWidth = 5
        tail.lineCap = .round
        tail.path = tailPath(phase: 0)
        return tail
    }

    private func tailPath(phase: CGFloat) -> CGPath {
        let wag = sin(phase) * 4
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 14, y: -84))
        path.addCurve(to: CGPoint(x: 46, y: -96 + wag),
                      control1: CGPoint(x: 28, y: -98),
                      control2: CGPoint(x: 44, y: -82 + wag))
        path.addCurve(to: CGPoint(x: 31, y: -80 - wag),
                      control1: CGPoint(x: 48, y: -108 + wag),
                      control2: CGPoint(x: 27, y: -100))
        return path
    }

    private func earLayer(centre: CGPoint, radius: CGFloat) -> CALayer {
        let ear = CALayer()
        ear.addSublayer(shape(ellipse(centre.x, centre.y, radius, radius),
                              fill: Palette.fur, stroke: Palette.ink, width: 4))
        ear.addSublayer(shape(ellipse(centre.x, centre.y + radius * 0.1, radius * 0.5, radius * 0.5),
                              fill: Palette.pink, stroke: nil, width: 0))
        return ear
    }

    private func footLayer(centre: CGPoint, rotation: CGFloat) -> CAShapeLayer {
        shape(ellipse(centre.x, centre.y, 8, 5.5, rotation: rotation),
              fill: Palette.pink, stroke: Palette.ink, width: 3)
    }

    /// A front leg. The container's anchor sits on the shoulder, so rotating the
    /// container swings the whole arm down into a slap. The arm is two round-capped
    /// strokes — a fat ink one under a fur one — which fakes an outlined capsule.
    private func limb(shoulder: CGPoint, paw: CGPoint, container: CALayer) -> CALayer {
        let reach: CGFloat = 40
        container.bounds = CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        container.position = shoulder

        // Paths inside the container are relative to the shoulder.
        let local = CGPoint(x: paw.x - shoulder.x, y: paw.y - shoulder.y)
        let armPath = CGMutablePath()
        armPath.move(to: .zero)
        armPath.addLine(to: local)

        for (colour, width) in [(Palette.ink, CGFloat(13)), (Palette.fur, CGFloat(7))] {
            let arm = CAShapeLayer()
            arm.path = armPath
            arm.strokeColor = colour
            arm.lineWidth = width
            arm.lineCap = .round
            arm.fillColor = nil
            container.addSublayer(arm)
        }

        container.addSublayer(shape(ellipse(local.x, local.y, 6.5, 7),
                                    fill: Palette.pink, stroke: Palette.ink, width: 3))
        return container
    }

    /// Whiskers splay sideways from the snout, not forward — forward reads as antennae.
    private func whiskers() -> CAShapeLayer {
        let path = CGMutablePath()
        for (dx, dy) in [(-1.0, 0.1), (-1.0, -0.45), (1.0, 0.1), (1.0, -0.45)] as [(CGFloat, CGFloat)] {
            path.move(to: CGPoint(x: dx * 6, y: -11))
            path.addLine(to: CGPoint(x: dx * 18, y: -11 + dy * 13))
        }
        let layer = CAShapeLayer()
        layer.path = path
        layer.strokeColor = Palette.ink
        layer.lineWidth = 1.5
        layer.lineCap = .round
        layer.opacity = 0.5
        return layer
    }

    // MARK: - Posing

    func apply(_ pose: MousePose, size: CGFloat) {
        let scale = size / 100

        tail.path = tailPath(phase: pose.tailPhase)

        // A slap swings the arm forward about the shoulder, towards the nose.
        let lift = pose.hop * 0.5
        leftPawPivot.setAffineTransform(
            CGAffineTransform(rotationAngle: -(pose.leftPaw + lift) * 0.8))
        rightPawPivot.setAffineTransform(
            CGAffineTransform(rotationAngle: (pose.rightPaw + lift) * 0.8))

        // Squash flattens the body only; the head keeps its shape so it stays cute.
        let squash = 1 - pose.squash * 0.18
        body.setAffineTransform(CGAffineTransform(scaleX: 1 + pose.squash * 0.2, y: squash))

        // The hop is a pulse and a wobble, never a translation: this sprite IS the
        // cursor, so the nose has to stay welded to the pointer tip.
        let pulse = 1 + sin(.pi * pose.hop) * 0.12
        let wobble = sin(.pi * 2 * pose.hop) * 0.22

        // Rest angle matches the reference art: nose up-left, body trailing down-right.
        var transform = CGAffineTransform(rotationAngle: -0.58 + pose.lean + wobble)
        transform = transform.scaledBy(x: scale * pulse, y: scale * pulse)
        root.setAffineTransform(transform)
    }

    // MARK: - Shape helpers

    private func ellipse(_ cx: CGFloat, _ cy: CGFloat,
                         _ rx: CGFloat, _ ry: CGFloat,
                         rotation: CGFloat = 0) -> CGPath {
        var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: rotation)
        return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2),
                      transform: &t)
    }

    private func shape(_ path: CGPath, fill: CGColor?, stroke: CGColor?, width: CGFloat) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = fill
        layer.strokeColor = stroke
        layer.lineWidth = width
        layer.lineJoin = .round
        return layer
    }
}
