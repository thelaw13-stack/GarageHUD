import XCTest
@testable import GarageHUDKit

final class VehicleModelTests: XCTestCase {
    func testDocumentedTotalInvestmentOverridesItemizedPartsCost() {
        var vehicle = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        vehicle.parts = [
            Part(name: "Fuel Rail", category: .fueling, cost: 150),
            Part(name: "Removed Exhaust", category: .exhaust, status: .removed, cost: 900)
        ]

        XCTAssertEqual(vehicle.itemizedPartsCost, 150)

        vehicle.documentedTotalInvestment = 18_316.16
        XCTAssertEqual(vehicle.totalInvested, 18_316.16, accuracy: 0.001)
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
