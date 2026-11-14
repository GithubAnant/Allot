import AppKit

/// The selected Token mark, shared by the menu bar and app-icon renderer.
enum RationMark {
    static func path(in rect: NSRect) -> NSBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + rect.width * x / 100, y: rect.maxY - rect.height * y / 100)
        }
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.move(to: point(9, 0))
        path.line(to: point(91, 0))
        path.curve(to: point(100, 9), controlPoint1: point(96, 0), controlPoint2: point(100, 4))
        path.line(to: point(100, 84))
        path.curve(to: point(84, 100), controlPoint1: point(100, 93), controlPoint2: point(93, 100))
        path.line(to: point(9, 100))
        path.curve(to: point(0, 91), controlPoint1: point(4, 100), controlPoint2: point(0, 96))
        path.line(to: point(0, 9))
        path.curve(to: point(9, 0), controlPoint1: point(0, 4), controlPoint2: point(4, 0))
        path.close()
        path.move(to: point(32.4, 22.3))
        path.line(to: point(66.5, 22.3))
        path.line(to: point(66.5, 48.1))
        path.line(to: point(32.4, 48.1))
        path.close()
        path.move(to: point(32.4, 64.8))
        path.line(to: point(54.3, 64.8))
        path.line(to: point(86, 100))
        path.line(to: point(67.1, 100))
        path.line(to: point(67.1, 90.5))
        path.line(to: point(32.4, 90.5))
        path.close()
        return path
    }
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { bounds in
            NSColor.black.setFill()
            path(in: bounds.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ration · AI usage"
        return image
    }
}
