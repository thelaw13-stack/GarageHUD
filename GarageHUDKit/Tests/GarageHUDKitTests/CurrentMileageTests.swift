import XCTest
@testable import GarageHUDKit

/// The odometer is derived from build history — the mileage on the most recent event that recorded
/// one — rather than stored separately, so it can't drift out of sync with the timeline.
final class CurrentMileageTests: XCTestCase {
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }

    func testUsesMostRecentEventWithMileage() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.buildEvents = [
            BuildEvent(date: daysAgo(200), title: "Bought", mileage: 30_000),
            BuildEvent(date: daysAgo(30), title: "Leveling kit", mileage: 41_500),
            BuildEvent(date: daysAgo(90), title: "Tint", mileage: 38_000),
        ]
        XCTAssertEqual(v.currentMileage, 41_500)   // latest by date, not largest overall
    }

    func testIgnoresEventsWithoutMileage() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        v.buildEvents = [
            BuildEvent(date: daysAgo(10), title: "Detail"),        // no odo
            BuildEvent(date: daysAgo(50), title: "Coilovers", mileage: 88_200),
        ]
        XCTAssertEqual(v.currentMileage, 88_200)
    }

    func testNilWhenNoMileageEverRecorded() {
        var v = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1)
        v.buildEvents = [BuildEvent(title: "Acquired")]
        XCTAssertNil(v.currentMileage)
    }

    func testSameDayTieTakesHigherReading() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        let day = daysAgo(5)
        v.buildEvents = [
            BuildEvent(date: day, title: "Morning note", mileage: 120_000),
            BuildEvent(date: day, title: "Evening drive", mileage: 120_140),
        ]
        XCTAssertEqual(v.currentMileage, 120_140)
    }
}
