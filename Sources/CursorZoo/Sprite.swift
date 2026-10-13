import AppKit

/// Rasterises the speech bubbles. Characters themselves are vector rigs.
enum Sprite {
    private static var cache: [String: CGImage] = [:]

    /// Two voices, straight from the playground: a quiet white pill for ordinary
    /// clicks and a loud Polymet-orange one for the big moments.
    enum BubbleStyle { case soft, loud }

    static func bubble(_ text: String, points: CGFloat, style: BubbleStyle) -> CGImage? {
        let key = "b:\(text):\(points):\(style)"
        if let hit = cache[key] { return hit }
        let orange = NSColor(srgbRed: 0.98, green: 0.33, blue: 0.09, alpha: 1.0)
        let ink = NSColor(srgbRed: 0.16, green: 0.14, blue: 0.13, alpha: 1.0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: points, weight: .bold),
            .foregroundColor: style == .loud ? NSColor.white : ink
        ]
        let fill = style == .loud ? orange : NSColor.white
        let edge = style == .loud ? nil : NSColor(white: 0.82, alpha: 1)
        guard let image = draw(NSAttributedString(string: text, attributes: attrs),
                               padding: 9, background: fill, edge: edge) else { return nil }
        cache[key] = image
        return image
    }

    private static func draw(_ string: NSAttributedString,
                             padding: CGFloat,
                             background: NSColor?,
                             edge: NSColor?) -> CGImage? {
        let measured = string.boundingRect(
            with: CGSize(width: 2000, height: 2000),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = CGSize(width: ceil(measured.width) + padding * 2,
                          height: ceil(measured.height) + padding * 2)
        let scale: CGFloat = 3
        guard size.width > 0, size.height > 0,
              let ctx = CGContext(data: nil,
                                  width: Int(size.width * scale),
                                  height: Int(size.height * scale),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        if let background {
            let inset: CGFloat = edge == nil ? 0 : 0.75
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let path = NSBezierPath(roundedRect: rect,
                                    xRadius: rect.height / 2,
                                    yRadius: rect.height / 2)
            background.setFill()
            path.fill()
            if let edge {
                edge.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
        string.draw(at: CGPoint(x: padding, y: padding))

        NSGraphicsContext.current = previous
        return ctx.makeImage()
    }
}
