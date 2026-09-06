import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
let background = NSGradient(colors: [
    NSColor(red: 0.28, green: 0.76, blue: 0.66, alpha: 1),
    NSColor(red: 0.41, green: 0.78, blue: 0.97, alpha: 1),
    NSColor(red: 0.78, green: 0.93, blue: 0.96, alpha: 1)
])!
background.draw(in: bounds, angle: -35)

// A translucent glass orb gives the mark a recognisable silhouette at small sizes.
let glowRect = NSRect(x: 120, y: 120, width: 784, height: 784)
NSColor.white.withAlphaComponent(0.18).setFill()
NSBezierPath(roundedRect: glowRect, xRadius: 205, yRadius: 205).fill()

let route = NSBezierPath()
route.move(to: NSPoint(x: 190, y: 280))
route.curve(to: NSPoint(x: 830, y: 745), controlPoint1: NSPoint(x: 330, y: 90), controlPoint2: NSPoint(x: 675, y: 920))
route.lineWidth = 14
route.setLineDash([24, 24], count: 2, phase: 0)
NSColor.white.withAlphaComponent(0.65).setStroke()
route.stroke()

let borderRect = bounds.insetBy(dx: 94, dy: 94)
let border = NSBezierPath(roundedRect: borderRect, xRadius: 150, yRadius: 150)
border.lineWidth = 18
NSColor(red: 0.06, green: 0.25, blue: 0.23, alpha: 0.22).setStroke()
border.stroke()

let sunRect = NSRect(x: 278, y: 278, width: 468, height: 468)
NSColor(red: 1.0, green: 0.79, blue: 0.24, alpha: 1).setFill()
NSBezierPath(ovalIn: sunRect).fill()

let config = NSImage.SymbolConfiguration(pointSize: 330, weight: .black)
if let symbol = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    symbol.isTemplate = true
    NSColor(red: 0.06, green: 0.13, blue: 0.16, alpha: 1).set()
    let symbolRect = NSRect(x: 340, y: 350, width: 340, height: 340)
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
}

image.unlockFocus()
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create icon bitmap")
}
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: bounds)
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}

let output = URL(fileURLWithPath: "Prompti/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try png.write(to: output)
print(output.path)
