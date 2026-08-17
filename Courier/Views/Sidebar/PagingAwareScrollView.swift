import AppKit

/// A vertical scroll view that hands horizontal swipes to a pager.
///
/// Without this the workspace pager is unreachable by trackpad: each page fills
/// the sidebar with its own scrolling list, and that list swallows the whole
/// gesture, horizontal component included.
///
/// The axis is decided once per gesture rather than per event. A trackpad swipe
/// arrives as a stream — `began`, many `changed`, then momentum — and judging
/// each event separately lets a gesture that starts horizontal flip to vertical
/// mid-swipe as the finger drifts, so the page slides partway and then sticks.
/// Locking on `began` keeps one swipe on one axis. Discrete mouse-wheel ticks
/// carry no phase at all, so those are judged individually.
final class PagingAwareScrollView: NSScrollView {

    weak var pager: NSScrollView?

    private var routeToPager = false

    override func scrollWheel(with event: NSEvent) {
        let phase = event.phase
        let momentum = event.momentumPhase

        if phase.contains(.began) {
            routeToPager = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        } else if phase.isEmpty && momentum.isEmpty {
            routeToPager = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        }
        // `changed`, `ended`, and momentum events keep the locked axis.

        if routeToPager, let pager {
            pager.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
