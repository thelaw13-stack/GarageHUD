import XCTest
@testable import GarageHUDKit

/// Spend-by-system groups priced installed parts by category, highest first, excluding removed
/// and undocumented-price parts.
final class SpendByCategoryTests: XCTestCase {
    func testGroupsAndSortsPricedParts() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        v.parts = [
            Part(name: "Supercharger", category: .forcedInduction, status: .installed, cost: 5759.75),
            Part(name: "Injectors", category: .fueling, status: .installed, cost: 945),
            Part(name: "Fuel rail", category: .fueling, status: .installed, cost: 150),
            Part(name: "Coilovers", category: .suspension, status: .installed, cost: nil),   // undocumented
            Part(name: "Old exhaust", category: .exhaust, status: .removed, cost: 800)        // removed
        ]
        let b = v.spendByCategory
        XCTAssertEqual(b.count, 2)                                   // suspension (nil) + removed excluded
        XCTAssertEqual(b[0].category, .forcedInduction)             // highest first
        XCTAssertEqual(b[0].total, 5759.75, accuracy: 0.001)
        XCTAssertEqual(b[1].category, .fueling)
        XCTAssertEqual(b[1].total, 1095, accuracy: 0.001)           // 945 + 150 grouped
    }

    func testEmptyWhenNoPricedParts() {
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        v.parts = [Part(name: "x", category: .engine, status: .installed, cost: nil)]
        XCTAssertTrue(v.spendByCategory.isEmpty)
    }
}
