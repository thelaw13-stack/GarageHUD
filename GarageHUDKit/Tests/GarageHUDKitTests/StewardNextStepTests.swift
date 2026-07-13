import XCTest
@testable import GarageHUDKit

/// The next-step recommendation is a strict priority over what the data already says: rebuild
/// first, then advisory, then build-support open item, then stale tune.
final class StewardNextStepTests: XCTestCase {

    private func day(_ o: Int) -> Date { Calendar.current.date(byAdding: .day, value: o, to: .now)! }

    private func boostedS2K() -> Vehicle {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 237)
        v.drivetrain = .rwd
        v.parts = [Part(name: "SC", category: .forcedInduction, status: .installed),
                   Part(name: "Injectors", category: .fueling, status: .installed),
                   Part(name: "Rad", category: .cooling, status: .installed),
                   Part(name: "Pistons", category: .engine, status: .installed),
                   Part(name: "Clutch", category: .drivetrain, status: .installed)]   // no brakes
        v.performanceRecords = [PerformanceRecord(date: day(-30), type: .dyno, wheelHorsepower: 477)]
        return v
    }

    func testRebuildOutranksEverything() {
        var v = boostedS2K()
        v.serviceStatus = ServiceStatus(isInService: true, reason: "Engine teardown", since: day(-30),
            checklist: [ServiceTask(title: "a", isDone: true), ServiceTask(title: "b")])
        v.parts.append(Part(name: "Bearings", category: .engine, status: .installed, flaggedForRebuild: true))
        let step = Steward.nextStep(v)!
        XCTAssertTrue(step.action.localizedCaseInsensitiveContains("finish"))
        XCTAssertTrue(step.rationale.contains("1 of 2 done"))
        XCTAssertTrue(step.rationale.localizedCaseInsensitiveContains("to inspect/replace"))
        XCTAssertEqual(step.confidence, .confirmed)
    }

    func testOperationalBuildPointsAtTheOpenSupportItem() {
        // Not in service, no advisory → the assessment's open item (braking) is the next step.
        let step = Steward.nextStep(boostedS2K())!
        XCTAssertTrue(step.action.localizedCaseInsensitiveContains("braking"))
    }

    func testAdvisoryOutranksSupportGap() {
        var v = boostedS2K()
        // A real advisory (overdue maintenance) must outrank the caution-level support gap. (Quiet
        // build is only informational now — not logging isn't urgent, so it never wins the next step.)
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: day(-400))]
        let step = Steward.nextStep(v)!
        XCTAssertTrue(step.action.localizedCaseInsensitiveContains("overdue"))
    }

    func testNilWhenNothingPressing() {
        var v = Vehicle(make: "Honda", model: "Civic", year: 2022, garageSlot: 1, factoryHorsepower: 158)
        v.buildEvents = [BuildEvent(date: day(-2), title: "drive")]
        XCTAssertNil(Steward.nextStep(v))
    }
}
