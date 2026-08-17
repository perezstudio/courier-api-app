import AppKit

/// Horizontal bar chart of the request phases.
///
/// One of the three custom views the plan allows (REQUIREMENTS.md §7.4): AppKit
/// ships no chart control.
@MainActor
final class TimelineChartView: NSView {

    private var timing: TimingBreakdown?

    private static let phaseColors: [NSColor] = [
        .systemBlue, .systemTeal, .systemPurple, .systemOrange, .systemPink, .systemGreen,
    ]

    func setTiming(_ timing: TimingBreakdown?) {
        self.timing = timing
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let timing, timing.total > 0 else {
            drawPlaceholder()
            return
        }

        let phases = timing.phases
        guard !phases.isEmpty else {
            drawPlaceholder()
            return
        }

        let labelWidth: CGFloat = 76
        let valueWidth: CGFloat = 64
        let rowHeight: CGFloat = 26
        let barInset: CGFloat = 12
        let available = bounds.width - labelWidth - valueWidth - barInset * 2
        guard available > 40 else { return }

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        for (index, phase) in phases.enumerated() {
            let y = barInset + CGFloat(index) * rowHeight

            (phase.name as NSString).draw(
                at: NSPoint(x: barInset, y: y + 4),
                withAttributes: labelAttributes
            )

            // Bars are proportional to the slowest phase, not to the total —
            // otherwise a 2ms DNS lookup next to a 900ms wait is invisible.
            let longest = phases.map(\.duration).max() ?? phase.duration
            let fraction = longest > 0 ? phase.duration / longest : 0
            let barWidth = max(2, available * fraction)

            let barRect = NSRect(
                x: labelWidth + barInset,
                y: y + 4,
                width: barWidth,
                height: 12
            )
            let path = NSBezierPath(roundedRect: barRect, xRadius: 3, yRadius: 3)
            Self.phaseColors[index % Self.phaseColors.count].setFill()
            path.fill()

            let milliseconds = String(format: "%.0f ms", phase.duration * 1000)
            (milliseconds as NSString).draw(
                at: NSPoint(x: barRect.maxX + 8, y: y + 3),
                withAttributes: valueAttributes
            )
        }

        let totalY = barInset + CGFloat(phases.count) * rowHeight + 6
        let total = String(format: "Total  %.0f ms", timing.total * 1000)
        (total as NSString).draw(
            at: NSPoint(x: barInset, y: totalY),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    private func drawPlaceholder() {
        let text = "No timing available" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    override func accessibilityLabel() -> String? {
        guard let timing, timing.total > 0 else { return "No timing available" }
        let parts = timing.phases.map { "\($0.name) \(Int($0.duration * 1000)) milliseconds" }
        return "Request timing: " + parts.joined(separator: ", ")
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }
}
