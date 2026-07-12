import XCTest
@testable import GarageHUDKit

/// Sprint E rules read the timeline, not just present state — a dyno can go stale, and a
/// round of parts can fail to show up on the rollers. These pin both directions.
final class StewardSequenceTests: XCTestCase {

    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: .now)! }

    private func base() -> Vehicle {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.factoryHorsepower = 200
        return v
    }

    // MARK: Stale tune

    func testDynoBeforeHardwareChangeIsFlaggedStale() {
        var v = base()
        v.performanceRecords = [PerformanceRecord(date: day(-90), type: .dyno, wheelHorsepower: 300)]
        v.parts = [Part(name: "Bigger injectors", category: .fueling, status: .installed, installDate: day(-20))]
        let obs = Steward.observe(v)
        let stale = obs.first { $0.statement.localizedCaseInsensitiveContains("predates your current hardware") }
        XCTAssertNotNil(stale)
        XCTAssertEqual(stale?.provenance, .derived)
    }

    func testHardwareBeforeDynoIsNotStale() {
        var v = base()
        v.parts = [Part(name: "Bigger injectors", category: .fueling, status: .installed, installDate: day(-90))]
        v.performanceRecords = [PerformanceRecord(date: day(-20), type: .dyno, wheelHorsepower: 320)]
        XCTAssertFalse(Steward.observe(v).contains { $0.statement.localizedCaseInsensitiveContains("predates your current hardware") })
    }

    func testNoStaleFlagWithoutAnyDyno() {
        var v = base()
        v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed, installDate: day(-20))]
        XCTAssertFalse(Steward.observe(v).contains { $0.statement.localizedCaseInsensitiveContains("predates") })
    }

    // MARK: Plateau

    func testPartsAddedButDynoFlatIsPlateau() {
        var v = base()
        v.performanceRecords = [
            PerformanceRecord(date: day(-120), type: .dyno, wheelHorsepower: 300),
            PerformanceRecord(date: day(-10), type: .dyno, wheelHorsepower: 302)
        ]
        v.parts = [Part(name: "Cat-back", category: .exhaust, status: .installed, installDate: day(-60))]
        let plateau = Steward.observe(v).first { $0.statement.localizedCaseInsensitiveContains("haven't shown up on the dyno") }
        XCTAssertNotNil(plateau)
        XCTAssertEqual(plateau?.provenance, .derived)
    }

    func testRealGainIsNotPlateau() {
        var v = base()
        v.performanceRecords = [
            PerformanceRecord(date: day(-120), type: .dyno, wheelHorsepower: 300),
            PerformanceRecord(date: day(-10), type: .dyno, wheelHorsepower: 360)
        ]
        v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed, installDate: day(-60))]
        XCTAssertFalse(Steward.observe(v).contains { $0.statement.localizedCaseInsensitiveContains("haven't shown up") })
    }

    func testNoPlateauWithoutPartsBetweenPulls() {
        var v = base()
        v.performanceRecords = [
            PerformanceRecord(date: day(-120), type: .dyno, wheelHorsepower: 300),
            PerformanceRecord(date: day(-10), type: .dyno, wheelHorsepower: 301)
        ]
        // part installed before both pulls, nothing changed between them
        v.parts = [Part(name: "Intake", category: .engine, status: .installed, installDate: day(-200))]
        XCTAssertFalse(Steward.observe(v).contains { $0.statement.localizedCaseInsensitiveContains("haven't shown up") })
    }
}
