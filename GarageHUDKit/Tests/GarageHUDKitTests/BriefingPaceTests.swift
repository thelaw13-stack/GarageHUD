import XCTest
@testable import GarageHUDKit

/// The briefing folds the learned driving pace into the mileage service line when a rate is known,
/// and stays silent about pace when it isn't.
final class BriefingPaceTests: XCTestCase {
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }

    private func tundra(rate: Bool) -> Vehicle {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, nickname: "Tundra", garageSlot: 1)
        // Oil due soon by mileage: 300 mi left on a 5,000-mi interval from 30,000.
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 60, lastServiced: daysAgo(1),
                                         intervalMiles: 5_000, lastServicedMileage: 30_000)]
        if rate {
            v.buildEvents = [
                BuildEvent(date: daysAgo(100), title: "Start", mileage: 30_000),
                BuildEvent(date: daysAgo(0), title: "Now", mileage: 34_700),   // rate + current 34,200
            ]
        } else {
            v.buildEvents = [BuildEvent(date: daysAgo(0), title: "Now", mileage: 34_700)]  // one reading, no rate
        }
        return v
    }

    func testPaceAppearsWhenRateKnown() {
        let summary = StewardBriefingBuilder.serviceSummary(for: [tundra(rate: true)])
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.contains("mi"), summary ?? "nil")
        XCTAssertTrue(summary!.contains("at your pace"), summary ?? "nil")
    }

    func testNoPaceWhenRateUnknown() {
        let summary = StewardBriefingBuilder.serviceSummary(for: [tundra(rate: false)])
        XCTAssertNotNil(summary)
        XCTAssertFalse(summary!.contains("at your pace"), summary ?? "nil")
    }
}
