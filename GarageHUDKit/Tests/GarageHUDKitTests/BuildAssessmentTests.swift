import XCTest
@testable import GarageHUDKit

/// The Build Assessment synthesizes support-vs-power coherence from the knowledge model —
/// honestly (undocumented ≠ missing) and only for a genuinely modified build.
final class BuildAssessmentTests: XCTestCase {

    private func s2kLikeBuild() -> Vehicle {
        // Mirrors Tim's S2K: forced induction + matched fueling/cooling/internals/clutch, no
        // brakes logged, ~276 whp over stock.
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 237)
        v.drivetrain = .rwd
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 477)]
        v.parts = [
            Part(name: "Supercharger", category: .forcedInduction, status: .installed),
            Part(name: "ID1340s", category: .fueling, status: .installed),
            Part(name: "Koyo radiator", category: .cooling, status: .installed),
            Part(name: "CP pistons", category: .engine, status: .installed),
            Part(name: "SoS clutch", category: .drivetrain, status: .installed),
        ]
        return v
    }

    func testS2KBuildIsStrongWithBrakesTheOpenItem() {
        let a = Steward.assess(s2kLikeBuild())!
        // Fueling, cooling, internals, drivetrain supported; braking undocumented.
        let byId = Dictionary(uniqueKeysWithValues: a.subsystems.map { ($0.id, $0.status) })
        XCTAssertEqual(byId["Fueling"], .supported)
        XCTAssertEqual(byId["Cooling"], .supported)
        XCTAssertEqual(byId["Engine"], .supported)
        XCTAssertEqual(byId["Drivetrain"], .supported)
        XCTAssertEqual(byId["Brakes"], .undocumented)
        XCTAssertTrue(a.headline.localizedCaseInsensitiveContains("braking isn't documented"))
        XCTAssertEqual(a.confidence, .moderate)          // rests on undocumented braking
        XCTAssertTrue(a.powerSummary.contains("477 whp"))
    }

    func testFullySupportedBuildReadsStrong() {
        var v = s2kLikeBuild()
        v.parts.append(Part(name: "BBK", category: .brakes, status: .installed))
        let a = Steward.assess(v)!
        XCTAssertTrue(a.subsystems.allSatisfy { $0.status == .supported })
        XCTAssertTrue(a.headline.localizedCaseInsensitiveContains("well-supported"))
        XCTAssertEqual(a.confidence, .strong)
    }

    func testConfirmedStockBrakesIsAnOpenItemNotUndocumented() {
        var v = s2kLikeBuild()
        v.confirmedStockSystems = [.brakes]
        let a = Steward.assess(v)!
        XCTAssertEqual(a.subsystems.first { $0.id == "Brakes" }?.status, .openItem)
        XCTAssertTrue(a.headline.localizedCaseInsensitiveContains("open item"))
    }

    func testUnmodifiedCarHasNoAssessment() {
        var v = Vehicle(make: "Honda", model: "Civic", year: 2020, garageSlot: 1, factoryHorsepower: 158)
        v.parts = [Part(name: "Floor mats", category: .interior, status: .installed)]
        XCTAssertNil(Steward.assess(v))
    }

    func testEmptyRecordHasNoAssessment() {
        XCTAssertNil(Steward.assess(Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)))
    }

    func testInternalsOnlyRelevantAtRealPower() {
        // Mild FI, small gain → internals not demanded, so no engine subsystem row.
        var v = Vehicle(make: "Mazda", model: "MX-5", year: 2016, garageSlot: 1, factoryHorsepower: 155)
        v.drivetrain = .rwd
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 180)] // +~48 whp
        v.parts = [Part(name: "Small turbo", category: .forcedInduction, status: .installed),
                   Part(name: "Injectors", category: .fueling, status: .installed)]
        let a = Steward.assess(v)!
        XCTAssertFalse(a.subsystems.contains { $0.id == "Engine" })
    }
}
