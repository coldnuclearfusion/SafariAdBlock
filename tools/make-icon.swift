// tools/make-icon.swift — draws the app icon PNG set (.iconset).
// Usage: swift tools/make-icon.swift <output iconset directory>   →  then iconutil -c icns to produce the .icns
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let deepRed = NSColor(red: 0.80, green: 0.12, blue: 0.22, alpha: 1)

func drawIcon(_ s: CGFloat) {
    let inset = s * 0.09
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
                          xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(starting: NSColor(red: 0.99, green: 0.47, blue: 0.36, alpha: 1), ending: deepRed)!.draw(in: bg, angle: -90)

    // shield
    let cx = s / 2
    let top = s * 0.79, bottom = s * 0.19, half = s * 0.27
    let shield = NSBezierPath()
    shield.move(to: NSPoint(x: cx, y: top))
    shield.line(to: NSPoint(x: cx + half, y: top - s * 0.09))
    shield.curve(to: NSPoint(x: cx, y: bottom),
                 controlPoint1: NSPoint(x: cx + half, y: top - s * 0.42),
                 controlPoint2: NSPoint(x: cx + half * 0.55, y: bottom + s * 0.09))
    shield.curve(to: NSPoint(x: cx - half, y: top - s * 0.09),
                 controlPoint1: NSPoint(x: cx - half * 0.55, y: bottom + s * 0.09),
                 controlPoint2: NSPoint(x: cx - half, y: top - s * 0.42))
    shield.close()
    NSColor.white.withAlphaComponent(0.96).setFill()
    shield.fill()

    // "no" sign inside the shield (ring + slash)
    let r = s * 0.13
    let center = NSPoint(x: cx, y: (top + bottom) / 2 + s * 0.03)
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    ring.lineWidth = s * 0.05
    deepRed.setStroke()
    ring.stroke()
    let slash = NSBezierPath()
    slash.lineWidth = s * 0.05
    slash.lineCapStyle = .round
    let d = r * 0.7071
    slash.move(to: NSPoint(x: center.x - d, y: center.y + d))
    slash.line(to: NSPoint(x: center.x + d, y: center.y - d))
    slash.stroke()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
