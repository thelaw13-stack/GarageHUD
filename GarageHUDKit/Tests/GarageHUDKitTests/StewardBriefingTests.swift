import XCTest
@testable import GarageHUDKit

/// The briefing rolls up every reasoning layer into one prioritized read — these pin the
/// ordering, the cap, the fleet/vehicle attribution, and driving-mode terseness.
final class StewardBriefingTests: XCTestCase {

    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: .now)! }

    /// A boosted car with no fueling/cooling/brakes → several cautions; plus a stale build.
    private func gappyCar(_ name: String, slot: Int) -> Vehicle {
        var v = Vehicle(make: "M", model: name, year: 2020, garageSlot: slot)
        v.nickname = name
        v.factoryHorsepower = 200
        v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed)]
        v.performanceRecords = [PerformanceRecord(date: day(-300), type: .dyno, wheelHorsepower: 300)]
        return v
    }

    func testEmptyGarageHasCalmHeadlineAndNoItems() {
        let brief = StewardBriefingBuilder.build(for: [])
        XCTAssertTrue(brief.items.isEmpty)
        XCTAssertTrue(brief.spokenScript.localizedCaseInsensitiveContains("nothing"))
    }

    func testBriefingIsCappedAndAdvisoryFirst() {
        let brief = StewardBriefingBuilder.build(for: [gappyCar("S2K", slot: 1), gappyCar("Fozzy", slot: 2)], limit: 4)
        XCTAssertLessThanOrEqual(brief.items.count, 4)
        XCTAssertFalse(brief.items.isEmpty)
        // Ranked: no informational should precede a caution/advisory.
        if let firstInfo = brief.items.firstIndex(where: { $0.observation.tone == .informational }),
           let lastStrong = brief.items.lastIndex(where: { $0.observation.tone != .informational }) {
            XCTAssertLessThan(firstInfo, lastStrong + 1)
            XCTAssertLessThan(lastStrong == 0 ? 0 : firstInfo, brief.items.count)
        }
        for i in brief.items.dropFirst().indices {
            // monotonic non-increasing rank
            XCTAssertGreaterThanOrEqual(rank(brief.items[i-1]), rank(brief.items[i]))
        }
    }

    func testFleetItemsAreAttributedToFleetVehiclesToCars() {
        let brief = StewardBriefingBuilder.build(for: [gappyCar("S2K", slot: 1), gappyCar("Fozzy", slot: 2)])
        XCTAssertTrue(brief.items.contains { $0.vehicleName == nil }, "expected at least one fleet-level item")
        XCTAssertTrue(brief.items.contains { $0.vehicleName != nil }, "expected at least one per-car item")
        // A per-car line reads "On <name>, ..."
        if let carItem = brief.items.first(where: { $0.vehicleName != nil }) {
            XCTAssertTrue(brief.spokenScript.contains("On \(carItem.vehicleName!),"))
        }
    }

    func testMovingModeKeepsOnlyAdvisoriesAndDropsConfidence() {
        let vehicles = [gappyCar("S2K", slot: 1), gappyCar("Fozzy", slot: 2)]
        let moving = StewardBriefingBuilder.build(for: vehicles, mode: .moving)
        XCTAssertTrue(moving.items.allSatisfy { $0.observation.tone == .advisory })
        XCTAssertFalse(moving.spokenScript.localizedCaseInsensitiveContains("confidence"))
    }

    private func rank(_ item: StewardBriefingItem) -> Int {
        switch item.observation.tone {
        case .advisory: return 200 + item.observation.confidence
        case .caution: return 100 + item.observation.confidence
        case .informational: return item.observation.confidence
        }
    }
}
