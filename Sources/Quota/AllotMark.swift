import AppKit

/// A three-quarter quota disk with its remaining portion set apart.
enum AllotMark {
    static func path(in rect: NSRect) -> NSBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + rect.width * x / 100, y: rect.maxY - rect.height * y / 100)
        }
        let scale = min(rect.width, rect.height)
        let path = NSBezierPath()
        let center = point(44, 58)
        path.move(to: center)
        path.appendArc(withCenter: center, radius: scale * 0.40, startAngle: 90, endAngle: 360, clockwise: false)
        path.close()
        let portion = point(54, 46)
        path.move(to: portion)
        path.appendArc(withCenter: portion, radius: scale * 0.365, startAngle: 84, endAngle: -6, clockwise: true)
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
