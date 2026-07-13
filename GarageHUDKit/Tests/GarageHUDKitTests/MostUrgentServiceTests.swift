import XCTest
@testable import GarageHUDKit

/// Tapping the SERVICE DUE badge jumps to the most-pressing car: overdue before due-soon, and
/// within that, the earliest due date. Out-of-service cars are ignored.
final class MostUrgentServiceTests: XCTestCase {
    private func monthsAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .month, value: -n, to: .now)! }

    private func car(_ name: String, _ items: [MaintenanceItem], inService: Bool = false) -> Vehicle {
        var v = Vehicle(make: "M", model: name, year: 2020, nickname: name, garageSlot: 1)
        v.maintenance = items
        if inService { v.serviceStatus = ServiceStatus(isInService: true, reason: "teardown") }
        return v
    }

    func testOverdueBeatsDueSoon() {
        let cal = Calendar.current
        let dueSoonLast = cal.date(byAdding: .day, value: 15, to: cal.date(byAdding: .month, value: -6, to: .now)!)!
        let overdue = car("A", [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(9))])
        let dueSoon = car("B", [MaintenanceItem(name: "Filter", intervalMonths: 6, lastServiced: dueSoonLast)])
        XCTAssertEqual(FleetHealth.mostUrgent(in: [dueSoon, overdue])?.nickname, "A")
    }

    func testEarliestDueDateWinsAmongOverdue() {
        let mild = car("Mild", [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(7))])
        let worst = car("Worst", [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(24))])
        XCTAssertEqual(FleetHealth.mostUrgent(in: [mild, worst])?.nickname, "Worst")
    }

    func testOutOfServiceIgnoredAndNilWhenNothingDue() {
        let overdueButDown = car("Down", [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))],
                                 inService: true)
        let fine = car("Fine", [MaintenanceItem(name: "Coolant", intervalMonths: 24, lastServiced: monthsAgo(1))])
        XCTAssertNil(FleetHealth.mostUrgent(in: [overdueButDown, fine]))
    }
}
