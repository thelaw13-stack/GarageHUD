import XCTest
@testable import GarageHUDKit

/// Duplicate record ids (from a past import/merge) are healed at the source: the first keeps its id,
/// later collisions get fresh ones — so no collection can hard-crash a ForEach or confuse sheets.
final class DedupeRecordIDsTests: XCTestCase {
    func testReassignsDuplicateBuildEventIDs() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        let shared = UUID()
        v.buildEvents = [BuildEvent(id: shared, title: "A"), BuildEvent(id: shared, title: "B")]
        XCTAssertTrue(v.dedupeRecordIDs())
        XCTAssertEqual(Set(v.buildEvents.map(\.id)).count, 2)
        XCTAssertEqual(v.buildEvents[0].id, shared)          // first occurrence keeps its id
        XCTAssertEqual(v.buildEvents.map(\.title), ["A", "B"])  // order + content preserved
    }

    func testHealsAcrossAllRecordCollections() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        let p = UUID(), m = UUID()
        v.parts = [Part(id: p, name: "X", category: .engine), Part(id: p, name: "Y", category: .engine)]
        v.maintenance = [MaintenanceItem(id: m, name: "Oil", intervalMonths: 6, lastServiced: .now),
                         MaintenanceItem(id: m, name: "Filter", intervalMonths: 6, lastServiced: .now)]
        XCTAssertTrue(v.dedupeRecordIDs())
        XCTAssertEqual(Set(v.parts.map(\.id)).count, 2)
        XCTAssertEqual(Set(v.maintenance.map(\.id)).count, 2)
    }

    func testNoOpWhenAlreadyUnique() {
        var v = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1)
        v.buildEvents = [BuildEvent(title: "A"), BuildEvent(title: "B")]
        XCTAssertFalse(v.dedupeRecordIDs())
    }
}
