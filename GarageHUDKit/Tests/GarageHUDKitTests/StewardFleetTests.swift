import XCTest
@testable import GarageHUDKit

/// Fleet reasoning only fires across multiple cars and must compare them honestly — value
/// leader, neglect, and shared gaps.
final class StewardFleetTests: XCTestCase {

    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: .now)! }

    private func car(_ name: String, slot: Int) -> Vehicle {
        var v = Vehicle(make: "Make", model: name, year: 2020, garageSlot: slot)
        v.nickname = name
        return v
    }

    func testSilentWithFewerThanTwoVehicles() {
        XCTAssertTrue(Steward.observeFleet([car("Solo", slot: 1)]).isEmpty)
        XCTAssertTrue(Steward.observeFleet([]).isEmpty)
    }

    func testNamesTheValueLeader() {
        var efficient = car("S2K", slot: 1)
        efficient.factoryHorsepower = 200
        efficient.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 400)] // +200 whp
        efficient.documentedTotalInvestment = 20_000                                          // $100/whp

        var pricey = car("Fozzy", slot: 2)
        pricey.factoryHorsepower = 200
        pricey.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 300)]     // +100 whp
        pricey.documentedTotalInvestment = 30_000                                             // $300/whp

        let leader = Steward.observeFleet([pricey, efficient]).first { $0.statement.localizedCaseInsensitiveContains("most power per dollar") }
        XCTAssertNotNil(leader)
        XCTAssertTrue(leader!.statement.contains("S2K"))
        XCTAssertEqual(leader!.provenance, .derived)
    }

    func testFlagsNeglectedCarAgainstActiveOne() {
        var quiet = car("Fozzy", slot: 1)
        quiet.buildEvents = [BuildEvent(date: day(-200), title: "Last touched")]
        var active = car("S2K", slot: 2)
        active.buildEvents = [BuildEvent(date: day(-5), title: "Fresh work")]

        let neglect = Steward.observeFleet([quiet, active]).first { $0.statement.localizedCaseInsensitiveContains("fallen behind") }
        XCTAssertNotNil(neglect)
        XCTAssertTrue(neglect!.statement.contains("Fozzy"))
    }

    func testNoNeglectWhenBothActive() {
        var a = car("A", slot: 1); a.buildEvents = [BuildEvent(date: day(-5), title: "x")]
        var b = car("B", slot: 2); b.buildEvents = [BuildEvent(date: day(-10), title: "y")]
        XCTAssertFalse(Steward.observeFleet([a, b]).contains { $0.statement.localizedCaseInsensitiveContains("fallen behind") })
    }

    /// A shared gap aggregates only when it's *confirmed absent* on multiple cars — a mere
    /// undocumented omission on both must NOT become a confident fleet-wide warning.
    func testSharedGapFiresOnlyWhenConfirmedAbsent() {
        func boosted(_ name: String, _ slot: Int, confirmStock: Bool) -> Vehicle {
            var v = car(name, slot: slot)
            v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed)]
            if confirmStock { v.confirmedStockSystems = [.fueling] }
            return v
        }
        // Both merely undocumented → no fleet-level shared gap.
        let undocumented = [boosted("S2K", 1, confirmStock: false), boosted("Fozzy", 2, confirmStock: false)]
        XCTAssertFalse(Steward.observeFleet(undocumented).contains { $0.ruleID.hasPrefix("fleet.sharedGap") })

        // Both confirmed stock fueling → a real, strong shared gap.
        let confirmed = [boosted("S2K", 1, confirmStock: true), boosted("Fozzy", 2, confirmStock: true)]
        let shared = Steward.observeFleet(confirmed).first { $0.ruleID == "fleet.sharedGap.Fueling" }
        XCTAssertNotNil(shared)
        XCTAssertEqual(shared?.tone, .caution)
        XCTAssertEqual(shared?.confidence, .strong)
    }
}
