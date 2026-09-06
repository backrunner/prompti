import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
// iOS applies the final rounded mask. Keep this artwork full bleed and leave
// generous safe margins so the mark remains legible at every icon size.
let background = NSGradient(colors: [
    NSColor(red: 0.07, green: 0.45, blue: 0.40, alpha: 1),
    NSColor(red: 0.18, green: 0.67, blue: 0.69, alpha: 1),
    NSColor(red: 0.38, green: 0.73, blue: 0.93, alpha: 1)
])!
background.draw(in: bounds, angle: -38)

// Soft light blooms create depth without drawing a rounded-corner frame.
NSColor.white.withAlphaComponent(0.12).setFill()
NSBezierPath(ovalIn: NSRect(x: -160, y: 520, width: 780, height: 780)).fill()
NSColor(red: 0.76, green: 1, blue: 0.92, alpha: 0.14).setFill()
NSBezierPath(ovalIn: NSRect(x: 530, y: -180, width: 760, height: 760)).fill()

// A restrained glass disc is the single container for the travel mark.
let glassRect = NSRect(x: 154, y: 154, width: 716, height: 716)
NSColor.white.withAlphaComponent(0.20).setFill()
NSBezierPath(ovalIn: glassRect).fill()
let glassStroke = NSBezierPath(ovalIn: glassRect.insetBy(dx: 5, dy: 5))
glassStroke.lineWidth = 10
NSColor.white.withAlphaComponent(0.34).setStroke()
glassStroke.stroke()

// The route is deliberately short and quiet, so the airplane remains the
// first thing read by the eye.
let route = NSBezierPath()
route.move(to: NSPoint(x: 274, y: 330))
route.curve(to: NSPoint(x: 750, y: 674), controlPoint1: NSPoint(x: 394, y: 130), controlPoint2: NSPoint(x: 610, y: 858))
route.lineWidth = 13
route.setLineDash([20, 24], count: 2, phase: 0)
NSColor.white.withAlphaComponent(0.82).setStroke()
route.stroke()

for point in [NSPoint(x: 274, y: 330), NSPoint(x: 750, y: 674)] {
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)).fill()
}

let config = NSImage.SymbolConfiguration(pointSize: 330, weight: .black)
if let symbol = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    symbol.isTemplate = true
    NSColor(red: 0.06, green: 0.13, blue: 0.16, alpha: 1).set()
    let symbolRect = NSRect(x: 342, y: 342, width: 340, height: 340)
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 512, yBy: 512)
    transform.rotate(byDegrees: -18)
    transform.translateX(by: -512, yBy: -512)
    transform.concat()
    NSColor(red: 0.04, green: 0.20, blue: 0.22, alpha: 0.20).set()
    symbol.draw(in: symbolRect.offsetBy(dx: 0, dy: -13), from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
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
