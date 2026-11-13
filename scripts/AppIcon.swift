import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let pixels = points * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let size = CGFloat(pixels)
    NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: size * 0.2, yRadius: size * 0.2).fill()
    for (index, fraction) in [0.85, 0.62, 0.36].enumerated() {
        let y = size * (0.65 - Double(index) * 0.19)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: size * 0.2, y: y, width: size * 0.6, height: size * 0.09), xRadius: size * 0.02, yRadius: size * 0.02).fill()
        NSColor(calibratedWhite: 0.84, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: size * 0.2, y: y, width: size * 0.6 * fraction, height: size * 0.09), xRadius: size * 0.02, yRadius: size * 0.02).fill()
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
}
