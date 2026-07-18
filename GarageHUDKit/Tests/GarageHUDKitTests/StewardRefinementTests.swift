import XCTest
@testable import GarageHUDKit

/// Refinements that make the Steward less noisy: cost-per-hp only when real power was added, and
/// "quiet build" is a plain informational note, never an urgent advisory scold.
final class StewardRefinementTests: XCTestCase {
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: .now)! }

    /// W-046 (Tim): a statistic is not a task. Cost-per-hp is permanent, unresolvable
    /// arithmetic — it must NEVER appear in the attention stream, at any gain level. It lives
    /// on Specs, in the grounding record, and in the voice's efficiency answer when asked.
    func testCostPerHpIsAStatisticNotAnObservation() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 240)
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 400)]   // big gain
        v.documentedTotalInvestment = 20_000
        XCTAssertFalse(Steward.observe(v).contains { $0.ruleID.hasPrefix("efficiency.") },
                       "no statistic in the attention stream")
        // The figure's real homes still carry it, caveats intact.
        XCTAssertTrue(StewardGrounding.record(for: v).contains("per wheel-hp [Moderate — wheel-estimate, not dyno-corrected]"))
        let spoken = StewardConversation.reply(to: "cost per hp", vehicle: v).text
        XCTAssertTrue(spoken.contains("per wheel-hp gained"), spoken)
        XCTAssertTrue(spoken.contains("not dyno-corrected"), spoken)
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
