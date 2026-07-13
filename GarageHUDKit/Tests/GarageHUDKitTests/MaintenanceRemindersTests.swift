import XCTest
@testable import GarageHUDKit

/// The reminder schedule (what to notify, when) is pure and testable independent of the
/// notification system.
final class MaintenanceRemindersTests: XCTestCase {
    private func monthsAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .month, value: -n, to: .now)! }
    private func monthsAhead(_ n: Int) -> Date { Calendar.current.date(byAdding: .month, value: n, to: .now)! }

    private func car(_ name: String, _ items: [MaintenanceItem], inService: Bool = false) -> Vehicle {
        var v = Vehicle(make: "Make", model: name, year: 2020, nickname: name, garageSlot: 1)
        v.maintenance = items
        if inService { v.serviceStatus = ServiceStatus(isInService: true, reason: "teardown") }
        return v
    }

    func testOverdueFiresSoonFutureFiresAtDue() {
        let overdue = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(8))
        let future = MaintenanceItem(name: "Coolant", intervalMonths: 24, lastServiced: monthsAgo(1))
        let now = Date()
        let reminders = MaintenanceReminders.upcoming(for: [car("Fozzy", [overdue, future])], now: now)
        XCTAssertEqual(reminders.count, 2)
        // Overdue → fires ~now (soonest), future → at its due date.
        XCTAssertEqual(reminders.first?.title, "Fozzy: Oil")
        XCTAssertLessThan(reminders[0].fireDate.timeIntervalSince(now), 120)
        XCTAssertGreaterThan(reminders[1].fireDate, now.addingTimeInterval(60))
        XCTAssertTrue(reminders[0].body.localizedCaseInsensitiveContains("overdue"))
    }

    func testOutOfServiceCarIsSkipped() {
        let item = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(8))
        let reminders = MaintenanceReminders.upcoming(for: [car("S2K", [item], inService: true)])
        XCTAssertTrue(reminders.isEmpty)
    }

    func testStableIdsAcrossRebuilds() {
        let item = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(1))
        let v = car("Fozzy", [item])
        let a = MaintenanceReminders.upcoming(for: [v])
        let b = MaintenanceReminders.upcoming(for: [v])
        XCTAssertEqual(a.map(\.id), b.map(\.id))   // rescheduling replaces, never duplicates
    }
}
