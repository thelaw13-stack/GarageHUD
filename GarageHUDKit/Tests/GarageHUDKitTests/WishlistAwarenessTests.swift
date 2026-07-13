import XCTest
@testable import GarageHUDKit

/// Planning counts: a wishlist part for an open subsystem is reflected in the assessment and
/// changes the recommended next step from "go address it" to "install the one you planned".
final class WishlistAwarenessTests: XCTestCase {

    private func boostedNoBrakes() -> Vehicle {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 237)
        v.drivetrain = .rwd
        v.parts = [Part(name: "SC", category: .forcedInduction, status: .installed),
                   Part(name: "Injectors", category: .fueling, status: .installed),
                   Part(name: "Rad", category: .cooling, status: .installed),
                   Part(name: "Pistons", category: .engine, status: .installed),
                   Part(name: "Clutch", category: .drivetrain, status: .installed)]
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 477)]
        return v
    }

    func testPlannedPartMarksSubsystemAndSpend() {
        var v = boostedNoBrakes()
        v.parts.append(Part(name: "Wilwood BBK", category: .brakes, status: .wishlist, cost: 1800))
        XCTAssertTrue(v.hasPlanned(in: .brakes))
        XCTAssertEqual(v.plannedSpend, 1800, accuracy: 0.001)

        let a = Steward.assess(v)!
        let brakes = a.subsystems.first { $0.id == "Brakes" }!
        XCTAssertNotEqual(brakes.status, .supported)   // still not installed
        XCTAssertTrue(brakes.planned)                  // but planned
    }

    func testNextStepBecomesInstallThePlannedPart() {
        var v = boostedNoBrakes()
        // Without a plan → document/address braking (undocumented here → "Document braking…").
        let bare = Steward.nextStep(v)!.action
        XCTAssertTrue(bare.localizedCaseInsensitiveContains("braking"))
        XCTAssertFalse(bare.localizedCaseInsensitiveContains("planned"))
        // With a planned BBK → "install the planned braking upgrade".
        v.parts.append(Part(name: "Wilwood BBK", category: .brakes, status: .wishlist, cost: 1800))
        let step = Steward.nextStep(v)!
        XCTAssertTrue(step.action.localizedCaseInsensitiveContains("install the planned braking"))
        XCTAssertTrue(step.rationale.localizedCaseInsensitiveContains("wishlist"))
    }
}
