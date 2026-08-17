import Foundation

/// The arithmetic behind the workspace pager's snapping, kept free of AppKit so
/// it can be tested without a live scroll view.
nonisolated enum PagerGeometry {

    /// The page a scroll offset has landed nearest to.
    ///
    /// Rounded rather than truncated: truncation only ever advances once a
    /// swipe has dragged a *full* page across, so a half-page flick would fall
    /// back to where it started.
    ///
    /// Returns nil when there is nothing to snap to — no pages, or a width of
    /// zero before the first layout pass, where the division is meaningless.
    static func pageIndex(offsetX: CGFloat, pageWidth: CGFloat, pageCount: Int) -> Int? {
        guard pageCount > 0, pageWidth > 0 else { return nil }
        let raw = Int((offsetX / pageWidth).rounded())
        return min(max(raw, 0), pageCount - 1)
    }

    /// The offset that puts `index` flush in the viewport.
    static func offset(forPage index: Int, pageWidth: CGFloat) -> CGFloat {
        CGFloat(index) * pageWidth
    }
}
