import XCTest
@testable import GarageHUDKit

/// The confirm-factory-stock control should cover every real system, not just the three support
/// systems the Steward's gap logic uses — so a car can be fully documented as stock.
final class StockConfirmableTests: XCTestCase {
    func testCoversAllRealCategoriesExceptCatchAll() {
        let list = PartCategory.stockConfirmable
        XCTAssertFalse(list.contains(.uncategorized))
        XCTAssertEqual(Set(list), Set(PartCategory.allCases).subtracting([.uncategorized]))
    }

    func testIncludesTheSystemsPreviouslyMissing() {
        for c in [PartCategory.engine, .forcedInduction, .drivetrain, .suspension, .exhaust, .wheelsAndTires] {
            XCTAssertTrue(PartCategory.stockConfirmable.contains(c), "\(c) should be confirmable")
        }
    }

    func testStillIncludesTheSupportGapSystems() {
        for c in [PartCategory.fueling, .cooling, .brakes] {
            XCTAssertTrue(PartCategory.stockConfirmable.contains(c))
        }
    }
}
