import XCTest
@testable import GarageHUDKit

/// The briefing rolls up every reasoning layer into one prioritized read — these pin ordering,
/// the cap, fleet/vehicle attribution, driving-mode terseness, and deterministic identity.
final class StewardBriefingTests: XCTestCase {

    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: .now)! }

    /// A boosted car, quiet for a long time (→ advisory), with a real confirmed-stock gap
    /// (→ caution) and a cost figure (→ fleet value leader + informational).
    private func gappyCar(_ name: String, slot: Int, invested: Double) -> Vehicle {
        var v = Vehicle(make: "M", model: name, year: 2020, garageSlot: slot)
        v.nickname = name
        v.factoryHorsepower = 200
        v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed)]
        v.confirmedStockSystems = [.fueling]   // a confirmed gap, not a mere undocumented one
        v.performanceRecords = [PerformanceRecord(date: day(-300), type: .dyno, wheelHorsepower: 300)]
        v.documentedTotalInvestment = invested
        return v
    }

    private func fleet() -> [Vehicle] {
        [gappyCar("S2K", slot: 1, invested: 15_000), gappyCar("Fozzy", slot: 2, invested: 25_000)]
    }

    func testEmptyGarageHasCalmHeadlineAndNoItems() {
        let brief = StewardBriefingBuilder.build(for: [])
        XCTAssertTrue(brief.items.isEmpty)
        XCTAssertTrue(brief.spokenScript.localizedCaseInsensitiveContains("nothing"))
    }

    func testBriefingIsCappedAndRankedDescending() {
        let brief = StewardBriefingBuilder.build(for: fleet(), limit: 4)
        XCTAssertLessThanOrEqual(brief.items.count, 4)
        XCTAssertFalse(brief.items.isEmpty)
        for i in brief.items.dropFirst().indices {
            XCTAssertGreaterThanOrEqual(rank(brief.items[i-1]), rank(brief.items[i]))
        }
    }

    func testFleetItemsAreAttributedToFleetVehiclesToCars() {
        let brief = StewardBriefingBuilder.build(for: fleet())
        XCTAssertTrue(brief.items.contains { $0.vehicleName == nil }, "expected at least one fleet-level item")
        XCTAssertTrue(brief.items.contains { $0.vehicleName != nil }, "expected at least one per-car item")
        if let carItem = brief.items.first(where: { $0.vehicleName != nil }) {
            XCTAssertTrue(brief.spokenScript.contains("On \(carItem.vehicleName!),"))
        }
    }

    func testMovingModeKeepsOnlyAdvisories() {
        let moving = StewardBriefingBuilder.build(for: fleet(), mode: .moving)
        XCTAssertTrue(moving.items.allSatisfy { $0.observation.tone == .advisory })
    }

    /// Rebuilding the same garage yields the same item identities (no SwiftUI churn) and the
    /// same order (total, tie-broken sort).
    func testBriefingIsDeterministic() {
        let garage = fleet()   // same vehicles both times
        let a = StewardBriefingBuilder.build(for: garage)
        let b = StewardBriefingBuilder.build(for: garage)
        XCTAssertEqual(a.items.map(\.id), b.items.map(\.id))
    }

    private func rank(_ item: StewardBriefingItem) -> Int {
        switch item.observation.tone {
        case .advisory: return 200 + item.observation.confidence.rawValue
        case .caution: return 100 + item.observation.confidence.rawValue
        case .informational: return item.observation.confidence.rawValue
        }
    }
}
