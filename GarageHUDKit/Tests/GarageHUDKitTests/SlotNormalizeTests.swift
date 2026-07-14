import XCTest
@testable import GarageHUDKit

/// No vehicle should ever be stranded in a hidden bay, and valid 1...8 bay assignments should
/// remain stable so an owner can intentionally keep a car in bay 5 or beyond.
@MainActor
final class SlotNormalizeTests: XCTestCase {
    func testSlotFiveIsPreservedOnLoad() throws {
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
        XCTAssertEqual(slots, [1, 2, 5], "bay 5 is visible and must not be packed down")
        XCTAssertTrue(store.vehicles.contains { $0.model == "Baja Bug" })
    }

    func testOutOfRangeAndDuplicateSlotsAreRepairedIntoOpenBays() throws {
        var a = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        a.parts = [Part(name: "x", category: .engine)]
        var b = Vehicle(make: "Subaru", model: "Forester", year: 2008, garageSlot: 1)
        b.parts = [Part(name: "y", category: .engine)]
        var c = Vehicle(make: "VW", model: "Baja Bug", year: 1970, garageSlot: 9)
        c.parts = [Part(name: "z", category: .engine)]

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ghud-slots-\(UUID()).json")
        try GaragePersistence.encode([a, b, c]).write(to: url)

        let store = GarageStore(fileURL: url, syncEnabled: false)
        let slots = store.vehicles.map(\.garageSlot)
        XCTAssertEqual(Set(slots), Set([1, 2, 3]))
        XCTAssertTrue(slots.allSatisfy { (1...GarageStore.maxGarageSlots).contains($0) })
    }
}
