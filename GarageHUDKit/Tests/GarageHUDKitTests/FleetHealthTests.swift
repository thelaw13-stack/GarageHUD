import XCTest
@testable import GarageHUDKit

/// The Garage header's fleet service-due rollup: counts cars with overdue / due-soon maintenance,
/// skipping out-of-service ones (not being driven), across both time and mileage intervals.
final class FleetHealthTests: XCTestCase {
    private func monthsAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .month, value: -n, to: .now)! }

    private func car(_ name: String, _ items: [MaintenanceItem], odo: Int? = nil, inService: Bool = false) -> Vehicle {
        var v = Vehicle(make: "M", model: name, year: 2020, nickname: name, garageSlot: 1)
        v.maintenance = items
        if let odo { v.buildEvents = [BuildEvent(title: "Odo", mileage: odo)] }
        if inService { v.serviceStatus = ServiceStatus(isInService: true, reason: "teardown") }
        return v
    }

    func testCountsOverdueAndDueSoonSeparately() {
        // Due ~15 days out: serviced (interval − 15 days) ago, so it lands in the 30-day dueSoon window.
        let cal = Calendar.current
        let dueSoonLast = cal.date(byAdding: .day, value: 15, to: cal.date(byAdding: .month, value: -6, to: .now)!)!
        let overdueItem = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(9))
        let dueSoonItem = MaintenanceItem(name: "Filter", intervalMonths: 6, lastServiced: dueSoonLast)
        let okItem = MaintenanceItem(name: "Coolant", intervalMonths: 24, lastServiced: monthsAgo(1))

        let fleet = [car("A", [overdueItem]), car("B", [dueSoonItem]), car("C", [okItem])]
        let due = FleetHealth.serviceDue(for: fleet)
        XCTAssertEqual(due.overdue, 1)
        XCTAssertEqual(due.dueSoon, 1)
        XCTAssertEqual(due.total, 2)
    }

    func testOutOfServiceCarsAreSkipped() {
        let overdue = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))
        let fleet = [car("A", [overdue], inService: true)]
        XCTAssertEqual(FleetHealth.serviceDue(for: fleet), FleetHealth.ServiceDue(overdue: 0, dueSoon: 0))
    }

    func testMileageOverdueCounts() {
        // Time is fine, but 6,000 mi past a 5,000-mi interval → the car counts as overdue.
        let oil = MaintenanceItem(name: "Oil", intervalMonths: 12, lastServiced: monthsAgo(1),
                                  intervalMiles: 5_000, lastServicedMileage: 30_000)
        let due = FleetHealth.serviceDue(for: [car("Tundra", [oil], odo: 36_000)])
        XCTAssertEqual(due.overdue, 1)
    }

    func testEmptyFleetIsAllZero() {
        XCTAssertEqual(FleetHealth.serviceDue(for: []).total, 0)
    }
}
