import XCTest
@testable import GarageHUDKit

/// Parts flagged for a rebuild surface through the vehicle and into the Steward's in-service note.
final class PartFlagTests: XCTestCase {
    func testFlaggedPartsExcludeRemovedAndSurface() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        v.parts = [
            Part(name: "Rod bearings", category: .engine, status: .installed, flaggedForRebuild: true),
            Part(name: "Main bearings", category: .engine, status: .installed, flaggedForRebuild: true),
            Part(name: "Old flywheel", category: .drivetrain, status: .removed, flaggedForRebuild: true),
            Part(name: "Turbo", category: .forcedInduction, status: .installed)
        ]
        XCTAssertEqual(v.partsFlaggedForRebuild.count, 2)   // removed excluded, unflagged excluded
    }

    func testInServiceObservationReportsFlaggedCount() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        v.parts = [Part(name: "Rod bearings", category: .engine, status: .installed, flaggedForRebuild: true)]
        v.serviceStatus = ServiceStatus(isInService: true, reason: "Teardown")
        let svc = Steward.observe(v).first { $0.ruleID == "service.inService" }
        XCTAssertTrue(svc!.evidence.localizedCaseInsensitiveContains("1 part flagged"))
    }

    func testFlagRoundTripsThroughPersistence() throws {
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        v.parts = [Part(name: "Bearings", category: .engine, flaggedForRebuild: true)]
        let data = try GaragePersistence.encode([v])
        guard case .ok(let back) = GaragePersistence.decode(data) else { return XCTFail() }
        XCTAssertTrue(back[0].parts[0].flaggedForRebuild)
    }
}
