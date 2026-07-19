import XCTest
@testable import GarageHUDKit

/// The owner-calibrated reasoning windows (Tim, 2026-07-18): sequence-lag 30 days, quiet-record
/// 90 days, and a flagged pull that stays until a later clean pull resolves it (no timer).
final class StewardWindowTests: XCTestCase {
    private func daysAgo(_ n: Int) -> Date { Date().addingTimeInterval(-Double(n) * 86_400) }

    private func supercharged(fiDaysAgo: Int, fuelDaysAgo: Int) -> Vehicle {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 237)
        v.parts = [
            Part(name: "Supercharger", category: .forcedInduction, status: .installed, installDate: daysAgo(fiDaysAgo)),
            Part(name: "Injectors", category: .fueling, status: .installed, installDate: daysAgo(fuelDaysAgo)),
        ]
        return v
    }

    func testSequenceLagFlagsAtThirtyDaysNotFourteen() {
        // 20-day gap: within one build now — no flag (would have flagged at the old 14).
        let short = Steward.observe(supercharged(fiDaysAgo: 100, fuelDaysAgo: 80))
        XCTAssertFalse(short.contains { $0.ruleID == StewardRuleID.sequenceFIAheadOfFueling })
        // 40-day gap: ran boost ahead of fueling long enough to matter.
        let long = Steward.observe(supercharged(fiDaysAgo: 100, fuelDaysAgo: 60))
        XCTAssertTrue(long.contains { $0.ruleID == StewardRuleID.sequenceFIAheadOfFueling })
    }

    func testQuietRecordFlagsAtNinetyDays() {
        func quiet(_ d: Int) -> Vehicle {
            var v = Vehicle(make: "Mazda", model: "MX-5", year: 2016, garageSlot: 1)
            v.buildEvents = [BuildEvent(date: daysAgo(d), title: "Last touched")]
            return v
        }
        XCTAssertFalse(Steward.observe(quiet(80)).contains { $0.ruleID == StewardRuleID.buildQuiet })
        XCTAssertTrue(Steward.observe(quiet(100)).contains { $0.ruleID == StewardRuleID.buildQuiet })
    }

    private func pull(daysAgo n: Int, breached: Bool) -> PullReport {
        let end = daysAgo(n)
        return PullReport(startedAt: end.addingTimeInterval(-12), endedAt: end, feedLabel: "OBD-II Adapter",
                          rpmStart: 3000, rpmPeak: 7200, rpmEnd: 7400,
                          boostPeakPsi: breached ? 21 : 16, boostBreachedCeiling: breached, boostCeilingPsi: 18,
                          onTargetFraction: nil, overTargetFraction: nil, underTargetFraction: nil,
                          coolantStartF: nil, coolantPeakF: nil, coolantDeltaF: nil,
                          sampleCount: 60, measuredBoostFraction: 1.0, confidence: .strong)
    }

    private func hasPullFlag(_ v: Vehicle) -> Bool {
        Steward.observe(v).contains { $0.ruleID.contains("pullFlagged") }
    }

    func testFlaggedPullStaysUntilResolved_noTimer() {
        var v = Vehicle(make: "Subaru", model: "WRX", year: 2015, garageSlot: 1)
        // A breach 60 days ago with nothing since — the old 14-day timer would have dropped it; it must stay.
        v.pullReports = [pull(daysAgo: 60, breached: true)]
        XCTAssertTrue(hasPullFlag(v), "a safety breach must not silently expire on a timer")
    }

    func testFlaggedPullResolvedByALaterCleanPull() {
        var v = Vehicle(make: "Subaru", model: "WRX", year: 2015, garageSlot: 1)
        v.pullReports = [pull(daysAgo: 60, breached: true), pull(daysAgo: 3, breached: false)]
        XCTAssertFalse(hasPullFlag(v), "a later clean pull shows the car running right — resolved")
        // But a later breach does NOT resolve it.
        v.pullReports = [pull(daysAgo: 60, breached: true), pull(daysAgo: 3, breached: true)]
        XCTAssertTrue(hasPullFlag(v))
    }
}
