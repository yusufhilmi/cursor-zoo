import AppKit

/// `CursorZoo --selftest out.png` renders every character mid-reaction through the
/// real `CharacterView`, so the drawing path can be checked without a screen
/// recording grant (and without a human watching the pointer).
enum SelfTest {
    static func run(outputPath: String) -> Int32 {
        let cell = CGSize(width: 240, height: 230)
        let sheet = CGSize(width: cell.width * CGFloat(Character.all.count), height: cell.height)

        guard let ctx = CGContext(data: nil,
                                  width: Int(sheet.width * 2),
                                  height: Int(sheet.height * 2),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            FileHandle.standardError.write(Data("selftest: could not allocate context\n".utf8))
            return 1
        }
        ctx.scaleBy(x: 2, y: 2)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: sheet))

        for (index, character) in Character.all.enumerated() {
            let view = CharacterView(frame: CGRect(origin: .zero, size: cell))
            view.configure(character: character, size: .large, replaceMode: false)

            let centre = CGPoint(x: cell.width / 2, y: cell.height / 2)
            // Fire the double-click reaction, then let it run a little so the frame
            // we capture is mid-hop with the bubble up, not at rest.
            view.update(state(at: centre, reaction: .doubleClick), origin: .zero, onThisScreen: true)
            Thread.sleep(forTimeInterval: 0.12)
            view.update(state(at: centre, reaction: nil), origin: .zero, onThisScreen: true)

            ctx.saveGState()
            ctx.translateBy(x: cell.width * CGFloat(index), y: 0)
            view.layer?.render(in: ctx)

            let label = NSAttributedString(string: character.name, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.black.withAlphaComponent(0.55)
            ])
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            label.draw(at: CGPoint(x: 14, y: 14))
            NSGraphicsContext.current = previous
            ctx.restoreGState()
        }

        guard let image = ctx.makeImage() else { return 1 }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }
        do {
            try data.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            FileHandle.standardError.write(Data("selftest: \(error)\n".utf8))
            return 1
        }

        // A blank sheet still writes a valid PNG, so assert something was drawn.
        let drawn = nonWhitePixelCount(image)
        print("selftest: wrote \(outputPath) (\(image.width)x\(image.height), \(drawn) painted pixels)")
        return drawn > 5000 ? 0 : 1
    }

    private static func state(at point: CGPoint, reaction: Reaction?) -> PointerState {
        PointerState(location: point,
                     velocity: CGVector(dx: 0, dy: 0),
                     leftDown: false,
                     rightDown: false,
                     scrollDelta: 0,
                     reaction: reaction,
                     dt: 1.0 / 60.0)
    }

    private static func nonWhitePixelCount(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let rowBytes = image.bytesPerRow
        var count = 0
        for y in stride(from: 0, to: image.height, by: 2) {
            for x in stride(from: 0, to: image.width, by: 2) {
                let p = y * rowBytes + x * 4
                if bytes[p] < 240 || bytes[p + 1] < 240 || bytes[p + 2] < 240 { count += 1 }
            }
        }
        return count
    }
}

extension SelfTest {
    /// `--mousetest out.png` renders the Tiny Mouse in a row of poses so the
    /// artwork can be eyeballed without hiding anyone's real cursor.
    static func renderMouse(outputPath: String) -> Int32 {
        let poses: [(String, MousePose)] = [
            ("rest",        MousePose()),
            ("left paw",    MousePose(leftPaw: 1, squash: 0.8)),
            ("right paw",   MousePose(rightPaw: 1, squash: 0.8)),
            ("hop",         MousePose(leftPaw: 0.5, rightPaw: 0.5, hop: 1, tailPhase: 1.6)),
            ("lean",        MousePose(lean: 0.4, tailPhase: 3.1))
        ]
        let cell = CGSize(width: 240, height: 250)
        let sheet = CGSize(width: cell.width * CGFloat(poses.count), height: cell.height)

        guard let ctx = CGContext(data: nil,
                                  width: Int(sheet.width * 3),
                                  height: Int(sheet.height * 3),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        ctx.scaleBy(x: 3, y: 3)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: sheet))

        for (index, entry) in poses.enumerated() {
            let container = CALayer()
            container.frame = CGRect(origin: .zero, size: cell)
            let node = TinyMouseNode()
            node.apply(entry.1, size: 150)
            // Put the nose where a pointer tip would be, and draw a crosshair on it
            // to confirm the hotspot really is pinned to the nose.
            let nose = CGPoint(x: cell.width / 2 + 28, y: cell.height - 42)
            node.root.position = nose
            container.addSublayer(node.root)

            ctx.saveGState()
            ctx.translateBy(x: cell.width * CGFloat(index), y: 0)
            container.render(in: ctx)

            ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: nose.x - 12, y: nose.y)); ctx.addLine(to: CGPoint(x: nose.x + 12, y: nose.y))
            ctx.move(to: CGPoint(x: nose.x, y: nose.y - 12)); ctx.addLine(to: CGPoint(x: nose.x, y: nose.y + 12))
            ctx.strokePath()

            let label = NSAttributedString(string: entry.0, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.black.withAlphaComponent(0.6)
            ])
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            label.draw(at: CGPoint(x: 14, y: 12))
            NSGraphicsContext.current = previous
            ctx.restoreGState()
        }

        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return 1 }
        try? data.write(to: URL(fileURLWithPath: outputPath))
        print("mousetest: wrote \(outputPath) (\(image.width)x\(image.height))")
        return 0
    }
}
