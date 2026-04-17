import AppKit

/// NSSplitView subclass that draws no divider line.
/// The divider remains at its configured thickness so it's still draggable,
/// just visually transparent.
final class InvisibleDividerSplitView: NSSplitView {
    override var dividerColor: NSColor { .clear }

    override func drawDivider(in rect: NSRect) {
        // Intentionally empty — no line drawn.
    }
}
