import XCTest
@testable import GarageHUDKit

/// The service log distills completed services out of the biography — newest first — and marking an
/// item done adds one (stamped with the odometer). It also shows up in the exported build sheet.
final class ServiceLogTests: XCTestCase {
    func testMarkDoneAppendsToServiceLogWithOdometer() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.buildEvents = [BuildEvent(title: "Fill-up", mileage: 41_000)]
        let oil = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: .now)
        v.maintenance = [oil]

        XCTAssertTrue(v.serviceLog.isEmpty)
        v.markMaintenanceDone(oil.id)

        XCTAssertEqual(v.serviceLog.count, 1)
        XCTAssertTrue(v.serviceLog[0].title.hasPrefix(Vehicle.servicePrefix))
        XCTAssertTrue(v.serviceLog[0].title.contains("Oil"))
        XCTAssertTrue(v.serviceLog[0].title.contains("41,000"))   // odometer stamped in the entry
        XCTAssertEqual(v.serviceLog[0].mileage, 41_000)
    }

    func testServiceLogIsNewestFirstAndExcludesNonServiceEvents() {
        func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        v.buildEvents = [
            BuildEvent(date: day(30), title: "\(Vehicle.servicePrefix)Oil"),
            BuildEvent(date: day(10), title: "Coilovers installed"),          // not a service
            BuildEvent(date: day(5), title: "\(Vehicle.servicePrefix)Brake fluid"),
        ]
        XCTAssertEqual(v.serviceLog.map { $0.title },
                       ["\(Vehicle.servicePrefix)Brake fluid", "\(Vehicle.servicePrefix)Oil"])
    }

    @MainActor
    func testExportIncludesServiceHistorySection() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        v.buildEvents = [BuildEvent(title: "\(Vehicle.servicePrefix)Timing belt @ 120,000 mi")]
        let text = BuildSheetExporter.text(for: v)
        XCTAssertTrue(text.contains("SERVICE HISTORY"))
        XCTAssertTrue(text.contains("Timing belt"))
    }
}
