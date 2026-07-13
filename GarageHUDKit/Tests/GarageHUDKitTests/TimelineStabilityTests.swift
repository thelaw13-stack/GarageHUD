import XCTest
@testable import GarageHUDKit

/// The timeline spine must have stable identities across rebuilds (it used to mint a fresh UUID per
/// access, churning SwiftUI's ForEach every frame) and must not choke on imported data that carries
/// a duplicate record id — the Timeline-tab crash.
final class TimelineStabilityTests: XCTestCase {
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }

    func testTimelineIDsAreStableAcrossRebuilds() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.parts = [Part(name: "Leveling kit", category: .suspension, status: .installed, installDate: daysAgo(30))]
        v.buildEvents = [BuildEvent(date: daysAgo(10), title: "Tint")]
        XCTAssertEqual(v.timeline.map(\.id), v.timeline.map(\.id))   // identical ids on a second call
    }

    func testDistinctRecordsGetDistinctIDs() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        let p = Part(name: "Coilovers", category: .suspension, status: .removed,
                     installDate: daysAgo(100), removeDate: daysAgo(5))
        v.parts = [p]   // one part yields both an install and a removal entry
        let ids = v.timeline.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "install and removal entries must not collide")
    }

    func testDuplicateEventIDsDoNotCollapseTheTimeline() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        let shared = UUID()
        v.buildEvents = [
            BuildEvent(id: shared, date: daysAgo(20), title: "A"),
            BuildEvent(id: shared, date: daysAgo(10), title: "B"),   // duplicate id from a merge/import
        ]
        // The model still lists both moments; the view keys on position so it can't crash on the dup.
        XCTAssertEqual(v.timeline.count, 2)
    }
}
