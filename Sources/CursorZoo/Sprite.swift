import AppKit

/// Rasterises placeholder art. Everything here is swapped out the moment real
/// sprite sheets land; nothing else in the app knows what a glyph is.
enum Sprite {
    private static var cache: [String: CGImage] = [:]

    static func glyph(_ text: String, points: CGFloat) -> CGImage? {
        let key = "g:\(text):\(points)"
        if let hit = cache[key] { return hit }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: points)
        ]
        guard let image = draw(NSAttributedString(string: text, attributes: attrs),
                               padding: 6, background: nil) else { return nil }
        cache[key] = image
        return image
    }

    static func bubble(_ text: String, points: CGFloat) -> CGImage? {
        let key = "b:\(text):\(points)"
        if let hit = cache[key] { return hit }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: points, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        // Polymet orange, so the app reads as the same family as the playground.
        let fill = NSColor(srgbRed: 0.98, green: 0.33, blue: 0.09, alpha: 1.0)
        guard let image = draw(NSAttributedString(string: text, attributes: attrs),
                               padding: 9, background: fill) else { return nil }
        cache[key] = image
        return image
    }

    private static func draw(_ string: NSAttributedString,
                             padding: CGFloat,
                             background: NSColor?) -> CGImage? {
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
            let rect = CGRect(origin: .zero, size: size)
            let path = NSBezierPath(roundedRect: rect,
                                    xRadius: size.height / 2,
                                    yRadius: size.height / 2)
            background.setFill()
            path.fill()
        }
        string.draw(at: CGPoint(x: padding, y: padding))

        NSGraphicsContext.current = previous
        return ctx.makeImage()
    }
}
