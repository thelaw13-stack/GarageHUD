import XCTest
@testable import GarageHUDKit

/// Tapping the SERVICE DUE badge jumps to the most-pressing service item: overdue before due-soon,
/// with item-level tie-breakers that account for calendar and mileage intervals.
final class MostUrgentServiceTests: XCTestCase {
    private func monthsAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .month, value: -n, to: .now)! }

    private func car(_ name: String, _ items: [MaintenanceItem], odo: Int? = nil, inService: Bool = false) -> Vehicle {
        var v = Vehicle(make: "M", model: name, year: 2020, nickname: name, garageSlot: 1)
        v.maintenance = items
        if let odo { v.buildEvents = [BuildEvent(title: "Odo", mileage: odo)] }
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

    func testMileageOnlyOverdueBeatsDueSoonCalendarService() {
        let cal = Calendar.current
        let dueSoonLast = cal.date(byAdding: .day, value: 15, to: cal.date(byAdding: .month, value: -6, to: .now)!)!
        let mileageOverdue = MaintenanceItem(name: "Oil", intervalMonths: 12, lastServiced: monthsAgo(1),
                                             intervalMiles: 5_000, lastServicedMileage: 30_000)
        let dueSoon = MaintenanceItem(name: "Filter", intervalMonths: 6, lastServiced: dueSoonLast)

        let focus = FleetHealth.mostUrgentService(in: [
            car("Calendar", [dueSoon]),
            car("Mileage", [mileageOverdue], odo: 36_000)
        ])

        XCTAssertEqual(focus?.vehicleName, "Mileage")
        XCTAssertEqual(focus?.itemName, "Oil")
        XCTAssertEqual(focus?.due, .overdue)
        XCTAssertEqual(FleetHealth.mostUrgent(in: [
            car("Calendar", [dueSoon]),
            car("Mileage", [mileageOverdue], odo: 36_000)
        ])?.nickname, "Mileage")
    }

    func testMileageOnlyDueSoonParticipatesWhenNoCalendarServiceIsDue() {
        let mileageSoon = MaintenanceItem(name: "Oil", intervalMonths: 12, lastServiced: monthsAgo(1),
                                          intervalMiles: 5_000, lastServicedMileage: 30_000)
        let fine = MaintenanceItem(name: "Coolant", intervalMonths: 24, lastServiced: monthsAgo(1))

        XCTAssertEqual(FleetHealth.mostUrgent(in: [
            car("Fine", [fine]),
            car("MileageSoon", [mileageSoon], odo: 34_700)
        ])?.nickname, "MileageSoon")
    }

    func testMostUrgentServiceReturnsTheWinningItemWithinACar() {
        let brakeFluid = MaintenanceItem(name: "Brake fluid", intervalMonths: 24, lastServiced: monthsAgo(25))
        let oil = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))

        let focus = FleetHealth.mostUrgentService(in: [car("Track car", [brakeFluid, oil])])

        XCTAssertEqual(focus?.vehicleName, "Track car")
        XCTAssertEqual(focus?.itemName, "Oil")
        XCTAssertEqual(focus?.due, .overdue)
    }
}
