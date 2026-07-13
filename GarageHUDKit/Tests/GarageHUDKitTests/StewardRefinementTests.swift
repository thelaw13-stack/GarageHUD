import XCTest
@testable import GarageHUDKit

/// Refinements that make the Steward less noisy: cost-per-hp only when real power was added, and
/// "quiet build" is a plain informational note, never an urgent advisory scold.
final class StewardRefinementTests: XCTestCase {
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: .now)! }

    func testCostPerHpStaysSilentOnTinyGain() {
        // A near-stock build (dyno barely over the wheel baseline) shouldn't get a $/hp note.
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1, factoryHorsepower: 381)
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 330)]  // ~near stock at the wheels
        v.documentedTotalInvestment = 12_000
        XCTAssertFalse(Steward.observe(v).contains { $0.ruleID == "efficiency.costPerHp" })
    }

    func testCostPerHpFiresOnceRealPowerIsAdded() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 240)
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 400)]   // big gain
        v.documentedTotalInvestment = 20_000
        let cost = Steward.observe(v).first { $0.ruleID == "efficiency.costPerHp" }
        XCTAssertNotNil(cost)
        XCTAssertTrue(cost!.statement.contains("per wheel-hp"))   // leads with the figure, not "I observed…"
    }

    func testQuietBuildIsInformationalNotAdvisory() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        v.buildEvents = [BuildEvent(date: day(-400), title: "last touched")]   // long-quiet
        let quiet = Steward.observe(v).first { $0.ruleID == "build.quiet" }
        XCTAssertNotNil(quiet)
        XCTAssertEqual(quiet!.tone, .informational)              // never escalates to advisory/red
    }

    func testFreshlyAddedCarIsNeverCalledQuiet() {
        let v = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1)   // nothing logged yet
        XCTAssertFalse(Steward.observe(v).contains { $0.ruleID == "build.quiet" })
    }
}
