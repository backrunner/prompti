import AppKit

// Run from the repository root: swift Tools/GenerateAppIcon.swift
// One hand-drawn contour drives the brand SVGs, legacy PNGs and Icon Composer.
// Coordinates use a top-left origin on an unmasked 1024 × 1024 canvas.
enum Segment {
    case move(CGFloat, CGFloat)
    case line(CGFloat, CGFloat)
    case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    case close
}

let contour: [Segment] = [
    .move(278, 816), .line(278, 393),
    .curve(278, 287, 339, 222, 443, 222), .line(566, 222),
    .curve(705, 222, 798, 315, 798, 446),
    .curve(798, 577, 705, 670, 566, 670), .line(426, 670),
    .line(313, 833), .curve(301, 850, 278, 840, 278, 816), .close,
    // Open counter: its generous width survives notifications and tinted mode.
    .move(506, 359), .line(570, 359),
    .curve(614.2, 359, 650, 394.8, 650, 439), .line(650, 453),
    .curve(650, 497.2, 614.2, 533, 570, 533), .line(506, 533),
    .curve(461.8, 533, 426, 497.2, 426, 453), .line(426, 439),
    .curve(426, 394.8, 461.8, 359, 506, 359), .close
]

// Optical centering accounts for the bowl's weight and the speech tail.
let offset = CGPoint(x: -18, y: -12)
let ink = "#103F38"
let cream = "#F7FFEA"
let mint = "#A3F2CE"

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x + offset.x, y: y + offset.y)
}

func markPath() -> CGPath {
    let path = CGMutablePath()
    for segment in contour {
        switch segment {
        case let .move(x, y): path.move(to: point(x, y))
        case let .line(x, y): path.addLine(to: point(x, y))
        case let .curve(x1, y1, x2, y2, x, y):
            path.addCurve(to: point(x, y), control1: point(x1, y1), control2: point(x2, y2))
        case .close: path.closeSubpath()
        }
    }
    return path
}

func svgPath() -> String {
    func pair(_ x: CGFloat, _ y: CGFloat) -> String {
        let p = point(x, y)
        return "\(p.x) \(p.y)"
    }
    return contour.map { segment in
        switch segment {
        case let .move(x, y): return "M\(pair(x, y))"
        case let .line(x, y): return "L\(pair(x, y))"
        case let .curve(x1, y1, x2, y2, x, y):
            return "C\(pair(x1, y1)) \(pair(x2, y2)) \(pair(x, y))"
        case .close: return "Z"
        }
    }.joined(separator: " ")
}

func svg(fill: String, tight: Bool = false) -> String {
    // Brand exports include a small clear space; app layers keep the full canvas.
    let viewBox = tight ? "210 160 620 720" : "0 0 1024 1024"
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(tight ? 620 : 1024)" height="\(tight ? 720 : 1024)" viewBox="\(viewBox)">
      <title>Prompti</title>
      <path fill="\(fill)" fill-rule="evenodd" d="\(svgPath())"/>
    </svg>

    """
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Prompti/Assets.xcassets/AppIcon.appiconset")
let composer = root.appendingPathComponent("Prompti/AppIcon.icon")
let brand = root.appendingPathComponent("Documentation/Brand")
for directory in [catalog, composer.appendingPathComponent("Assets"), brand] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

func color(_ hex: String) -> CGColor {
    let value = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        CGFloat((value >> 16) & 255) / 255,
        CGFloat((value >> 8) & 255) / 255,
        CGFloat(value & 255) / 255, 1
    ])!
}

func writeIcon(filename: String, top: String, bottom: String, foreground: String) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // RGB without an alpha channel: App Store images must be opaque, including corners.
    guard let context = CGContext(data: nil, width: 1024, height: 1024,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Could not create icon canvas")
    }
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    let gradient = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.addPath(markPath())
    context.setFillColor(color(foreground))
    context.drawPath(using: .eoFill)
    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Could not encode icon")
    }
    try png.write(to: catalog.appendingPathComponent(filename), options: .atomic)
}

try writeIcon(filename: "AppIcon.png", top: "#19B88B", bottom: "#05766B", foreground: cream)
try writeIcon(filename: "AppIcon-Dark.png", top: "#122F2B", bottom: "#081C1A", foreground: mint)
try writeIcon(filename: "AppIcon-Tinted.png", top: "#252525", bottom: "#111111", foreground: "#F2F2F2")

try svg(fill: cream).write(to: composer.appendingPathComponent("Assets/Prompti.svg"), atomically: true, encoding: .utf8)
try svg(fill: ink, tight: true).write(to: brand.appendingPathComponent("Prompti-Mark.svg"), atomically: true, encoding: .utf8)
try svg(fill: cream, tight: true).write(to: brand.appendingPathComponent("Prompti-Mark-Reversed.svg"), atomically: true, encoding: .utf8)
try svg(fill: "currentColor", tight: true).write(to: brand.appendingPathComponent("Prompti-Mark-Mono.svg"), atomically: true, encoding: .utf8)

// The in-app template uses the same contour as the icon, with vector preservation.
let markAsset = root.appendingPathComponent("Prompti/Assets.xcassets/BrandMark.imageset")
try FileManager.default.createDirectory(at: markAsset, withIntermediateDirectories: true)
var mediaBox = CGRect(x: 0, y: 0, width: 620, height: 720)
let pdfData = NSMutableData()
guard let consumer = CGDataConsumer(data: pdfData),
      let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
    fatalError("Could not create brand PDF")
}
pdf.beginPDFPage(nil)
pdf.translateBy(x: -210, y: 880)
pdf.scaleBy(x: 1, y: -1)
pdf.addPath(markPath())
pdf.setFillColor(color(ink))
pdf.drawPath(using: .eoFill)
pdf.endPDFPage()
pdf.closePDF()
try (pdfData as Data).write(to: markAsset.appendingPathComponent("BrandMark.pdf"), options: .atomic)
let markContents: [String: Any] = [
    "images": [["filename": "BrandMark.pdf", "idiom": "universal"]],
    "info": ["author": "xcode", "version": 1],
    "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"]
]
try (JSONSerialization.data(withJSONObject: markContents, options: [.prettyPrinted, .sortedKeys]) + Data([0x0A]))
    .write(to: markAsset.appendingPathComponent("Contents.json"), options: .atomic)

let composition: [String: Any] = [
    "fill": ["solid": "srgb:0.025,0.58,0.45,1"],
    "groups": [[
        "name": "Prompti",
        "layers": [[
            "name": "P · conversation",
            "image-name": "Prompti.svg",
            "fill-specializations": [[
                "appearance": "dark",
                "value": ["solid": "srgb:0.63922,0.94902,0.80784,1"]
            ]]
        ]]
    ]],
    "supported-platforms": ["squares": ["iOS"]]
]
try (JSONSerialization.data(withJSONObject: composition, options: [.prettyPrinted, .sortedKeys]) + Data([0x0A]))
    .write(to: composer.appendingPathComponent("icon.json"), options: .atomic)

let appearances: [(String, String?)] = [("AppIcon.png", nil), ("AppIcon-Dark.png", "dark"), ("AppIcon-Tinted.png", "tinted")]
let entries: [[String: Any]] = appearances.map { filename, appearance in
    var entry: [String: Any] = ["filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
    if let appearance { entry["appearances"] = [["appearance": "luminosity", "value": appearance]] }
    return entry
}
try (JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]],
                            options: [.prettyPrinted, .sortedKeys]) + Data([0x0A]))
    .write(to: catalog.appendingPathComponent("Contents.json"), options: .atomic)
print("Generated app icons, Icon Composer source, vector brand marks and the in-app template PDF.")
