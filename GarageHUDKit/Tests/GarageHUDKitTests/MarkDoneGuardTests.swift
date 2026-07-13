import XCTest
@testable import GarageHUDKit

/// "Mark done" must not manufacture a service history that never happened: repeated taps at the same
/// day and odometer are impossible duplicates and should be no-ops.
final class MarkDoneGuardTests: XCTestCase {
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }

    private func tundra(odo: Int?) -> Vehicle {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        if let odo { v.buildEvents = [BuildEvent(date: daysAgo(1), title: "Fill-up", mileage: odo)] }
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: daysAgo(200))]
        return v
    }

    func testRepeatedMarkDoneLogsOnlyOnce() {
        var v = tundra(odo: 41_000)
        let id = v.maintenance[0].id
        XCTAssertTrue(v.markMaintenanceDone(id))    // first is real
        XCTAssertFalse(v.markMaintenanceDone(id))   // same day, same odo → refused
        XCTAssertFalse(v.markMaintenanceDone(id))   // …and again
        XCTAssertEqual(v.serviceLog.count, 1)       // exactly one service entry
    }

    func testAlreadyDoneReflectsState() {
        var v = tundra(odo: 41_000)
        let id = v.maintenance[0].id
        XCTAssertFalse(v.maintenanceAlreadyDone(id))
        v.markMaintenanceDone(id)
        XCTAssertTrue(v.maintenanceAlreadyDone(id))  // drives the disabled "Done ✓" button
    }

    func testAdvancingTheOdometerAllowsANewService() {
        var v = tundra(odo: 41_000)
        let id = v.maintenance[0].id
        v.markMaintenanceDone(id)
        XCTAssertEqual(v.serviceLog.count, 1)
        // Later fill-up moves the odometer → a genuine new service is allowed.
        v.buildEvents.append(BuildEvent(date: .now, title: "Fill-up", mileage: 46_000))
        XCTAssertFalse(v.maintenanceAlreadyDone(id))
        XCTAssertTrue(v.markMaintenanceDone(id))
        XCTAssertEqual(v.serviceLog.count, 2)
    }
}
