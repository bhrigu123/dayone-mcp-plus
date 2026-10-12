// Draws the app icon: an open journal with a keyhole on its spine, on an indigo squircle.
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

// Open journal: two pages meeting at a centre spine, with a lavender page stack below for depth.
func page(_ side: CGFloat, inset: CGFloat, drop: CGFloat) -> NSBezierPath {
    // side = -1 for the left page, +1 for the right; mirrored so the book is symmetric.
    let spineTop = NSPoint(x: 512, y: 700 - drop), spineBottom = NSPoint(x: 512, y: 318 - drop)
    let outerTop = NSPoint(x: 512 + side * (262 - inset), y: 742 - drop)
    let outerBottom = NSPoint(x: 512 + side * (262 - inset), y: 352 - drop)
    let path = NSBezierPath()
    path.move(to: spineTop)
    path.curve(to: outerTop, controlPoint1: NSPoint(x: 512 + side * 80, y: 744 - drop),
               controlPoint2: NSPoint(x: 512 + side * 170, y: 752 - drop))
    path.line(to: outerBottom)
    path.curve(to: spineBottom, controlPoint1: NSPoint(x: 512 + side * 170, y: 362 - drop),
               controlPoint2: NSPoint(x: 512 + side * 80, y: 356 - drop))
    path.close()
    return path
}

NSGraphicsContext.saveGraphicsState()
let bookShadow = NSShadow()
bookShadow.shadowColor = color(0x000000, 0.25)
bookShadow.shadowOffset = NSSize(width: 0, height: -14)
bookShadow.shadowBlurRadius = 30
bookShadow.set()
color(0xC9C2FA).setFill()
for side in [CGFloat(-1), 1] { page(side, inset: -10, drop: 34).fill() }
NSGraphicsContext.restoreGraphicsState()
color(0xE4E0FF).setFill()
for side in [CGFloat(-1), 1] { page(side, inset: -4, drop: 17).fill() }
color(0xFAF9FF).setFill()
for side in [CGFloat(-1), 1] { page(side, inset: 0, drop: 0).fill() }

// Faint writing lines on each page, mirrored, stopping short of the keyhole.
color(0xDCD7FC).setFill()
for y in stride(from: CGFloat(630), through: 420, by: -52) {
    for side in [CGFloat(-1), 1] {
        let inner: CGFloat = 92, outer: CGFloat = 214
        let x = side < 0 ? 512 - outer : 512 + inner
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: outer - inner, height: 12), xRadius: 6, yRadius: 6).fill()
    }
}

// Spine crease.
let spine = NSBezierPath()
spine.move(to: NSPoint(x: 512, y: 700))
spine.line(to: NSPoint(x: 512, y: 318))
spine.lineWidth = 6
color(0xC9C2FA).setStroke()
spine.stroke()

// Keyhole on the spine, centred on the pages.
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
