import AppKit

/// `CursorZoo --selftest sheet.png` plays a scripted timeline through the real
/// `CharacterView` for every character and renders a contact sheet: one row per
/// character, one column per interaction, a crosshair on the hotspot in every cell.
///
/// The clock is simulated, so the sheet is deterministic apart from particle
/// jitter, and nothing touches the real cursor. Exits non-zero on a blank render.
enum SelfTest {
    private static let cell = CGSize(width: 280, height: 250)
    private static let hotspot = CGPoint(x: 118, y: 150)
    private static let points: CGFloat = 62

    private struct Scenario {
        let name: String
        let play: (Driver) -> Void
    }

    private static let scenarios: [Scenario] = [
        Scenario(name: "idle") { $0.hold(0.6) },
        Scenario(name: "left click") { d in
            d.hold(0.4); d.press(.leftClick); d.hold(0.075)
        },
        Scenario(name: "right click") { d in
            d.hold(0.4); d.press(.rightClick); d.hold(0.09)
        },
        Scenario(name: "double click") { d in
            d.hold(0.4); d.press(.leftClick); d.hold(0.15); d.press(.doubleClick); d.hold(0.17)
        },
        Scenario(name: "scroll") { d in
            d.hold(0.3); d.scroll(frames: 14, delta: 6); d.hold(0.05)
        },
        Scenario(name: "move") { d in
            // A curve, not a straight line: trails have to hold together through turns.
            d.jump(to: CGPoint(x: hotspot.x - 95, y: hotspot.y - 95))
            d.hold(0.3)
            d.curve(through: CGPoint(x: hotspot.x + 150, y: hotspot.y - 120), to: hotspot, over: 0.42)
        }
    ]

    /// Steps a view through time at 120 Hz.
    private final class Driver {
        let view: CharacterView
        private(set) var location: CGPoint
        private var time: CFTimeInterval = 100
        private let dt: CFTimeInterval = 1.0 / 120

        init(view: CharacterView, at location: CGPoint) {
            self.view = view
            self.location = location
        }

        func hold(_ seconds: CFTimeInterval) {
            for _ in 0..<Int(seconds / dt) { step(to: location) }
        }

        func press(_ reaction: Reaction) { step(to: location, reaction: reaction) }

        func scroll(frames: Int, delta: CGFloat) {
            for _ in 0..<frames { step(to: location, reaction: .scroll, scroll: delta) }
        }

        func jump(to point: CGPoint) { location = point }

        func move(to target: CGPoint, over seconds: CFTimeInterval) {
            let start = location
            let steps = Int(seconds / dt)
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                step(to: CGPoint(x: start.x + (target.x - start.x) * t,
                                 y: start.y + (target.y - start.y) * t))
            }
        }

        /// A quadratic curve from the current location through `control` to `target`.
        func curve(through control: CGPoint, to target: CGPoint, over seconds: CFTimeInterval) {
            let start = location
            let steps = Int(seconds / dt)
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                step(to: Ease.bezier(start, control, target, t))
            }
        }

        private func step(to point: CGPoint, reaction: Reaction? = nil, scroll: CGFloat = 0) {
            let velocity = CGVector(dx: (point.x - location.x) / dt, dy: (point.y - location.y) / dt)
            location = point
            time += dt
            view.update(PointerState(location: point, velocity: velocity,
                                     leftDown: false, rightDown: false,
                                     scrollDelta: scroll, reaction: reaction,
                                     dt: dt, time: time),
                        origin: .zero, onThisScreen: true)
        }
    }

    static func run(outputPath: String) -> Int32 {
        let rows = Character.all
        let sheet = CGSize(width: cell.width * CGFloat(scenarios.count),
                           height: cell.height * CGFloat(rows.count))
        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(sheet.width * scale),
                                  height: Int(sheet.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(NSColor(white: 0.975, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: sheet))

        for (row, character) in rows.enumerated() {
            for (column, scenario) in scenarios.enumerated() {
                let view = CharacterView(frame: CGRect(origin: .zero, size: cell))
                view.configure(character: character, size: .medium, replaceMode: true, bubbles: false)
                view.sizeOverride = points
                scenario.play(Driver(view: view, at: hotspot))

                ctx.saveGState()
                ctx.translateBy(x: cell.width * CGFloat(column),
                                y: sheet.height - cell.height * CGFloat(row + 1))
                ctx.setStrokeColor(NSColor(white: 0.88, alpha: 1).cgColor)
                ctx.stroke(CGRect(origin: .zero, size: cell).insetBy(dx: 0.5, dy: 0.5))
                view.layer?.render(in: ctx)
                crosshair(ctx, at: hotspot)
                label(ctx, "\(character.name) · \(scenario.name)")
                ctx.restoreGState()
            }
        }

        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return 1 }
        do { try data.write(to: URL(fileURLWithPath: outputPath)) } catch {
            FileHandle.standardError.write(Data("selftest: \(error)\n".utf8))
            return 1
        }
        let painted = paintedPixels(image)
        print("selftest: wrote \(outputPath) (\(image.width)x\(image.height), \(painted) painted samples)")
        return painted > 5000 * rows.count ? 0 : 1
    }

    /// `CursorZoo --trackstest out.png`: one long drive with the racer — an S-bend,
    /// a hairpin, a fast run into a hard stop, then a donut — so the tyre marks can
    /// be judged as a whole: smooth through turns, cutting inside curves, darker
    /// where the tyres would slip.
    static func runTracks(outputPath: String) -> Int32 {
        let size = CGSize(width: 980, height: 560)
        let view = CharacterView(frame: CGRect(origin: .zero, size: size))
        view.configure(character: .lilRacer, size: .medium, replaceMode: true, bubbles: false)
        view.sizeOverride = 56
        let d = Driver(view: view, at: CGPoint(x: 90, y: 140))
        d.hold(0.3)
        d.curve(through: CGPoint(x: 300, y: 520), to: CGPoint(x: 520, y: 280), over: 0.75)
        d.curve(through: CGPoint(x: 760, y: 40), to: CGPoint(x: 860, y: 320), over: 0.55)
        d.curve(through: CGPoint(x: 900, y: 520), to: CGPoint(x: 640, y: 450), over: 0.4)
        d.move(to: CGPoint(x: 420, y: 430), over: 0.16)
        d.hold(0.2)
        d.press(.rightClick)
        d.hold(0.9)

        guard let ctx = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        ctx.scaleBy(x: 2, y: 2)
        ctx.setFillColor(NSColor(white: 0.975, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        view.layer?.render(in: ctx)
        crosshair(ctx, at: d.location)
        label(ctx, "Lil Racer · S-bend, hairpin, hard stop, donut")
        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return 1 }
        do { try data.write(to: URL(fileURLWithPath: outputPath)) } catch { return 1 }
        print("trackstest: wrote \(outputPath)")
        return 0
    }

    private static func crosshair(_ ctx: CGContext, at p: CGPoint) {
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: p.x - 10, y: p.y)); ctx.addLine(to: CGPoint(x: p.x + 10, y: p.y))
        ctx.move(to: CGPoint(x: p.x, y: p.y - 10)); ctx.addLine(to: CGPoint(x: p.x, y: p.y + 10))
        ctx.strokePath()
    }

    private static func label(_ ctx: CGContext, _ text: String) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.black.withAlphaComponent(0.55)
        ])
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        string.draw(at: CGPoint(x: 10, y: 9))
        NSGraphicsContext.current = previous
    }

    private static func paintedPixels(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        var count = 0
        for y in stride(from: 0, to: image.height, by: 2) {
            for x in stride(from: 0, to: image.width, by: 2) {
                let p = y * image.bytesPerRow + x * 4
                if bytes[p] < 200 || bytes[p + 1] < 200 || bytes[p + 2] < 200 { count += 1 }
            }
        }
        return count
    }
}
