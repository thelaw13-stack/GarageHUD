import XCTest
@testable import GarageHUDKit

/// No vehicle should ever be stranded in a hidden bay: slots are packed to 1…N on load.
@MainActor
final class SlotNormalizeTests: XCTestCase {
    func testSlotsArePackedContiguouslyOnLoad() throws {
        // A garage where a vehicle sits at slot 5 (beyond the visible 4) — simulating the
        // stray-vehicle situation.
        var a = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        a.parts = [Part(name: "x", category: .engine)]
        var b = Vehicle(make: "Subaru", model: "Forester", year: 2008, garageSlot: 2)
        b.parts = [Part(name: "y", category: .engine)]
        var c = Vehicle(make: "VW", model: "Baja Bug", year: 1970, garageSlot: 5)
        c.parts = [Part(name: "z", category: .engine)]

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ghud-slots-\(UUID()).json")
        try GaragePersistence.encode([a, b, c]).write(to: url)

        let store = GarageStore(fileURL: url, syncEnabled: false)
        let slots = store.vehicles.sorted { $0.garageSlot < $1.garageSlot }.map(\.garageSlot)
        XCTAssertEqual(slots, [1, 2, 3], "the slot-5 vehicle must be pulled into a visible bay")
        XCTAssertTrue(store.vehicles.contains { $0.model == "Baja Bug" })
    }
}
