import XCTest
@testable import GarageHUDKit

/// The briefing's plain-English service line — leads with the most-pressing car, tacks on a count
/// of any others, and folds into the spoken script. Nil when nothing is due.
final class BriefingServiceSummaryTests: XCTestCase {
    private func monthsAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .month, value: -n, to: .now)! }

    private func car(_ name: String, _ items: [MaintenanceItem], odo: Int? = nil) -> Vehicle {
        var v = Vehicle(make: "M", model: name, year: 2020, nickname: name, garageSlot: 1)
        v.maintenance = items
        if let odo { v.buildEvents = [BuildEvent(title: "Odo", mileage: odo)] }
        return v
    }

    func testMileageOverdueReadsInPlainEnglish() {
        let oil = MaintenanceItem(name: "Oil", intervalMonths: 12, lastServiced: monthsAgo(1),
                                  intervalMiles: 5_000, lastServicedMileage: 30_000)
        let summary = StewardBriefingBuilder.serviceSummary(for: [car("Tundra", [oil], odo: 36_000)])
        XCTAssertEqual(summary, "Tundra is 1,000 mi overdue for oil.")
    }

    func testTailCountsOtherCarsNeedingService() {
        let overdue = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))
        let alsoOverdue = MaintenanceItem(name: "Brakes", intervalMonths: 6, lastServiced: monthsAgo(10))
        let summary = StewardBriefingBuilder.serviceSummary(for: [
            car("Worst", [overdue]), car("Second", [alsoOverdue]),
        ])
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.contains("1 other car also needs service."), summary ?? "nil")
    }

    func testNilWhenNothingDue() {
        let fine = MaintenanceItem(name: "Coolant", intervalMonths: 24, lastServiced: monthsAgo(1))
        XCTAssertNil(StewardBriefingBuilder.serviceSummary(for: [car("Fine", [fine])]))
    }

    func testSummaryFoldsIntoBriefingAndScript() {
        let oil = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))
        let brief = StewardBriefingBuilder.build(for: [car("S2K", [oil])])
        XCTAssertNotNil(brief.serviceSummary)
        XCTAssertEqual(brief.headline, "1 thing for your attention.")
        XCTAssertTrue(brief.spokenScript.contains("overdue for oil"), brief.spokenScript)
    }

    func testServiceOnlyBriefingHasServiceHeadline() {
        let oil = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))
        let brief = StewardBriefingBuilder.build(for: [car("S2K", [oil])], limit: 0)
        XCTAssertEqual(brief.items.count, 0)
        XCTAssertNotNil(brief.serviceSummary)
        XCTAssertEqual(brief.headline, "Service needs attention.")
        XCTAssertTrue(brief.spokenScript.contains("overdue for oil"), brief.spokenScript)
    }

    func testMovingBriefingSuppressesServiceSummary() {
        let oil = MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))
        let brief = StewardBriefingBuilder.build(for: [car("S2K", [oil])], mode: .moving)
        XCTAssertNil(brief.serviceSummary)
        XCTAssertFalse(brief.spokenScript.contains("overdue for oil"), brief.spokenScript)
    }
}
