import XCTest
@testable import GarageHUDKit

/// Phase 3 — the Build Plan orders planned parts into a sensible path (support/safety before power,
/// fueling before boost), measures progress toward a stated power goal, and warns when the plan
/// outpaces its support. Same honesty rules: never invents a target, grades power by whether it's
/// measured.
final class BuildPlanTests: XCTestCase {
    private func boostedCar(goalWHP: Double? = nil) -> Vehicle {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1, factoryHorsepower: 224)
        v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed)]  // boosted now
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 300)]
        if let goalWHP { v.buildGoal = BuildGoal(summary: "Reliable street", targetWheelHP: goalWHP) }
        return v
    }

    func testEmptyWhenNoGoalAndNothingPlanned() {
        XCTAssertTrue(BuildPlanner.plan(for: boostedCar()).isEmpty)
    }

    func testSupportAndSequenceOutrankPowerInThePath() {
        var v = boostedCar()
        v.parts += [
            Part(name: "Big turbo", category: .forcedInduction, status: .wishlist, cost: 3000),   // power
            Part(name: "Injectors", category: .fueling, status: .wishlist, cost: 800),             // sequence (before boost)
            Part(name: "Big brakes", category: .brakes, status: .wishlist, cost: 2500),            // support (power is up)
        ]
        let steps = BuildPlanner.plan(for: v).steps
        XCTAssertEqual(steps.count, 3)
        // Fueling (sequence) and brakes (support) must come before the turbo (power).
        let turboIndex = steps.firstIndex { $0.category == .forcedInduction }!
        let fuelIndex = steps.firstIndex { $0.category == .fueling }!
        let brakeIndex = steps.firstIndex { $0.category == .brakes }!
        XCTAssertLessThan(fuelIndex, turboIndex)
        XCTAssertLessThan(brakeIndex, turboIndex)
        XCTAssertEqual(steps.first { $0.category == .fueling }?.priority, .sequence)
    }

    func testFuelingIsTaggedSequenceWhenBoostIsPlanned() {
        var v = Vehicle(make: "Honda", model: "Civic", year: 2000, garageSlot: 1, factoryHorsepower: 160)
        v.parts = [
            Part(name: "Turbo kit", category: .forcedInduction, status: .wishlist, cost: 4000),
            Part(name: "Fuel pump", category: .fueling, status: .wishlist, cost: 400),
        ]
        let steps = BuildPlanner.plan(for: v).steps
        XCTAssertEqual(steps.first?.category, .fueling)   // fueling leads
        XCTAssertEqual(steps.first?.priority, .sequence)
    }

    func testAdvisoryWarnsWhenBoostPlannedWithoutFueling() {
        var v = Vehicle(make: "Honda", model: "Civic", year: 2000, garageSlot: 1, factoryHorsepower: 160)
        v.parts = [Part(name: "Turbo kit", category: .forcedInduction, status: .wishlist, cost: 4000)]
        let plan = BuildPlanner.plan(for: v)
        XCTAssertNotNil(plan.advisory)
        XCTAssertTrue(plan.advisory!.localizedCaseInsensitiveContains("fueling first"))
    }

    func testProgressTowardTargetPowerIsMeasuredAware() {
        let v = boostedCar(goalWHP: 400)   // dyno 300 whp, target 400
        let progress = BuildPlanner.plan(for: v).progress
        XCTAssertEqual(progress.currentWHP, 300)
        XCTAssertEqual(progress.targetWHP, 400)
        XCTAssertTrue(progress.powerMeasured)                       // it's a dyno
        XCTAssertEqual(progress.powerFraction ?? 0, 0.75, accuracy: 0.001)
    }

    func testAtGoalAdvisorySwitchesToRefinement() {
        let v = boostedCar(goalWHP: 250)   // already at 300 whp, past the 250 goal
        XCTAssertTrue(BuildPlanner.plan(for: v).advisory!.localizedCaseInsensitiveContains("goal"))
    }

    func testProgressUsesWheelBaselineNotCrankWhenUnmeasured() {
        // A crank factory rating must not be compared against a wheel target — that overstates
        // progress. An un-dynoed RWD car rated 300 crank toward a 300 whp goal is NOT at 100%:
        // the honest current figure is the ~stock wheel baseline (~300 * (1 - RWD loss)).
        var v = Vehicle(make: "Ford", model: "Mustang", year: 2015, garageSlot: 1, factoryHorsepower: 300)
        v.drivetrain = .rwd
        v.buildGoal = BuildGoal(summary: "300 whp", targetWheelHP: 300)
        let progress = BuildPlanner.plan(for: v).progress
        XCTAssertFalse(progress.powerMeasured)
        XCTAssertEqual(progress.currentWHP ?? 0, v.estimatedStockWheelHP ?? 0, accuracy: 0.001)
        XCTAssertLessThan(progress.powerFraction ?? 1, 1.0)   // not falsely "at goal"
    }

    func testProgressNilWithoutATarget() {
        var v = boostedCar()
        v.parts += [Part(name: "Coilovers", category: .suspension, status: .wishlist, cost: 1200)]
        XCTAssertNil(BuildPlanner.plan(for: v).progress.powerFraction)   // no target set → no fraction
    }

    func testGoalPersistsThroughDecode() throws {
        var v = boostedCar(goalWHP: 450)
        let data = try JSONEncoder().encode([v])
        let restored = try JSONDecoder().decode([Vehicle].self, from: data)
        XCTAssertEqual(restored.first?.buildGoal?.targetWheelHP, 450)
        XCTAssertEqual(restored.first?.buildGoal?.summary, "Reliable street")
    }
}
