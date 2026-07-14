import XCTest
@testable import GarageHUDKit

final class VehicleModelTests: XCTestCase {
    func testTotalInvestedIsLiveFromPricedPartsWithDocumentedFallback() {
        var vehicle = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        vehicle.parts = [
            Part(name: "Fuel Rail", category: .fueling, cost: 150),
            Part(name: "Removed Exhaust", category: .exhaust, status: .removed, cost: 900)   // excluded
        ]
        XCTAssertEqual(vehicle.itemizedPartsCost, 150)

        // Priced parts drive the total — a documented lump sum no longer silently overrides them,
        // so editing a part price actually moves the number.
        vehicle.documentedTotalInvestment = 18_316.16
        XCTAssertEqual(vehicle.totalInvested, 150, accuracy: 0.001)
        XCTAssertTrue(vehicle.investmentIsLiveFromParts)
        XCTAssertEqual(vehicle.documentedTotalMismatch, 18_316.16)   // both surfaced, not hidden

        // Editing the part price moves the total immediately (the bug that started this).
        vehicle.parts[0].cost = 400
        XCTAssertEqual(vehicle.totalInvested, 400, accuracy: 0.001)

        // With nothing priced, the documented lump sum stands in (a just-imported build).
        var lumpOnly = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1)
        lumpOnly.documentedTotalInvestment = 8_000
        XCTAssertEqual(lumpOnly.totalInvested, 8_000, accuracy: 0.001)
        XCTAssertFalse(lumpOnly.investmentIsLiveFromParts)
        XCTAssertNil(lumpOnly.documentedTotalMismatch)
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
