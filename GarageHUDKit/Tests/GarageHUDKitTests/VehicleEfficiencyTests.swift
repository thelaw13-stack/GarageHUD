import XCTest
@testable import GarageHUDKit

/// TD-002: the cost/efficiency math drives the numbers owners see on the Specs tab, so
/// the derivations get explicit coverage against silent regressions.
final class VehicleEfficiencyTests: XCTestCase {
    func testPowerToWeightUsesCurrentHorsepower() {
        let vehicle = Vehicle(make: "X", model: "Y", year: 2020, garageSlot: 1,
                              factoryHorsepower: 300, factoryWeightLbs: 3000)
        XCTAssertEqual(vehicle.powerToWeight ?? 0, 10, accuracy: 0.001) // 3000 / 300
    }

    func testHorsepowerGainedAndCostPerHorsepowerAreWheelNormalized() {
        var vehicle = Vehicle(make: "X", model: "Y", year: 2020, garageSlot: 1, factoryHorsepower: 200)
        vehicle.drivetrain = .rwd    // 15% loss → 170 whp estimated stock baseline
        vehicle.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 350)]
        vehicle.documentedTotalInvestment = 15_000

        XCTAssertEqual(vehicle.horsepowerGainedOverStock ?? 0, 180, accuracy: 0.001)          // 350 - 170
        XCTAssertEqual(vehicle.costPerHorsepowerGained ?? 0, 83.333, accuracy: 0.01)          // 15000 / 180
    }

    func testCostPerInstalledPartIgnoresWishlist() {
        var vehicle = Vehicle(make: "X", model: "Y", year: 2020, garageSlot: 1)
        vehicle.parts = [
            Part(name: "a", category: .engine, status: .installed),
            Part(name: "b", category: .brakes, status: .installed),
            Part(name: "c", category: .exhaust, status: .wishlist)
        ]
        vehicle.documentedTotalInvestment = 1_000
        XCTAssertEqual(vehicle.costPerInstalledPart ?? 0, 500, accuracy: 0.001) // 1000 / 2 installed
    }

    func testNonPositiveGainYieldsNilEfficiency() {
        var vehicle = Vehicle(make: "X", model: "Y", year: 2020, garageSlot: 1, factoryHorsepower: 400)
        // Estimated stock wheel baseline ≈ 340 (15% assumed). A 320 whp pull is below it →
        // no meaningful gain.
        vehicle.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 320)]
        vehicle.documentedTotalInvestment = 5_000
        XCTAssertNil(vehicle.horsepowerGainedOverStock)
        XCTAssertNil(vehicle.costPerHorsepowerGained)
    }

    func testRemovedPartsExcludedFromItemizedCost() {
        var vehicle = Vehicle(make: "X", model: "Y", year: 2020, garageSlot: 1)
        vehicle.parts = [
            Part(name: "Installed", category: .engine, status: .installed, cost: 500),
            Part(name: "Removed", category: .exhaust, status: .removed, cost: 900)
        ]
        XCTAssertEqual(vehicle.itemizedPartsCost, 500)
    }
}
