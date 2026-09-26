// Draws the DMG window background at 1x and 2x: scripts/dmg/make-background.swift <out-dir>
import AppKit

let size = CGSize(width: 660, height: 420)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // AppKit draws bottom-up; `top(_:_:)` converts a top-down y so the layout reads like the Finder window.
    func top(_ y: CGFloat, _ h: CGFloat = 0) -> CGFloat { size.height - y - h }

    // Neutral light canvas, like a Finder window.
    NSColor(srgbRed: 0.965, green: 0.965, blue: 0.97, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()

    func text(_ s: String, _ font: NSFont, _ color: NSColor, y: CGFloat) {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        NSAttributedString(string: s, attributes: a).draw(in: NSRect(x: 0, y: top(y, 30), width: size.width, height: 30))
    }

    text("Drag Umbra to Applications", .systemFont(ofSize: 20, weight: .semibold), NSColor(white: 0.1, alpha: 1), y: 44)
    text("Then open it from Applications or Spotlight.", .systemFont(ofSize: 13), NSColor(white: 0.42, alpha: 1), y: 74)

    // Arrow between the app icon (x 180) and Applications (x 480), both centered at y 215.
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 272, y: 205))
    arrow.line(to: CGPoint(x: 388, y: 205))
    arrow.move(to: CGPoint(x: 376, y: 195))
    arrow.line(to: CGPoint(x: 390, y: 205))
    arrow.line(to: CGPoint(x: 376, y: 215))
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(white: 0.62, alpha: 1).setStroke()
    arrow.stroke()

    // First-launch hint for downloads that aren't notarized.
    let hint = NSRect(x: 150, y: top(350, 34), width: 360, height: 34)
    NSColor(white: 0, alpha: 0.045).setFill()
    NSBezierPath(roundedRect: hint, xRadius: 17, yRadius: 17).fill()
    text("First time: right-click Umbra in Applications and choose Open.", .systemFont(ofSize: 11.5), NSColor(white: 0.38, alpha: 1), y: 359)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    let data = draw(scale: scale).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}
print("wrote \(out)/background.png and background@2x.png")
