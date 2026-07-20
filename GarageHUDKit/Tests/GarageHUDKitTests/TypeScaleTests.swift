import XCTest
@testable import GarageHUDKit

/// W-066 — the type scale must survive the owner's text-size setting.
///
/// Field-found 2026-07-19: iOS text size had no effect on GarageHUD and there was no in-app zoom,
/// so the owner had no way to make the app readable at all. Scaling is now applied at the design
/// system, which means the four-level scale has to keep its shape after scaling — a scale that
/// collapses or inverts under accessibility sizes would trade unreadable-small for incoherent.
final class TypeScaleTests: XCTestCase {

    /// The design scale, straight from HUDTheme: title / section / body / label.
    private let designSizes: [CGFloat] = [30, 19, 14, 10]

    func testScalingNeverShrinksTheDesignSize() {
        // The owner's setting can only ever make text bigger or leave it alone. A scale that could
        // shrink below the design size would make the smallest labels worse than before.
        for size in designSizes {
            XCTAssertGreaterThanOrEqual(HUDTheme.scaled(size), size, "\(size)pt shrank")
        }
    }

    func testTheFourLevelScaleStaysOrderedAfterScaling() {
        // Weight, not size, carries emphasis in this design — so if scaling ever compressed two
        // levels into the same size, the hierarchy would silently disappear.
        let scaled = designSizes.map(HUDTheme.scaled)
        for (a, b) in zip(scaled, scaled.dropFirst()) {
            XCTAssertGreaterThan(a, b, "the type scale collapsed or inverted under scaling")
        }
    }

    func testScalingIsStableForRepeatedCalls() {
        // The font helpers are called on every body evaluation; an unstable value would mean text
        // that changes size as views redraw.
        for size in designSizes {
            XCTAssertEqual(HUDTheme.scaled(size), HUDTheme.scaled(size))
        }
    }
}
