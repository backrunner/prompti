import Testing
import UIKit
@testable import Prompti

@Suite("Destination artwork and scroll boundaries")
@MainActor
struct DestinationPresentationTests {
    @Test("Every built-in destination has its own compiled vector asset")
    func artworkCoverage() {
        for destination in DestinationCatalog().destinations {
            #expect(UIImage(named: "Destination-\(destination.id)") != nil,
                    "Missing artwork for \(destination.city)")
        }
    }

    @Test("Overflow distinguishes top, middle, bottom, short content and inset changes")
    func scrollBoundaries() {
        let cases: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool, Bool)] = [
            (-60, 1200, 600, 60, 30, false, true),
            (200, 1200, 600, 60, 30, true, true),
            (630, 1200, 600, 60, 30, true, false),
            (-60, 300, 600, 60, 30, false, false),
            (-90, 1200, 600, 60, 30, false, true),
            (650, 1200, 600, 60, 30, true, false),
            (0, 600, 600, 0, 0, false, false),
            (0, 600, 600, 0, 280, false, true)
        ]
        for (offset, height, viewport, top, bottom, above, below) in cases {
            let value = PromptiScrollOverflow(offset: offset, contentHeight: height,
                                             viewportHeight: viewport, topInset: top, bottomInset: bottom)
            #expect(value.above == above)
            #expect(value.below == below)
        }
    }
}
