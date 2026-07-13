import XCTest
@testable import GarageHUDKit

/// A captured pull ties into the same reasoning and memory the rest of GarageHUD uses: a flagged
/// pull surfaces as a Steward note (evidence-graded, not just an alarm), and recording one logs a
/// compact biography entry.
final class PullReportStewardTests: XCTestCase {
    private func report(breach: Bool = false, over: Double? = nil, daysAgo: Int = 0,
                        confidence: ConfidenceBand = .strong) -> PullReport {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return PullReport(
            startedAt: date.addingTimeInterval(-3), endedAt: date, feedLabel: "OBD-II Adapter",
            rpmStart: 3000, rpmPeak: 6500, rpmEnd: 6500,
            boostPeakPsi: breach ? 15 : 10, boostBreachedCeiling: breach, boostCeilingPsi: 14,
            onTargetFraction: over.map { 1 - $0 }, overTargetFraction: over, underTargetFraction: 0,
            coolantStartF: 195, coolantPeakF: 199, coolantDeltaF: 4,
            sampleCount: 6, measuredBoostFraction: 1.0, confidence: confidence)
    }

    func testRecordPullReportAppendsAndLogsBiography() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        let r = report()
        v.recordPullReport(r)
        XCTAssertEqual(v.pullReports.map(\.id), [r.id])
        XCTAssertTrue(v.buildEvents.contains { $0.title.contains("Pull captured") })
    }

    func testCeilingBreachSurfacesAsStewardCaution() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        v.recordPullReport(report(breach: true))
        let obs = Steward.observe(v).first { $0.ruleID.hasPrefix("live.pullFlagged") }
        XCTAssertNotNil(obs)
        XCTAssertEqual(obs!.tone, .caution)
        XCTAssertTrue(obs!.statement.localizedCaseInsensitiveContains("ceiling"))
    }

    func testHeavyOverTargetSurfacesEvenWithoutABreach() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        v.recordPullReport(report(over: 0.8))
        XCTAssertTrue(Steward.observe(v).contains { $0.ruleID.hasPrefix("live.pullFlagged") })
    }

    func testCleanPullDoesNotSurface() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        v.recordPullReport(report(over: 0.1))   // mostly on target
        XCTAssertFalse(Steward.observe(v).contains { $0.ruleID.hasPrefix("live.pullFlagged") })
    }

    func testOldFlaggedPullNoLongerSurfaces() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        v.recordPullReport(report(breach: true, daysAgo: 30))   // beyond the 14-day relevance window
        XCTAssertFalse(Steward.observe(v).contains { $0.ruleID.hasPrefix("live.pullFlagged") })
    }

    func testObservationConfidenceMatchesTheReportsOwnGrade() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        v.recordPullReport(report(breach: true, confidence: .weak))   // mostly-simulated capture
        let obs = Steward.observe(v).first { $0.ruleID.hasPrefix("live.pullFlagged") }
        XCTAssertEqual(obs?.confidence, .weak)   // never reads more certain than the run itself
    }
}
