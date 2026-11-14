import AppKit

/// A chunky lowercase a with one portion set aside as a floating dot.
enum AllotMark {
    static let accentColor = NSColor(srgbRed: 215 / 255, green: 1, blue: 95 / 255, alpha: 1)
    static func path(in rect: NSRect) -> NSBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + rect.width * x / 100, y: rect.maxY - rect.height * y / 100)
        }
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.move(to: point(42, 20))
        path.curve(to: point(73, 34), controlPoint1: point(55, 20), controlPoint2: point(67, 26))
        path.line(to: point(73, 32))
        path.curve(to: point(83, 23), controlPoint1: point(73, 26), controlPoint2: point(78, 23))
        path.curve(to: point(96, 38), controlPoint1: point(91, 23), controlPoint2: point(96, 29))
        path.line(to: point(96, 83))
        path.curve(to: point(83, 97), controlPoint1: point(96, 91), controlPoint2: point(91, 97))
        path.curve(to: point(71, 89), controlPoint1: point(77, 97), controlPoint2: point(73, 94))
        path.curve(to: point(42, 99), controlPoint1: point(64, 95), controlPoint2: point(54, 99))
        path.curve(to: point(3, 60), controlPoint1: point(20, 99), controlPoint2: point(3, 82))
        path.curve(to: point(42, 20), controlPoint1: point(3, 38), controlPoint2: point(20, 20))
        path.close()
        path.append(oval(x: 28, y: 44, width: 30, height: 31, in: rect))
        path.append(accentPath(in: rect))
        return path
    }
    static func accentPath(in rect: NSRect) -> NSBezierPath {
        oval(x: 78, y: 0, width: 18, height: 18, in: rect)
    }
    private static func oval(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, in rect: NSRect) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: rect.minX + rect.width * x / 100, y: rect.maxY - rect.height * (y + height) / 100,
                                  width: rect.width * width / 100, height: rect.height * height / 100))
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
