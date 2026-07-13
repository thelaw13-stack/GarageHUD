import XCTest
@testable import GarageHUDKit

/// Mileage-based maintenance: an item can come due by miles as well as by time, and whichever
/// arrives first drives the state — the way a real service schedule works.
final class MileageMaintenanceTests: XCTestCase {
    private func recent(_ months: Int = 0) -> Date {
        Calendar.current.date(byAdding: .month, value: -months, to: .now)!
    }

    private func oil(interval: Int, lastAt: Int, monthsAgo: Int = 0) -> MaintenanceItem {
        MaintenanceItem(name: "Oil", intervalMonths: 12, lastServiced: recent(monthsAgo),
                        intervalMiles: interval, lastServicedMileage: lastAt)
    }

    func testMileageOverdueEvenWhenTimeIsFine() {
        // Serviced this month (time OK) but 6,000 mi ago on a 5,000-mi interval → overdue by miles.
        let item = oil(interval: 5_000, lastAt: 30_000, monthsAgo: 0)
        XCTAssertEqual(item.due(currentMileage: 36_000), .overdue)
        XCTAssertEqual(item.milesUntilDue(currentMileage: 36_000), -1_000)
    }

    func testMileageDueSoonWithinBuffer() {
        let item = oil(interval: 5_000, lastAt: 30_000)
        XCTAssertEqual(item.due(currentMileage: 34_800), .dueSoon)   // 200 mi to go
        XCTAssertEqual(item.due(currentMileage: 33_000), .ok)        // 2,000 mi to go
    }

    func testNoMileageIntervalIgnoresOdometer() {
        let item = MaintenanceItem(name: "Coolant", intervalMonths: 24, lastServiced: recent(1))
        XCTAssertNil(item.milesUntilDue(currentMileage: 999_999))
        XCTAssertEqual(item.due(currentMileage: 999_999), .ok)       // time not up, no miles config
    }

    func testMissingOdometerFallsBackToTimeOnly() {
        let item = oil(interval: 5_000, lastAt: 30_000, monthsAgo: 0)
        XCTAssertNil(item.milesUntilDue(currentMileage: nil))
        XCTAssertEqual(item.due(currentMileage: nil), .ok)           // can't judge miles, time fine
    }

    func testMarkDoneRebaselinesMileageFromCurrentOdometer() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.buildEvents = [BuildEvent(title: "Fill-up", mileage: 41_000)]   // currentMileage = 41,000
        let item = oil(interval: 5_000, lastAt: 30_000)
        v.maintenance = [item]
        XCTAssertEqual(v.maintenanceDue(), .overdue)                 // 11,000 mi since baseline

        v.markMaintenanceDone(item.id)
        XCTAssertEqual(v.maintenance[0].lastServicedMileage, 41_000) // baseline moved to now
        XCTAssertEqual(v.maintenanceDue(), .ok)                      // reset by both time and miles
    }
}
