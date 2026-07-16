import XCTest
@testable import GarageHUDKit

final class VehicleModelTests: XCTestCase {
    func testTotalInvestedTakesTheLargerOfPricedPartsAndDocumented() {
        // Partial pricing must NOT understate: with $150 priced but a $18,316 build sheet, the total
        // is the documented figure (it covers labor and parts not yet priced) — pricing one part
        // can't collapse the headline. This is the regression the earlier fix overshot into.
        var vehicle = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        vehicle.parts = [
            Part(name: "Fuel Rail", category: .fueling, cost: 150),
            Part(name: "Removed Exhaust", category: .exhaust, status: .removed, cost: 900)   // excluded
        ]
        vehicle.documentedTotalInvestment = 18_316.16
        XCTAssertEqual(vehicle.itemizedPartsCost, 150)
        XCTAssertEqual(vehicle.totalInvested, 18_316.16, accuracy: 0.001)  // documented wins — more complete
        XCTAssertFalse(vehicle.investmentIsLiveFromParts)
        XCTAssertNil(vehicle.documentedReconcileFigure)                    // documented is the total, not a note
        XCTAssertEqual(vehicle.pricedPartsSoFar, 150)                      // surfaced as "priced so far"

        // Once priced parts meet or exceed the documented figure, they take over and edits move the
        // total — the original bug (a lump sum silently overriding part edits) stays fixed.
        vehicle.parts[0].cost = 20_000
        XCTAssertEqual(vehicle.totalInvested, 20_000, accuracy: 0.001)
        XCTAssertTrue(vehicle.investmentIsLiveFromParts)
        XCTAssertEqual(vehicle.documentedReconcileFigure, 18_316.16)       // the lower lump sum, reconciled
        XCTAssertNil(vehicle.pricedPartsSoFar)
        vehicle.parts[0].cost = 24_000
        XCTAssertEqual(vehicle.totalInvested, 24_000, accuracy: 0.001)     // edit moves it immediately

        // With nothing priced, the documented lump sum stands in (a just-imported build).
        var lumpOnly = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1)
        lumpOnly.documentedTotalInvestment = 8_000
        XCTAssertEqual(lumpOnly.totalInvested, 8_000, accuracy: 0.001)
        XCTAssertFalse(lumpOnly.investmentIsLiveFromParts)
        XCTAssertNil(lumpOnly.documentedReconcileFigure)
        XCTAssertNil(lumpOnly.pricedPartsSoFar)
    }

    func testItemizedCostCountsInstalledOnly_NotWishlistOrRemoved() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        v.parts = [
            Part(name: "Installed coilovers", category: .suspension, status: .installed, cost: 1200),
            Part(name: "Planned BBK", category: .brakes, status: .wishlist, cost: 2500),      // future spend
            Part(name: "Old exhaust", category: .exhaust, status: .removed, cost: 600),       // no longer in car
        ]
        XCTAssertEqual(v.itemizedPartsCost, 1200)          // only money actually in the build
        XCTAssertEqual(v.totalInvested, 1200)
        XCTAssertEqual(v.plannedSpend, 2500)               // wishlist tracked separately
    }

    func testCurrentHorsepowerEstimatePrefersLatestDyno() {
        var vehicle = Vehicle(
            make: "Subaru",
            model: "Forester XT",
            year: 2008,
            garageSlot: 2,
            factoryHorsepower: 224
        )
        vehicle.performanceRecords = [
            PerformanceRecord(date: Date(timeIntervalSince1970: 100), type: .dyno, wheelHorsepower: 320),
            PerformanceRecord(date: Date(timeIntervalSince1970: 200), type: .dyno, wheelHorsepower: 381)
        ]

        XCTAssertEqual(vehicle.currentHorsepowerEstimate, 381)
    }

    func testBuildCompletionPercentUsesInstalledAndWishlistParts() {
        var vehicle = Vehicle(make: "Volkswagen", model: "Baja", year: 1970, garageSlot: 3)
        vehicle.parts = [
            Part(name: "Disc Brakes", category: .brakes, status: .installed),
            Part(name: "2276cc Engine", category: .engine, status: .wishlist),
            Part(name: "Dual 44s", category: .fueling, status: .wishlist)
        ]

        XCTAssertEqual(vehicle.buildCompletionPercent, 100.0 / 3.0, accuracy: 0.001)
    }
}
