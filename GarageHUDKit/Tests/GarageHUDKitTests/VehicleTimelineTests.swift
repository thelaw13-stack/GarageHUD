import XCTest
@testable import GarageHUDKit

/// The timeline is the history spine — these pin that it merges every dated record in the
/// right order, omits undated ones, and drives the Steward's sequence reasoning.
final class VehicleTimelineTests: XCTestCase {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: .now)!
    }

    func testTimelineMergesDatedRecordsNewestFirst() {
        let d5 = day(-5), d10 = day(-10), d30 = day(-30)
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed, installDate: d30)]
        v.performanceRecords = [PerformanceRecord(date: d5, type: .dyno, wheelHorsepower: 320)]
        v.buildEvents = [BuildEvent(date: d10, title: "First start")]

        let spine = v.timeline
        XCTAssertEqual(spine.count, 3)
        XCTAssertEqual(spine.map(\.date), [d5, d10, d30]) // newest first
        XCTAssertEqual(spine.first?.kind, .performance(.dyno))
    }

    func testUndatedPartsAreOmittedFromSpine() {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = [
            Part(name: "Coilovers", category: .suspension, status: .installed, installDate: nil),
            Part(name: "Wishlist BBK", category: .brakes, status: .wishlist)
        ]
        XCTAssertTrue(v.timeline.isEmpty)
    }

    func testRemovalProducesItsOwnEntry() {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = [Part(name: "Stock exhaust", category: .exhaust, status: .removed,
                        installDate: day(-100), removeDate: day(-40))]
        let spine = v.timeline
        XCTAssertEqual(spine.count, 2)
        XCTAssertEqual(spine.first?.kind, .partRemoved(.exhaust)) // removal is newer
    }

    func testStewardFlagsForcedInductionAheadOfFueling() {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = [
            Part(name: "Turbo", category: .forcedInduction, status: .installed, installDate: day(-60)),
            Part(name: "Injectors", category: .fueling, status: .installed, installDate: day(-20))
        ]
        let obs = Steward.observe(v)
        let seq = obs.first { $0.statement.localizedCaseInsensitiveContains("ran ahead") || $0.statement.localizedCaseInsensitiveContains("ahead of the fueling") }
        XCTAssertNotNil(seq)
        XCTAssertEqual(seq?.provenance, .derived)
    }

    func testNoSequenceFlagWhenFuelingCameFirst() {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = [
            Part(name: "Turbo", category: .forcedInduction, status: .installed, installDate: day(-20)),
            Part(name: "Injectors", category: .fueling, status: .installed, installDate: day(-60))
        ]
        XCTAssertFalse(Steward.observe(v).contains { $0.statement.localizedCaseInsensitiveContains("ahead of the fueling") })
    }
}
