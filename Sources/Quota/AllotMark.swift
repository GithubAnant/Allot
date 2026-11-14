import AppKit

/// A usage curve with a rounded peak, flat shelf and open negative space.
enum AllotMark {
    static func path(in rect: NSRect) -> NSBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + rect.width * x / 100, y: rect.maxY - rect.height * y / 100)
        }
        let path = NSBezierPath()
        path.move(to: point(2, 80))
        path.curve(to: point(0, 76), controlPoint1: point(0, 79), controlPoint2: point(0, 78))
        path.line(to: point(0, 72))
        path.curve(to: point(8, 63), controlPoint1: point(0, 66), controlPoint2: point(3, 64))
        path.curve(to: point(44, 35), controlPoint1: point(29, 59), controlPoint2: point(35, 50))
        path.curve(to: point(56, 20), controlPoint1: point(49, 26), controlPoint2: point(51, 20))
        path.curve(to: point(69, 33), controlPoint1: point(61, 20), controlPoint2: point(65, 26))
        path.curve(to: point(82, 42), controlPoint1: point(73, 40), controlPoint2: point(77, 42))
        path.line(to: point(98, 42))
        path.curve(to: point(100, 44), controlPoint1: point(100, 42), controlPoint2: point(100, 42))
        path.line(to: point(100, 78))
        path.curve(to: point(97, 80), controlPoint1: point(100, 80), controlPoint2: point(99, 81))
        path.curve(to: point(3, 80), controlPoint1: point(70, 62), controlPoint2: point(38, 62))
        path.curve(to: point(2, 80), controlPoint1: point(2.6, 80.2), controlPoint2: point(2.2, 80.3))
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
        image.accessibilityDescription = "Allot · AI usage"
        return image
    }
}
