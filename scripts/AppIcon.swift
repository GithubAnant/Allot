import AppKit

@main enum AppIcon {
    static func main() throws {
        guard (2...3).contains(CommandLine.arguments.count) else {
            throw NSError(domain: "AllotIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: render-icon <iconset-directory> [branding-directory]"])
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try png(pixels: points * scale, background: true).write(to: directory.appendingPathComponent(name))
        }
        if CommandLine.arguments.count == 3 {
            let branding = URL(fileURLWithPath: CommandLine.arguments[2])
            try FileManager.default.createDirectory(at: branding, withIntermediateDirectories: true)
            try png(pixels: 1024, background: true).write(to: branding.appendingPathComponent("app-icon.png"))
            try png(pixels: 1024, background: false).write(to: branding.appendingPathComponent("mark.png"))
        }
    }
    private static func png(pixels: Int, background: Bool) throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "AllotIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create icon bitmap"])
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let size = CGFloat(pixels), bounds = NSRect(x: 0, y: 0, width: size, height: size)
        context.cgContext.clear(bounds)
        if background {
            NSColor(calibratedWhite: 9 / 255, alpha: 1).setFill()
            let surface = bounds.insetBy(dx: size * 0.06, dy: size * 0.06)
            NSBezierPath(roundedRect: surface, xRadius: size * 0.19, yRadius: size * 0.19).fill()
        }
        NSColor.white.setFill()
        let inset = background ? size * 0.24 : 0
        let markBounds = bounds.insetBy(dx: inset, dy: inset)
        AllotMark.path(in: markBounds).fill()
        AllotMark.accentColor.setFill()
        AllotMark.accentPath(in: markBounds).fill()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AllotIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
        }
        return data
    }
}
