// Draws the app icon (a mint leaf on a soft sage squircle) and writes Resources/AppIcon.icns.
// Run: swift tools/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: the squircle is 824/1024 of the canvas, centred.
    let inset = s * 100 / 1024
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.02
    shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.09, green: 0.13, blue: 0.12, alpha: 1),
                        NSColor(srgbRed: 0.03, green: 0.05, blue: 0.05, alpha: 1)])!
        .draw(in: shape, angle: -90)

    // Soft mint glow behind the leaf, like the island's.
    let glowR = rect.width * 0.36
    NSGradient(colors: [NSColor(srgbRed: 0.56, green: 0.89, blue: 0.78, alpha: 0.35),
                        NSColor(srgbRed: 0.56, green: 0.89, blue: 0.78, alpha: 0)])!
        .draw(fromCenter: NSPoint(x: rect.midX, y: rect.midY), radius: 0,
              toCenter: NSPoint(x: rect.midX, y: rect.midY), radius: glowR, options: [])

    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.42, weight: .medium)
        .applying(.init(paletteColors: [NSColor(srgbRed: 0.56, green: 0.89, blue: 0.78, alpha: 1)]))
    if let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = leaf.size
        leaf.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                             width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
