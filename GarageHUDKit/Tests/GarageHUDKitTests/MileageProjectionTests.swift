import XCTest
@testable import GarageHUDKit

/// Predictive maintenance: GarageHUD learns a driving rate from odometer-stamped events and projects
/// when a mileage-based service will actually come due — the earlier of that projection and the
/// calendar interval.
final class MileageProjectionTests: XCTestCase {
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }

    // MARK: driving rate

    func testMilesPerDayFromTwoReadings() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.buildEvents = [
            BuildEvent(date: daysAgo(100), title: "Start", mileage: 30_000),
            BuildEvent(date: daysAgo(0), title: "Now", mileage: 33_000),   // 3,000 mi / 100 days
        ]
        XCTAssertEqual(v.milesPerDay ?? 0, 30, accuracy: 0.001)
    }

    func testMilesPerDayNilWithoutEnoughData() {
        var one = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1)
        one.buildEvents = [BuildEvent(date: daysAgo(10), title: "Only", mileage: 50_000)]
        XCTAssertNil(one.milesPerDay)                                       // single reading

        var flat = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        flat.buildEvents = [
            BuildEvent(date: daysAgo(30), title: "A", mileage: 88_000),
            BuildEvent(date: daysAgo(1), title: "B", mileage: 88_000),      // no miles added
        ]
        XCTAssertNil(flat.milesPerDay)
    }

    // MARK: projection

    func testProjectedMileageDueDateUsesRate() {
        // 1,000 mi remaining at 50 mi/day → ~20 days out.
        let item = MaintenanceItem(name: "Oil", intervalMonths: 60, lastServiced: daysAgo(1),
                                   intervalMiles: 5_000, lastServicedMileage: 30_000)
        let now = Date()
        let projected = item.projectedMileageDueDate(currentMileage: 34_000, milesPerDay: 50, now: now)
        let days = (projected!.timeIntervalSince(now)) / 86_400
        XCTAssertEqual(days, 20, accuracy: 0.5)
    }

    func testExpectedDueDateTakesSoonerOfTimeAndMileage() {
        let now = Date()
        // Time interval says ~60 months out; mileage projection says ~20 days → mileage wins.
        let item = MaintenanceItem(name: "Oil", intervalMonths: 60, lastServiced: now,
                                   intervalMiles: 5_000, lastServicedMileage: 30_000)
        let expected = item.expectedDueDate(currentMileage: 34_000, milesPerDay: 50, now: now)
        XCTAssertLessThan(expected.timeIntervalSince(now), 40 * 86_400)     // near the mileage projection
    }

    func testProjectionFallsBackToTimeWithoutRate() {
        let now = Date()
        let item = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: now,
                                   intervalMiles: 5_000, lastServicedMileage: 30_000)
        XCTAssertNil(item.projectedMileageDueDate(currentMileage: 34_000, milesPerDay: nil, now: now))
        // expectedDueDate with no rate → the calendar due date.
        XCTAssertEqual(item.expectedDueDate(currentMileage: 34_000, milesPerDay: nil, now: now),
                       item.dueDate())
    }

    func testAlreadyOverMileageProjectsNow() {
        let now = Date()
        let item = MaintenanceItem(name: "Oil", intervalMonths: 60, lastServiced: now,
                                   intervalMiles: 5_000, lastServicedMileage: 30_000)
        XCTAssertEqual(item.projectedMileageDueDate(currentMileage: 36_000, milesPerDay: 50, now: now), now)
    }
}
