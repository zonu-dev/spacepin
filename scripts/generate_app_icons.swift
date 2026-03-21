import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputURL = rootURL
    .appendingPathComponent("Support", isDirectory: true)
    .appendingPathComponent("Assets.xcassets", isDirectory: true)
    .appendingPathComponent("AppIcon.appiconset", isDirectory: true)

let iconNames: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: image.size)
    NSColor(calibratedRed: 0.17, green: 0.46, blue: 0.93, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()

    let innerRect = rect.insetBy(dx: size * 0.07, dy: size * 0.07)
    NSColor(calibratedRed: 0.27, green: 0.58, blue: 0.98, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: innerRect, xRadius: size * 0.18, yRadius: size * 0.18).fill()

    let pinConfig = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .bold)
    let pinImage = NSImage(systemSymbolName: "pin.circle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(pinConfig)

    let pinRect = NSRect(
        x: size * 0.19,
        y: size * 0.16,
        width: size * 0.62,
        height: size * 0.62
    )
    NSColor.white.set()
    pinImage?.draw(
        in: pinRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    image.unlockFocus()
    return image
}

func writePNG(named name: String, size: CGFloat) throws {
    let image = makeIcon(size: size)
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "SpacePinIconGenerator", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to encode \(name)"
        ])
    }

    try png.write(to: outputURL.appendingPathComponent(name))
}

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
for (name, size) in iconNames {
    try writePNG(named: name, size: size)
}

print("Generated \(iconNames.count) app icons in \(outputURL.path)")
