import XCTest
@testable import GarageHUDKit

/// Filling a bare vehicle from a seed must keep the vehicle's identity, copy the build in, and
/// never clobber content the owner already has.
final class SeedMergeTests: XCTestCase {

    private func seedS2K() -> Vehicle {
        var s = Vehicle(make: "Honda", model: "S2000", year: 2006, trim: "AP2", nickname: "S2K",
                        garageSlot: 9, factoryHorsepower: 237)
        s.drivetrain = .rwd
        s.documentedTotalInvestment = 12_396
        s.parts = [Part(name: "Supercharger", category: .forcedInduction, cost: 5760),
                   Part(name: "ID1340s", category: .fueling, cost: 945)]
        s.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 477)]
        s.serviceStatus = ServiceStatus(isInService: true, reason: "Teardown")
        return s
    }

    func testBareVehicleGetsFilledButKeepsIdentity() {
        let bare = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        XCTAssertTrue(bare.identityMatches(seedS2K()))

        let filled = bare.filledFromSeed(seedS2K())
        XCTAssertEqual(filled.id, bare.id, "must keep the existing id for clean sync")
        XCTAssertEqual(filled.garageSlot, 1, "must keep its own slot")
        XCTAssertEqual(filled.parts.count, 2)
        XCTAssertEqual(filled.performanceRecords.first?.wheelHorsepower, 477)
        XCTAssertEqual(filled.factoryHorsepower, 237)
        XCTAssertEqual(filled.drivetrain, .rwd)
        XCTAssertEqual(filled.documentedTotalInvestment, 12_396)
        XCTAssertTrue(filled.serviceStatus.isInService)
    }

    func testExistingContentIsNotClobbered() {
        var owned = Vehicle(make: "Honda", model: "S2000", year: 2006, nickname: "My Car", garageSlot: 1,
                            factoryHorsepower: 240)
        owned.parts = [Part(name: "My own part", category: .exhaust)]
        let filled = owned.filledFromSeed(seedS2K())
        XCTAssertEqual(filled.parts.count, 1)                       // not overwritten
        XCTAssertEqual(filled.parts.first?.name, "My own part")
        XCTAssertEqual(filled.factoryHorsepower, 240)              // owner's spec wins
        XCTAssertEqual(filled.nickname, "My Car")
    }

    func testIdentityMatchIsMakeModelYear() {
        let s2k = seedS2K()
        XCTAssertFalse(s2k.identityMatches(Vehicle(make: "Honda", model: "Civic", year: 2006, garageSlot: 1)))
        XCTAssertTrue(s2k.identityMatches(Vehicle(make: "honda", model: "s2000", year: 2006, garageSlot: 1)))
    }
}
