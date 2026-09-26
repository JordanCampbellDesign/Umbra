import AppKit

// Draws the Umbra icon: a sun partly covered by a moon shadow.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ s: Int) -> Data {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let f = CGFloat(s)
    let r = CGRect(x: 0, y: 0, width: f, height: f)
    let bg = NSBezierPath(roundedRect: r.insetBy(dx: f * 0.1, dy: f * 0.1), xRadius: f * 0.18, yRadius: f * 0.18)
    NSGradient(colors: [NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.26, alpha: 1),
                        NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.07, alpha: 1)])!.draw(in: bg, angle: -90)
    let c = CGPoint(x: f / 2, y: f / 2)
    let rad = f * 0.2
    NSColor(calibratedRed: 1, green: 0.78, blue: 0.25, alpha: 1).setStroke()
    for i in 0 ..< 12 {
        let a = CGFloat(i) * .pi / 6
        let p = NSBezierPath()
        p.lineWidth = f * 0.035
        p.lineCapStyle = .round
        p.move(to: CGPoint(x: c.x + cos(a) * rad * 1.35, y: c.y + sin(a) * rad * 1.35))
        p.line(to: CGPoint(x: c.x + cos(a) * rad * 1.7, y: c.y + sin(a) * rad * 1.7))
        p.stroke()
    }
    NSGradient(colors: [NSColor(calibratedRed: 1, green: 0.88, blue: 0.4, alpha: 1),
                        NSColor(calibratedRed: 1, green: 0.6, blue: 0.15, alpha: 1)])!
        .draw(in: NSBezierPath(ovalIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)), angle: -60)
    NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: c.x - rad * 0.45, y: c.y - rad * 0.55, width: rad * 1.9, height: rad * 1.9)).fill()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
