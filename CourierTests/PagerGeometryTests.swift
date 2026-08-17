import Foundation
import Testing

@testable import Courier

/// The workspace pager's snapping, exercised without a scroll view.
@Suite("Pager geometry")
struct PagerGeometryTests {

    @Test("A resting offset maps to its own page")
    func exactOffsets() {
        #expect(PagerGeometry.pageIndex(offsetX: 0, pageWidth: 250, pageCount: 3) == 0)
        #expect(PagerGeometry.pageIndex(offsetX: 250, pageWidth: 250, pageCount: 3) == 1)
        #expect(PagerGeometry.pageIndex(offsetX: 500, pageWidth: 250, pageCount: 3) == 2)
    }

    /// The reason for rounding rather than truncating: a flick that drags most
    /// of a page across should commit, not fall back to where it started.
    @Test("Past the halfway point commits to the next page")
    func roundsToNearest() {
        // The boundary is half a page — 125 of 250 — either side of which the
        // swipe settles back or carries on.
        #expect(PagerGeometry.pageIndex(offsetX: 124, pageWidth: 250, pageCount: 3) == 0)
        #expect(PagerGeometry.pageIndex(offsetX: 126, pageWidth: 250, pageCount: 3) == 1)
        #expect(PagerGeometry.pageIndex(offsetX: 200, pageWidth: 250, pageCount: 3) == 1)
    }

    /// Rubber-banding scrolls past both ends, so the raw index goes out of
    /// range in normal use, not just in error cases.
    @Test("Overscroll clamps to the ends")
    func clampsToRange() {
        #expect(PagerGeometry.pageIndex(offsetX: -80, pageWidth: 250, pageCount: 3) == 0)
        #expect(PagerGeometry.pageIndex(offsetX: 9_000, pageWidth: 250, pageCount: 3) == 2)
    }

    /// Before the first layout pass the pager has no width, and the division
    /// would be meaningless — nil rather than a guessed page.
    @Test("No pages or no width means nothing to snap to")
    func degenerateInputs() {
        #expect(PagerGeometry.pageIndex(offsetX: 0, pageWidth: 0, pageCount: 3) == nil)
        #expect(PagerGeometry.pageIndex(offsetX: 0, pageWidth: 250, pageCount: 0) == nil)
    }

    @Test("A single workspace always resolves to itself")
    func singlePage() {
        #expect(PagerGeometry.pageIndex(offsetX: 0, pageWidth: 250, pageCount: 1) == 0)
        #expect(PagerGeometry.pageIndex(offsetX: 240, pageWidth: 250, pageCount: 1) == 0)
    }

    /// Round-trips: the offset for a page must land back on that page, or a
    /// programmatic scroll would be re-read as a swipe somewhere else.
    @Test("Offsets round-trip back to their page")
    func offsetRoundTrip() {
        let width: CGFloat = 312
        for index in 0..<5 {
            let offset = PagerGeometry.offset(forPage: index, pageWidth: width)
            #expect(
                PagerGeometry.pageIndex(offsetX: offset, pageWidth: width, pageCount: 5) == index
            )
        }
    }
}
