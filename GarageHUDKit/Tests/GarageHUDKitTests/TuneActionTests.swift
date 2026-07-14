import XCTest
@testable import GarageHUDKit

/// The Tuner's pre-pull checks are now doors, not just diagnoses: every verify/hold check maps to a
/// concrete action, and a satisfied (ready) check offers none.
final class TuneActionTests: XCTestCase {
    private func check(_ id: String, _ state: TuneReadiness.State) -> TuneReadiness.Check {
        .init(id: id, title: "t", detail: "d", state: state)
    }

    func testReadyChecksHaveNoAction() {
        XCTAssertNil(check("condition.current", .ready).action)
        XCTAssertNil(check("support.Fueling", .ready).action)
        XCTAssertNil(check("profile.na", .ready).action)
    }

    func testMaintenanceAndServiceChecksRouteToService() {
        XCTAssertEqual(check("condition.overdue", .hold).action, .resolveMaintenance)
        XCTAssertEqual(check("condition.dueSoon", .verify).action, .resolveMaintenance)
        XCTAssertEqual(check("condition.noSchedule", .verify).action, .resolveMaintenance)
        XCTAssertEqual(check("condition.outOfService", .hold).action, .returnToService)
    }

    func testSupportChecksCarryTheirCategory() {
        XCTAssertEqual(check("support.Fueling", .verify).action, .confirmSupport(.fueling))
        XCTAssertEqual(check("support.Cooling", .hold).action, .confirmSupport(.cooling))
    }

    func testDynoAndCalibrationAndBoostMapAndFI() {
        XCTAssertEqual(check("validation.noDyno", .verify).action, .logDyno)
        XCTAssertEqual(check("validation.staleDyno", .verify).action, .logDyno)
        XCTAssertEqual(check("calibration.missing", .verify).action, .documentEngine)
        XCTAssertEqual(check("profile.unexpectedBoost", .hold).action, .confirmForcedInduction)
        XCTAssertEqual(check("profile.noBands", .verify).action, .editBoostMap)
        XCTAssertEqual(check("profile.noCeiling", .verify).action, .editBoostMap)
    }

    func testEveryActionHasALabel() {
        for a: TuneAction in [.resolveMaintenance, .returnToService, .confirmSupport(.fueling),
                              .documentEngine, .confirmForcedInduction, .logDyno, .editBoostMap] {
            XCTAssertFalse(a.label.isEmpty)
        }
    }

    func testARealBoostedCarWithGapsProducesActionableChecks() {
        // A boosted car overdue on service, no dyno, no boost map → several actionable checks.
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1, factoryHorsepower: 224)
        v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed)]
        v.confirmedStockSystems = []
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6,
                                         lastServiced: Calendar.current.date(byAdding: .month, value: -12, to: .now)!)]
        let checks = Steward.tuneReadiness(v).checks
        let actionable = checks.filter { $0.action != nil }
        XCTAssertFalse(actionable.isEmpty, "a car with real gaps should offer ways to fix them")
        XCTAssertTrue(actionable.contains { $0.action == .resolveMaintenance })
        XCTAssertTrue(actionable.contains { $0.action == .logDyno })
    }
}
