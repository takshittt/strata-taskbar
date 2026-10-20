// Draws Strata's 1024×1024 master icon: layered bands (the "strata") above a small taskbar.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-master.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Rounded-square body with the standard macOS margin (824 pt body on a 1024 canvas).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = CGSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
color(0x1E2A5A).setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
bodyPath.addClip()
NSGradient(colors: [color(0x2B3A8C), color(0x4C3FA8), color(0x7A4FC4)])!.draw(in: body, angle: 70)

// Strata: three translucent layered bands, each a little narrower and lighter going up.
let bands: [(y: CGFloat, inset: CGFloat, hex: UInt32, alpha: CGFloat)] = [
    (520, 150, 0x9FB4FF, 0.55),
    (612, 200, 0xC3D0FF, 0.70),
    (704, 250, 0xEEF2FF, 0.90),
]
for band in bands {
    let rect = CGRect(x: body.minX + band.inset, y: band.y, width: body.width - 2 * band.inset, height: 64)
    color(band.hex, band.alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 32, yRadius: 32).fill()
}

// The taskbar: a bright bar along the bottom with window buttons, the first one active.
let bar = CGRect(x: body.minX + 90, y: 250, width: body.width - 180, height: 150)
color(0xFFFFFF, 0.92).setFill()
NSBezierPath(roundedRect: bar, xRadius: 40, yRadius: 40).fill()

let start = CGRect(x: bar.minX + 30, y: bar.minY + 35, width: 80, height: 80)
for (dx, dy) in [(0, 0), (44, 0), (0, 44), (44, 44)] as [(CGFloat, CGFloat)] {
    color(0x4C5BD4).setFill()
    NSBezierPath(roundedRect: CGRect(x: start.minX + dx, y: start.minY + dy, width: 36, height: 36), xRadius: 9, yRadius: 9).fill()
}
let buttons: [(x: CGFloat, width: CGFloat, active: Bool)] = [(150, 170, true), (340, 130, false), (490, 100, false)]
for button in buttons {
    let rect = CGRect(x: bar.minX + button.x, y: bar.minY + 42, width: button.width, height: 66)
    color(button.active ? 0x6B5CE0 : 0xB9C1EE, button.active ? 1 : 0.9).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
}
color(0x6B5CE0).setFill()
NSBezierPath(roundedRect: CGRect(x: bar.minX + 175, y: bar.minY + 16, width: 120, height: 12), xRadius: 6, yRadius: 6).fill()
NSGraphicsContext.restoreGraphicsState()

// Hairline highlight on the body edge.
color(0xFFFFFF, 0.18).setStroke()
bodyPath.lineWidth = 4
bodyPath.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
