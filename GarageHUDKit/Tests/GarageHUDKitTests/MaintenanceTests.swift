import XCTest
@testable import GarageHUDKit

/// Date-interval maintenance: due status is computed from the interval, and overdue items
/// surface as a Steward advisory (and drive the next step).
final class MaintenanceTests: XCTestCase {
    private func monthsAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .month, value: -n, to: .now)! }

    func testDueStatusTransitions() {
        XCTAssertEqual(MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(1)).due(), .ok)
        XCTAssertEqual(MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(6)).due(), .overdue)
        // ~5 months in on a 6-month interval → within 30 days of due → dueSoon.
        let almost = Calendar.current.date(byAdding: .day, value: -(6 * 30 - 20), to: .now)!
        XCTAssertEqual(MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: almost).due(), .dueSoon)
    }

    func testOverdueMaintenanceIsAnAdvisoryObservation() {
        var v = Vehicle(make: "Subaru", model: "Forester", year: 2008, garageSlot: 1)
        v.maintenance = [MaintenanceItem(name: "Oil change", intervalMonths: 6, lastServiced: monthsAgo(8))]
        let obs = Steward.observe(v).first { $0.ruleID.hasPrefix("maintenance.overdue") }
        XCTAssertNotNil(obs)
        XCTAssertEqual(obs?.tone, .advisory)
        XCTAssertTrue(obs!.statement.localizedCaseInsensitiveContains("oil change is overdue"))
        XCTAssertEqual(v.maintenanceDue(), .overdue)
    }

    func testOverdueMaintenanceBecomesNextStep() {
        var v = Vehicle(make: "Subaru", model: "Forester", year: 2008, garageSlot: 1, factoryHorsepower: 224)
        v.maintenance = [MaintenanceItem(name: "Oil change", intervalMonths: 6, lastServiced: monthsAgo(8))]
        let step = Steward.nextStep(v)!
        XCTAssertTrue(step.action.localizedCaseInsensitiveContains("overdue oil change"))
    }

    func testMaintenanceRoundTripsThroughPersistence() throws {
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        v.maintenance = [MaintenanceItem(name: "Brake fluid", intervalMonths: 24, lastServiced: monthsAgo(2))]
        let data = try GaragePersistence.encode([v])
        guard case .ok(let back) = GaragePersistence.decode(data) else { return XCTFail() }
        XCTAssertEqual(back[0].maintenance.first?.name, "Brake fluid")
        XCTAssertEqual(back[0].maintenance.first?.intervalMonths, 24)
    }
}

extension MaintenanceTests {
    func testMarkDoneLogsServiceHistory() {
        var v = Vehicle(make: "Subaru", model: "Forester", year: 2008, garageSlot: 1)
        let item = MaintenanceItem(name: "Oil change", intervalMonths: 6, lastServiced: monthsAgo(8))
        v.maintenance = [item]
        let eventsBefore = v.buildEvents.count
        v.markMaintenanceDone(item.id)
        XCTAssertEqual(v.buildEvents.count, eventsBefore + 1)
        XCTAssertTrue(v.buildEvents.last!.title.contains("Serviced: Oil change"))
        XCTAssertEqual(v.maintenanceDue(), .ok)   // clock reset
    }
}
