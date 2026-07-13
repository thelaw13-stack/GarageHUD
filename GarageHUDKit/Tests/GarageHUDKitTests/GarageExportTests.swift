import XCTest
@testable import GarageHUDKit

/// A garage backup must be a valid, re-importable snapshot of the fleet.
@MainActor
final class GarageExportTests: XCTestCase {
    func testExportRoundTrips() throws {
        let store = GarageStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ghud-export-\(UUID()).json"), syncEnabled: false)
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, nickname: "S2K", garageSlot: 1)
        v.parts = [Part(name: "Supercharger", category: .forcedInduction, cost: 5760)]
        store.vehicles = [v]

        let data = store.exportData()
        guard case .ok(let restored) = GaragePersistence.decode(data) else { return XCTFail("not decodable") }
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].nickname, "S2K")
        XCTAssertEqual(restored[0].parts.first?.cost, 5760)
    }
}
