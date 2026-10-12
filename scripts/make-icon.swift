// Draws the app icon: a journal with a keyhole and a "+" badge on an indigo squircle.
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
let indigo = color(0x4F46E5)

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

// Journal: white cover with a lavender spine.
let book = NSRect(x: 292, y: 238, width: 430, height: 540)
let cover = NSBezierPath(roundedRect: book, xRadius: 46, yRadius: 46)
NSGraphicsContext.saveGraphicsState()
let bookShadow = NSShadow()
bookShadow.shadowColor = color(0x000000, 0.22)
bookShadow.shadowOffset = NSSize(width: 0, height: -14)
bookShadow.shadowBlurRadius = 30
bookShadow.set()
color(0xFAF9FF).setFill()
cover.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
cover.addClip()
color(0xDDD8FF).setFill()
NSRect(x: book.minX, y: book.minY, width: 78, height: book.height).fill()
color(0xC7C0FA).setFill()
NSRect(x: book.minX + 78, y: book.minY, width: 8, height: book.height).fill()
NSGraphicsContext.restoreGraphicsState()

// Keyhole, centred on the cover area right of the spine.
let cx = book.minX + 86 + (book.width - 86) / 2
let keyhole = NSBezierPath(ovalIn: NSRect(x: cx - 58, y: 500, width: 116, height: 116))
let stem = NSBezierPath()
stem.move(to: NSPoint(x: cx - 26, y: 530))
stem.line(to: NSPoint(x: cx + 26, y: 530))
stem.line(to: NSPoint(x: cx + 46, y: 382))
stem.curve(to: NSPoint(x: cx + 30, y: 364), controlPoint1: NSPoint(x: cx + 48, y: 372), controlPoint2: NSPoint(x: cx + 40, y: 364))
stem.line(to: NSPoint(x: cx - 30, y: 364))
stem.curve(to: NSPoint(x: cx - 46, y: 382), controlPoint1: NSPoint(x: cx - 40, y: 364), controlPoint2: NSPoint(x: cx - 48, y: 372))
stem.close()
keyhole.append(stem.reversed)
keyhole.windingRule = .nonZero
NSGradient(starting: color(0x6D5DF6), ending: color(0x3730A3))!.draw(in: keyhole, angle: -90)

// "+" badge over the cover's top-right corner, ringed in white to separate it.
let badgeCenter = NSPoint(x: book.maxX - 6, y: book.maxY - 4)
let radius: CGFloat = 100
color(0xFFFFFF).setFill()
NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - radius - 16, y: badgeCenter.y - radius - 16,
                            width: (radius + 16) * 2, height: (radius + 16) * 2)).fill()
let badge = NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - radius, y: badgeCenter.y - radius, width: radius * 2, height: radius * 2))
NSGradient(starting: color(0x4ADE9A), ending: color(0x10A36B))!.draw(in: badge, angle: -90)
color(0xFFFFFF).setFill()
let arm: CGFloat = 104, thickness: CGFloat = 32
NSBezierPath(roundedRect: NSRect(x: badgeCenter.x - arm / 2, y: badgeCenter.y - thickness / 2, width: arm, height: thickness),
             xRadius: thickness / 2, yRadius: thickness / 2).fill()
NSBezierPath(roundedRect: NSRect(x: badgeCenter.x - thickness / 2, y: badgeCenter.y - arm / 2, width: thickness, height: arm),
             xRadius: thickness / 2, yRadius: thickness / 2).fill()

NSGraphicsContext.current = nil
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
