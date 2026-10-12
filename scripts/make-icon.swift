// Draws the app icon: a journal with a keyhole, centred on an indigo squircle.
// Usage: swift scripts/make-icon.swift <output.png>   (1024×1024)
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background squircle on Apple's icon grid (824pt body inside 1024 canvas), with a soft shadow.
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0x000000, 0.28)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()
color(0x3730A3).setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0x7C6CF8), ending: color(0x2E2A7A))!.draw(in: body, angle: -90)

// Journal: white cover centred on the canvas.
let book = NSRect(x: 512 - 220, y: 512 - 280, width: 440, height: 560)
let cover = NSBezierPath(roundedRect: book, xRadius: 52, yRadius: 52)
NSGraphicsContext.saveGraphicsState()
let bookShadow = NSShadow()
bookShadow.shadowColor = color(0x000000, 0.22)
bookShadow.shadowOffset = NSSize(width: 0, height: -14)
bookShadow.shadowBlurRadius = 30
bookShadow.set()
color(0xFAF9FF).setFill()
cover.fill()
NSGraphicsContext.restoreGraphicsState()

// Keyhole, centred on the cover (spans y 392...632, midpoint 512).
let cx: CGFloat = 512
let keyhole = NSBezierPath(ovalIn: NSRect(x: cx - 64, y: 504, width: 128, height: 128))
let stem = NSBezierPath()
stem.move(to: NSPoint(x: cx - 28, y: 540))
stem.line(to: NSPoint(x: cx + 28, y: 540))
stem.line(to: NSPoint(x: cx + 50, y: 412))
stem.curve(to: NSPoint(x: cx + 32, y: 392), controlPoint1: NSPoint(x: cx + 52, y: 401), controlPoint2: NSPoint(x: cx + 43, y: 392))
stem.line(to: NSPoint(x: cx - 32, y: 392))
stem.curve(to: NSPoint(x: cx - 50, y: 412), controlPoint1: NSPoint(x: cx - 43, y: 392), controlPoint2: NSPoint(x: cx - 52, y: 401))
stem.close()
keyhole.append(stem.reversed)
keyhole.windingRule = .nonZero
NSGradient(starting: color(0x6D5DF6), ending: color(0x3730A3))!.draw(in: keyhole, angle: -90)

NSGraphicsContext.current = nil
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
