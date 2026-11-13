import AppKit
import SwiftUI

struct MetricPicker: NSViewRepresentable {
    @Binding var selection: T3Metric
    func makeNSView(context: Context) -> MetricControl { MetricControl(frame: .zero) }
    func updateNSView(_ control: MetricControl, context: Context) {
        control.onSelection = { selection = $0 }
        control.selectedSegment = T3Metric.allCases.firstIndex(of: selection) ?? 2
    }
}

final class MetricControl: NSSegmentedControl {
    var onSelection: ((T3Metric) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = MetricCell(textCell: "")
        segmentCount = T3Metric.allCases.count
        for (index, metric) in T3Metric.allCases.enumerated() {
            setLabel(metric.rawValue, forSegment: index)
            setToolTip("Show " + metric.rawValue, forSegment: index)
        }
        trackingMode = .selectOne
        segmentStyle = .rounded
        segmentDistribution = .fillEqually
        font = NSFont(name: "Geist-Regular", size: 12.1) ?? .systemFont(ofSize: 12.1)
        focusRingType = .none
        target = self; action = #selector(changed)
        setAccessibilityLabel("Usage metric")
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    @objc private func changed() {
        guard T3Metric.allCases.indices.contains(selectedSegment) else { return }
        onSelection?(T3Metric.allCases[selectedSegment])
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }
}

private final class MetricCell: NSSegmentedCell {
    override func draw(withFrame frame: NSRect, in controlView: NSView) {
        let surface = frame.insetBy(dx: 0, dy: 1)
        NSColor(white: 0.045, alpha: 1).setFill()
        NSBezierPath(roundedRect: surface, xRadius: 5, yRadius: 5).fill()
        guard segmentCount > 0 else { return }
        let width = surface.width / CGFloat(segmentCount)
        for index in 0..<segmentCount {
            let rect = NSRect(x: surface.minX + CGFloat(index) * width, y: surface.minY, width: width, height: surface.height).insetBy(dx: 2, dy: 2)
            if isSelected(forSegment: index) {
                NSColor(white: 0.13, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            }
            let text = NSAttributedString(string: label(forSegment: index) ?? "", attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 12.1),
                .foregroundColor: NSColor(white: isSelected(forSegment: index) ? 0.86 : 0.48, alpha: 1)
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }
}
